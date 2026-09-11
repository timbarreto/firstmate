# windows-process.ps1 - native process facts and owned watch-arm termination.
#
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this-script>
#        parent-processes|process-info|find-watch-arm-roots|stop-watch-arm-tree
# Facts: FM_PROCESS_NATIVE_PID selects a native PID. process-info prints its row;
# parent-processes prints up to 16 ancestors, nearest first, excluding that PID.
# Rows are PID<TAB>executable-path-or-name<TAB>command-line. Paths use /; embedded
# tabs/newlines are flattened so command-line data cannot introduce another row.
# Facts return 0 on a successful query, 3 for an absent process-info PID, and 2
# for invalid input, failed queries, or an unresolvable ancestry root. Each call
# queries fresh facts; parent links stop before a missing or reused parent PID.
# Watch-arm: FM_WATCH_ARM_ROOT_PID (native PID), FM_WATCH_ARM_OWNER_TOKEN (optional).
# A root must name fm-watch-arm.sh and match the PID or literal owner token.
# Each operation takes one fresh process-table snapshot. Stop expands descendants
# in that snapshot and targets only those IDs, youngest first; no cache is used.
# Find prints native PIDs. Stop returns 3 if no matching root exists, otherwise 0.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("parent-processes", "process-info", "find-watch-arm-roots", "stop-watch-arm-tree")]
    [string] $Operation
)

if ($Operation -eq "parent-processes" -or $Operation -eq "process-info") {
    $ErrorActionPreference = "Stop"
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $nativePid = 0
    if ($env:FM_PROCESS_NATIVE_PID -notmatch '^[0-9]+$' -or
        -not [int]::TryParse($env:FM_PROCESS_NATIVE_PID, [ref]$nativePid) -or $nativePid -le 1) {
        exit 2
    }

    function Format-ProcessRow($Process) {
        $command = [string]$Process.ExecutablePath
        if (-not $command) { $command = [string]$Process.Name }
        if (-not $command) { throw "Process executable is unavailable" }
        $command = $command.Replace('\', '/').Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
        $arguments = ([string]$Process.CommandLine).Replace('\', '/').Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
        "{0}`t{1}`t{2}" -f $Process.ProcessId, $command, $arguments
    }

    try {
        if ($Operation -eq "process-info") {
            $processes = @(Get-CimInstance Win32_Process -Filter "ProcessId = $nativePid" -OperationTimeoutSec 5)
            if ($processes.Count -eq 0) { exit 3 }
            if ($processes.Count -ne 1 -or [int]$processes[0].ProcessId -ne $nativePid) { exit 2 }
            Format-ProcessRow $processes[0]
            exit 0
        }

        $byPid = @{}
        foreach ($process in @(Get-CimInstance Win32_Process -OperationTimeoutSec 5)) {
            $byPid[[int]$process.ProcessId] = $process
        }
        if (-not $byPid.ContainsKey($nativePid)) { exit 2 }
        $child = $byPid[$nativePid]
        $seen = [System.Collections.Generic.HashSet[int]]::new()
        [void]$seen.Add($nativePid)
        $rows = [System.Collections.Generic.List[string]]::new()
        for ($depth = 0; $depth -lt 16; $depth++) {
            $parentPid = [int]$child.ParentProcessId
            if ($parentPid -le 1 -or -not $byPid.ContainsKey($parentPid)) { break }
            if (-not $seen.Add($parentPid)) { exit 2 }
            $parent = $byPid[$parentPid]
            # Windows retains a dead parent's numeric PID. Its new occupant is
            # not an ancestor, even if it happens to have a harness-like name.
            if (-not $child.CreationDate -or -not $parent.CreationDate) { exit 2 }
            if ($parent.CreationDate -gt $child.CreationDate) { break }
            $rows.Add((Format-ProcessRow $parent))
            $child = $parent
        }
        $rows | ForEach-Object { Write-Output $_ }
        exit 0
    } catch {
        exit 2
    }
}

$rootPid = [int]$env:FM_WATCH_ARM_ROOT_PID
$ownerToken = $env:FM_WATCH_ARM_OWNER_TOKEN
$escapedToken = [regex]::Escape($ownerToken)
$all = Get-CimInstance Win32_Process
$roots = @($all | Where-Object {
    ($_.CommandLine -match 'fm-watch-arm\.sh') -and
    (([int]$_.ProcessId -eq $rootPid) -or ($ownerToken -and $_.CommandLine -match $escapedToken))
})

if ($Operation -eq "find-watch-arm-roots") {
    $roots | ForEach-Object { Write-Output ([int]$_.ProcessId) }
    exit 0
}
if (-not $roots) {
    exit 3
}
$ids = [System.Collections.Generic.HashSet[int]]::new()
foreach ($root in $roots) {
    [void]$ids.Add([int]$root.ProcessId)
}
do {
    $before = $ids.Count
    foreach ($candidate in $all) {
        if ($ids.Contains([int]$candidate.ParentProcessId)) {
            [void]$ids.Add([int]$candidate.ProcessId)
        }
    }
} while ($ids.Count -gt $before)
foreach ($candidate in ($all | Where-Object { $ids.Contains([int]$_.ProcessId) } | Sort-Object CreationDate -Descending)) {
    Stop-Process -Id $candidate.ProcessId -Force -ErrorAction SilentlyContinue
}

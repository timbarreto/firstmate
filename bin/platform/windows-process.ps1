# windows-process.ps1 - native process facts and owned watch-arm termination.
#
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this-script>
#        parent-processes|process-info|descendant-processes|find-watch-arm-roots|stop-watch-arm-tree
# Facts: FM_PROCESS_NATIVE_PID selects a native PID. process-info prints its row;
# parent-processes prints up to 16 ancestors, nearest first, excluding that PID.
# descendant-processes includes the native root and its birth-verified descendants
# from one CIM snapshot, with at most 4096 rows. -MsysPs names the calling MSYS
# installation's ps.exe: its fresh PID/PPID/WINPID snapshot supplements native
# parent links lost during exec. Only exact WINPID mappings present in CIM and
# born before that MSYS snapshot may add edges; names and cwd never add ownership.
# Missing/failed/malformed MSYS evidence refuses rather than proving absence.
# Rows add UTC creation ticks after the PID: PID<TAB>birth<TAB>executable<TAB>args.
# Incomplete/ambiguous proof returns 2 without partial rows. No termination occurs.
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
    [ValidateSet("parent-processes", "process-info", "descendant-processes", "find-watch-arm-roots", "stop-watch-arm-tree")]
    [string] $Operation,
    [string] $MsysPs = ""
)

if ($Operation -in @("parent-processes", "process-info", "descendant-processes")) {
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

        $msysByPid = @{}
        $msysSnapshotAt = [datetime]::UtcNow
        if ($MsysPs) {
            if ($Operation -ne "descendant-processes") { exit 2 }
            $msysRows = @(& $MsysPs -e -l)
            if ($LASTEXITCODE -ne 0 -or $msysRows.Count -lt 2 -or
                $msysRows[0] -notmatch '^\s*PID\s+PPID\s+PGID\s+WINPID\b') { exit 2 }
            $nativeIds = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($line in $msysRows | Select-Object -Skip 1) {
                # ps may prefix a process-state letter before the PID columns.
                if ($line -notmatch '^\s*(?:[A-Z]\s+)?([0-9]+)\s+([0-9]+)\s+[0-9]+\s+([0-9]+)\s') { exit 2 }
                $logicalPid = [int]$Matches[1]
                $logicalParent = [int]$Matches[2]
                $winPid = [int]$Matches[3]
                if ($logicalPid -le 0 -or $winPid -le 1 -or $msysByPid.ContainsKey($logicalPid) -or
                    -not $nativeIds.Add($winPid)) { exit 2 }
                $msysByPid[$logicalPid] = [pscustomobject]@{ Parent = $logicalParent; Native = $winPid }
            }
        }

        $byPid = @{}
        foreach ($process in @(Get-CimInstance Win32_Process -OperationTimeoutSec 5)) {
            if ($byPid.ContainsKey([int]$process.ProcessId)) { exit 2 }
            $byPid[[int]$process.ProcessId] = $process
        }
        if (-not $byPid.ContainsKey($nativePid)) { exit 2 }
        if ($Operation -eq "descendant-processes") {
            $children = @{}
            foreach ($process in $byPid.Values) {
                $parentId = [int]$process.ParentProcessId
                if (-not $children.ContainsKey($parentId)) {
                    $children[$parentId] = [System.Collections.Generic.List[object]]::new()
                }
                $children[$parentId].Add([pscustomobject]@{ Process = $process; Msys = $false })
            }
            foreach ($logical in $msysByPid.Values) {
                $parent = $msysByPid[$logical.Parent]
                if (-not $parent -or -not $byPid.ContainsKey($parent.Native)) { continue }
                if (-not $children.ContainsKey($parent.Native)) {
                    $children[$parent.Native] = [System.Collections.Generic.List[object]]::new()
                }
                $children[$parent.Native].Add([pscustomobject]@{ Process = $byPid[$logical.Native]; Msys = $true })
            }
            # The two tables can prove the same child by different paths.
            # DFS colors deduplicate those paths but still refuse actual cycles.
            $root = $byPid[$nativePid]
            if ($MsysPs -and (-not $root.CreationDate -or
                $root.CreationDate.ToUniversalTime() -gt $msysSnapshotAt)) { exit 2 }
            $pending = [System.Collections.Generic.Stack[object]]::new()
            $pending.Push([pscustomobject]@{ Process = $root; Leaving = $false })
            $colors = @{}
            $resultRows = [System.Collections.Generic.List[string]]::new()
            while ($pending.Count -gt 0) {
                $entry = $pending.Pop()
                $parent = $entry.Process
                $parentId = [int]$parent.ProcessId
                if ($entry.Leaving) { $colors[$parentId] = 2; continue }
                if ($colors[$parentId] -eq 1) { exit 2 }
                if ($colors[$parentId] -eq 2) { continue }
                $colors[$parentId] = 1
                if ($colors.Count -gt 4096 -or -not $parent.CreationDate) { exit 2 }
                $row = Format-ProcessRow $parent
                $firstTab = $row.IndexOf("`t")
                $resultRows.Add($row.Substring(0, $firstTab) + "`t" +
                    $parent.CreationDate.ToUniversalTime().Ticks + $row.Substring($firstTab))
                $pending.Push([pscustomobject]@{ Process = $parent; Leaving = $true })
                foreach ($edge in $children[$parentId]) {
                    $child = $edge.Process
                    # A reachable MSYS process that disappeared before CIM may
                    # be mid-exec, with surviving children under a new WINPID.
                    # That incomplete observation cannot prove an empty pane.
                    if (-not $child -or -not $child.CreationDate) { exit 2 }
                    if ($edge.Msys -and ($parent.CreationDate.ToUniversalTime() -gt $msysSnapshotAt -or
                        $child.CreationDate.ToUniversalTime() -gt $msysSnapshotAt)) { exit 2 }
                    # A retained numeric parent ID may now belong to a younger
                    # process. Such an old child is not this root's descendant.
                    if ($child.CreationDate -ge $parent.CreationDate) {
                        $pending.Push([pscustomobject]@{ Process = $child; Leaving = $false })
                    }
                }
            }
            $resultRows | ForEach-Object { Write-Output $_ }
            exit 0
        }
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
    ($_.CommandLine -match 'fm-(?:watch-arm|supervision-host)\.sh') -and
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

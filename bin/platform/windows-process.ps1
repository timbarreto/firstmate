# windows-process.ps1 - bounded native watch-arm discovery and tree termination.
#
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this-script>
#        find-watch-arm-roots|stop-watch-arm-tree
# Inputs: FM_WATCH_ARM_ROOT_PID (native PID), FM_WATCH_ARM_OWNER_TOKEN (optional).
# A root must name fm-watch-arm.sh and match the PID or literal owner token.
# Each operation takes one fresh process-table snapshot. Stop expands descendants
# in that snapshot and targets only those IDs, youngest first; no cache is used.
# Find prints native PIDs. Stop returns 3 if no matching root exists, otherwise 0.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("find-watch-arm-roots", "stop-watch-arm-tree")]
    [string] $Operation
)

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

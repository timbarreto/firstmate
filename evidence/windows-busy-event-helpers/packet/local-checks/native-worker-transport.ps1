# Task-scoped diagnostic: existing resolver and an empty child control only.
. (Join-Path $env:WF_CODE 'bin/fm-windows-git-bash.ps1')
$bash = Resolve-FirstmateGitBash
Write-Output ('resolved=' + $bash)
& $bash -c 'exit 7'
Write-Output ('control_exit=' + $LASTEXITCODE)
& (Join-Path $env:WF_CODE 'bin/fm-ghcp-hook.ps1') worker-event $env:WF_STATE task g.fixture busy user-prompt-submitted -
Write-Output ('hook_exit=' + $LASTEXITCODE)

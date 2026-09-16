# Windows transport for GitHub Copilot CLI repository hooks.
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $HookArguments
)

# Command policies already have native Node owners. Do not load or launch a
# Bash transport for them; the other lifecycle hooks retain their Bash owners.
if ($HookArguments.Count -ge 2 -and $HookArguments[0] -eq 'pretool' -and
    $HookArguments[1] -in @('arm', 'cd')) {
    if ($env:COPILOT_CLI -ne '1') { exit 0 }
    $policyScript = Join-Path $PSScriptRoot 'fm-copilot-command-check.mjs'
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$node -or !(Test-Path -LiteralPath $policyScript -PathType Leaf)) { exit 0 }
    $payload = [Console]::In.ReadToEnd()
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $payload | & $node.Source $policyScript $HookArguments[1] 2>$null
    exit 0
}

. (Join-Path $PSScriptRoot "fm-windows-git-bash.ps1")

try {
    $bash = Resolve-FirstmateGitBash
}
catch {
    exit 0
}

$payload = [Console]::In.ReadToEnd()
$script = Join-Path $PSScriptRoot "fm-ghcp-hook.sh"
if ($HookArguments.Count -eq 1 -and $HookArguments[0] -eq 'primary-stop') {
    # The stop owner binds the native event itself; avoid a second Bash entry
    # and payload parse inside this short, nonblocking callback.
    $script = Join-Path $PSScriptRoot 'fm-copilot-stop.sh'
    $HookArguments = @()
}
if ($payload) {
    $payload | & $bash $script @HookArguments
}
else {
    & $bash $script @HookArguments
}
exit $LASTEXITCODE

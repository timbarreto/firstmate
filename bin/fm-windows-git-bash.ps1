# fm-windows-git-bash.ps1 - resolve or run Git Bash without relying on PATH order.
#
# Usage:
#   . .\bin\fm-windows-git-bash.ps1
#   Resolve-FirstmateGitBash
#
#   .\bin\fm-windows-git-bash.ps1 <bash-argument> [<bash-argument> ...]
#
# Dot-source the script to use Resolve-FirstmateGitBash from another PowerShell
# script. Execute it with Bash arguments to run the resolved Git for Windows
# Bash directly instead of an ambient bash.exe that may be the WSL launcher.
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $GitBashArguments
)

function Resolve-FirstmateGitBash {
    [CmdletBinding()]
    param()

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    function Find-GitBashCandidate([string]$Path) {
        if ($Path -and $seenPaths.Add($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $Path).Path
        }
    }
    function Find-GitBashRoot([string]$Root) {
        foreach ($relative in @('bin\bash.exe', 'usr\bin\bash.exe')) {
            $found = Find-GitBashCandidate (Join-Path $Root $relative)
            if ($found) { return $found }
        }
    }
    # Preserve the original candidate order, but stop at the first valid Git
    # installation instead of probing every alias and registry key first.
    foreach ($gitCommand in @(Get-Command 'git.exe' -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $found = Find-GitBashRoot (Split-Path -Parent (Split-Path -Parent $gitCommand.Source))
        if ($found) { return $found }
        $gitItem = Get-Item -LiteralPath $gitCommand.Source -ErrorAction SilentlyContinue
        if ($gitItem) {
            $targetProperty = $gitItem.PSObject.Properties['Target']
            if ($targetProperty -and $targetProperty.Value) {
                foreach ($target in @($targetProperty.Value)) {
                    if (-not [IO.Path]::IsPathRooted($target)) {
                        $target = Join-Path $gitItem.DirectoryName $target
                    }
                    $found = Find-GitBashRoot (Split-Path -Parent (Split-Path -Parent $target))
                    if ($found) { return $found }
                }
            }
        }
    }
    foreach ($registryKey in @('HKLM:\SOFTWARE\GitForWindows', 'HKLM:\SOFTWARE\WOW6432Node\GitForWindows', 'HKCU:\SOFTWARE\GitForWindows')) {
        $gitProperties = Get-ItemProperty -LiteralPath $registryKey -Name 'InstallPath' -ErrorAction SilentlyContinue
        if ($gitProperties -and $gitProperties.InstallPath) {
            $found = Find-GitBashRoot $gitProperties.InstallPath
            if ($found) { return $found }
        }
    }
    foreach ($candidate in @((Join-Path $env:ProgramFiles 'Git\bin\bash.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'))) {
        $found = Find-GitBashCandidate $candidate
        if ($found) { return $found }
    }

    throw "Git Bash was not found. Run .\bin\fm-install-windows.ps1 to install Git for Windows, then retry."
}

if ($MyInvocation.InvocationName -eq ".") {
    return
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $GitBashArguments -or $GitBashArguments[0] -in @("-h", "--help")) {
    Write-Output "usage: fm-windows-git-bash.ps1 <bash-argument> [<bash-argument> ...]"
    if (-not $GitBashArguments) {
        exit 2
    }
    exit 0
}

$gitBashPath = Resolve-FirstmateGitBash
& $gitBashPath @GitBashArguments
exit $LASTEXITCODE

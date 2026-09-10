# Native ACL policy owner. Paths arrive only as environment data.
# PR validation deliberately omits Force and does not require a FullControl ACE.
# X includes hidden paths and requires a current-user FullControl Allow ACE.
# Worker/Herdr require directories and allowed principals, not FullControl.
# Secure operations preserve ownership and re-read the applied descriptor.
$ErrorActionPreference = "Stop"
$policy = $env:FM_PRIVATE_PATH_POLICY
$action = $env:FM_PRIVATE_PATH_ACTION
$kind = $env:FM_PRIVATE_PATH_KIND
if ($env:FM_PRIVATE_PATH_COUNT -notmatch '^[1-3]$') { exit 1 }
$count = [int]$env:FM_PRIVATE_PATH_COUNT
switch ("$policy/$action/$kind") {
    "pr/validate/any" {}
    "pr/secure/file" { if ($count -ne 1) { exit 1 } }
    "x/validate/any" { if ($count -ne 1) { exit 1 } }
    "x/secure/any" { if ($count -ne 1) { exit 1 } }
    "worker/validate/directory" { if ($count -ne 1) { exit 1 } }
    "herdr/validate/directory" { if ($count -ne 1) { exit 1 } }
    default { exit 1 }
}

$current = [Security.Principal.WindowsIdentity]::GetCurrent().User
$allowed = @($current.Value, "S-1-5-18", "S-1-5-32-544")
$paths = @($env:FM_PRIVATE_PATH_1, $env:FM_PRIVATE_PATH_2, $env:FM_PRIVATE_PATH_3)
for ($index = 0; $index -lt $count; $index++) {
    $path = $paths[$index]
    if ($policy -eq "herdr" -and [string]::IsNullOrWhiteSpace($path)) { exit 1 }
    if ($kind -eq "directory") {
        $item = [IO.DirectoryInfo]::new($path)
        if (-not $item.Exists) { exit 1 }
    } elseif ($kind -eq "file") {
        $item = [IO.FileInfo]::new($path)
        if (-not $item.Exists) { exit 1 }
    } else {
        $item = Get-Item -LiteralPath $path -Force:($policy -eq "x")
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { exit 1 }
    $security = $item.GetAccessControl()
    if ($security.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $current.Value) { exit 1 }
    if ($action -eq "secure") {
        $security.SetAccessRuleProtection($true, $false)
        $rules = @($security.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))
        foreach ($rule in $rules) {
            [void]$security.RemoveAccessRuleSpecific($rule)
        }
        $inheritance = [Security.AccessControl.InheritanceFlags]::None
        if ($policy -eq "x" -and $item.PSIsContainer) {
            $inheritance = (
                [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                [Security.AccessControl.InheritanceFlags]::ObjectInherit
            )
        }
        foreach ($sid in $allowed) {
            $identity = [Security.Principal.SecurityIdentifier]::new($sid)
            $rule = [Security.AccessControl.FileSystemAccessRule]::new(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance,
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow
            )
            [void]$security.AddAccessRule($rule)
        }
        $item.SetAccessControl($security)
        $security = $item.GetAccessControl()
    }
    if ($security.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $current.Value) { exit 1 }
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new(
        $security.GetSecurityDescriptorBinaryForm(), 0
    )
    if ($null -eq $raw.DiscretionaryAcl) { exit 1 }
    $currentFullControl = $false
    foreach ($rule in $security.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
        if ($allowed -notcontains $rule.IdentityReference.Value) { exit 1 }
        if (
            $rule.IdentityReference.Value -eq $current.Value -and
            ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq
            [Security.AccessControl.FileSystemRights]::FullControl
        ) {
            $currentFullControl = $true
        }
    }
    if ($policy -eq "x" -and -not $currentFullControl) { exit 1 }
}
exit 0

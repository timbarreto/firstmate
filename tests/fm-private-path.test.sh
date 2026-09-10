#!/usr/bin/env bash
# Public compatibility contracts for the private-path policy variants.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-pr-lib.sh
. "$ROOT/bin/fm-pr-lib.sh"
# shellcheck source=bin/fm-x-lib.sh
. "$ROOT/bin/fm-x-lib.sh"
# shellcheck source=bin/backends/herdr.sh
. "$ROOT/bin/backends/herdr.sh"

private_expect() {
  local expected=$1 actual=0
  shift
  "$@" || actual=$?
  assert_equals "$expected" "$actual" "private-path verdict: $*"
}

private_native_fixture() {
  local native
  native=$(cygpath -w "$1") || fail "could not convert native fixture path"
  # shellcheck disable=SC2016 # PowerShell reads fixture parameters as environment data.
  FM_PRIVATE_FIXTURE_PATH=$native FM_PRIVATE_FIXTURE_ACTION=$2 \
    powershell.exe -NoProfile -NonInteractive -Command '
      $ErrorActionPreference = "Stop"
      $item = Get-Item -LiteralPath $env:FM_PRIVATE_FIXTURE_PATH -Force
      $current = [Security.Principal.WindowsIdentity]::GetCurrent().User
      $security = $item.GetAccessControl()
      $action = $env:FM_PRIVATE_FIXTURE_ACTION
      if ($action -eq "hidden") {
        $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
        exit 0
      }
      if ($action -eq "null") {
        $security.SetSecurityDescriptorSddlForm(
          "D:NO_ACCESS_CONTROL",
          [Security.AccessControl.AccessControlSections]::Access
        )
      } else {
        $security.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($security.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) {
          [void]$security.RemoveAccessRuleSpecific($rule)
        }
        $rights = [Security.AccessControl.FileSystemRights]::FullControl
        if ($action -eq "read") { $rights = [Security.AccessControl.FileSystemRights]::ReadAndExecute }
        foreach ($sid in @($current.Value, "S-1-5-18", "S-1-5-32-544")) {
          $identity = [Security.Principal.SecurityIdentifier]::new($sid)
          $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $identity, $rights, [Security.AccessControl.AccessControlType]::Allow
          )
          [void]$security.AddAccessRule($rule)
        }
        if ($action -eq "allow" -or $action -eq "deny") {
          $access = [Security.AccessControl.AccessControlType]::Deny
          if ($action -eq "allow") { $access = [Security.AccessControl.AccessControlType]::Allow }
          $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new("S-1-1-0"),
            [Security.AccessControl.FileSystemRights]::WriteData,
            $access
          )
          [void]$security.AddAccessRule($rule)
        }
      }
      $item.SetAccessControl($security)
      if ($action -eq "null") {
        $raw = [Security.AccessControl.RawSecurityDescriptor]::new(
          $item.GetAccessControl().GetSecurityDescriptorBinaryForm(), 0
        )
        if ($null -ne $raw.DiscretionaryAcl) { throw "fixture does not have a null DACL" }
      }
    ' >/dev/null || fail "could not construct native ACL fixture: $2"
}

test_private_native_policy_variants() {
  local tmp file dir action expected x_expected
  case "$(uname -s)" in
    MSYS*|MINGW*|CYGWIN*) ;;
    *) printf 'skip - native ACL policy fixtures require Windows\n'; return ;;
  esac
  tmp=$(fm_test_tmproot fm-private-policy)
  file="$tmp/file '[literal] & dollar\$"
  dir="$tmp/directory"
  : >"$file"
  mkdir "$dir"
  for action in private read allow deny null; do
    private_native_fixture "$file" "$action"
    private_native_fixture "$dir" "$action"
    expected=0
    x_expected=0
    case "$action" in
      read) x_expected=1 ;;
      allow|null) expected=1; x_expected=1 ;;
    esac
    private_expect "$expected" fm_pr_native_windows_private_paths_valid "$file" "$dir"
    private_expect "$x_expected" fmx_native_windows_private_path_acl "$file" validate
    private_expect "$x_expected" fmx_native_windows_private_path_acl "$dir" validate
    private_expect "$expected" fm_backend_herdr_presentation_lock_namespace_valid "$dir"
    private_expect "$expected" fm_private_path_native worker validate directory "$dir"
  done
  private_native_fixture "$file" private
  private_native_fixture "$dir" private
  private_native_fixture "$file" hidden
  private_expect 1 fm_pr_native_windows_private_paths_valid "$file"
  private_expect 0 fmx_native_windows_private_path_acl "$file" validate
  private_expect 0 fm_pr_private_file_secure "$file" 600
  private_expect 1 fm_pr_native_windows_private_paths_valid "$file"
  private_expect 1 fm_backend_herdr_presentation_lock_namespace_windows_acl_valid "$file"
  private_expect 1 fmx_native_windows_private_path_acl "$file" unknown
  private_expect 1 fm_pr_native_windows_private_paths_valid
  private_expect 1 fm_pr_native_windows_private_paths_valid "$dir" "$dir" "$dir" "$dir"
  pass "native callers retain ACL, FullControl, hidden-path, kind, and batch policies"
}

test_private_native_revalidation_and_inheritance() {
  local tmp file dir child native junction
  case "$(uname -s)" in
    MSYS*|MINGW*|CYGWIN*) ;;
    *) printf 'skip - native mutation fixtures require Windows\n'; return ;;
  esac
  tmp=$(fm_test_tmproot fm-private-mutation)
  file="$tmp/file"
  dir="$tmp/dir"
  child="$dir/child"
  junction="$tmp/junction"
  : >"$file"
  mkdir "$dir"
  private_native_fixture "$file" allow
  private_native_fixture "$dir" allow
  private_expect 0 fm_pr_private_file_secure "$file" 600
  private_expect 0 fmx_private_path_secure "$dir" 700
  : >"$child"
  private_expect 0 fmx_native_windows_private_path_acl "$child" validate
  private_expect 0 fm_pr_native_windows_private_paths_valid "$file" "$child" "$dir"
  printf '{"request_id":"private-path"}\n' \
    | fmx_private_artifact_publish_stdin "$tmp/outbox" private-path.json 600 \
    || fail "X publication through the extracted private-path dependency failed"
  private_expect 0 fmx_native_windows_private_path_acl "$tmp/outbox/private-path.json" validate
  private_native_fixture "$file" allow
  private_expect 1 fm_pr_native_windows_private_paths_valid "$file"
  private_expect 1 fmx_native_windows_private_path_acl "$file" validate
  mv "$file" "$tmp/former-file" || fail "could not replace fixture path"
  : >"$file"
  private_native_fixture "$file" allow
  private_expect 1 fm_pr_native_windows_private_paths_valid "$file"
  native=$(cygpath -w "$dir")
  # shellcheck disable=SC2016 # Paths are data, not interpolated source.
  FM_PRIVATE_FIXTURE_TARGET=$native FM_PRIVATE_FIXTURE_LINK=$(cygpath -w "$junction") \
    powershell.exe -NoProfile -NonInteractive -Command '
      $ErrorActionPreference = "Stop"
      [void](New-Item -ItemType Junction -Path $env:FM_PRIVATE_FIXTURE_LINK -Target $env:FM_PRIVATE_FIXTURE_TARGET)
    ' >/dev/null || fail "could not create reparse fixture"
  private_expect 1 fm_pr_native_windows_private_paths_valid "$junction"
  private_expect 1 fmx_native_windows_private_path_acl "$junction" validate
  private_expect 1 fm_backend_herdr_presentation_lock_namespace_windows_acl_valid "$junction"
  private_expect 1 fm_private_path_native worker validate directory "$junction"
  # Remove only the junction itself; never traverse the fixture target.
  # shellcheck disable=SC2016
  FM_PRIVATE_FIXTURE_LINK=$(cygpath -w "$junction") \
    powershell.exe -NoProfile -NonInteractive -Command \
      '[IO.Directory]::Delete($env:FM_PRIVATE_FIXTURE_LINK)' \
      || fail "could not remove reparse fixture"
  pass "native securing preserves inheritance and every validation rechecks mutation and reparse points"
}

test_private_structural_policies() {
  local tmp file device
  tmp=$(fm_test_tmproot fm-private-structure)
  file="$tmp/file"
  : >"$file"
  device=$(fm_pr_file_device "$file") || fail "could not inspect fixture device"
  private_expect 0 fm_pr_private_file_structure_valid "$file" "$device"
  private_expect 1 fm_pr_private_file_structure_valid "$tmp" "$device"
  private_expect 1 fm_pr_private_file_structure_valid "$file" different-device
  ln "$file" "$tmp/second-link" || fail "could not create hard-link fixture"
  private_expect 1 fm_pr_private_file_structure_valid "$file" "$device"
  private_expect 1 fmx_single_link_file_valid "$file"
  private_expect 1 fmx_private_path_secure "$tmp" 600
  private_expect 1 fmx_private_path_secure "$file" 644
  pass "public callers retain path-kind, device, hard-link, and supported-mode refusals"
}

# shellcheck disable=SC2329 # These tool doubles are called through imported compatibility functions.
test_private_transport_bounds() (
  local tmp file policy expected before after
  tmp=$(fm_test_tmproot fm-private-transport)
  file="$tmp/file"
  : >"$file"
  : >"$tmp/calls"
  uname() { printf 'MSYS_NT\n'; }
  _FM_X_UNAME=MSYS_NT
  cygpath() { printf '%s\n' "$2"; }
  powershell.exe() {
    printf '%s/%s/%s/%s\n' "$FM_PRIVATE_PATH_POLICY" "$FM_PRIVATE_PATH_ACTION" \
      "$FM_PRIVATE_PATH_KIND" "$FM_PRIVATE_PATH_COUNT" >>"$tmp/calls"
    printf '%s\0' "$FM_PRIVATE_PATH_1" "$FM_PRIVATE_PATH_2" "$FM_PRIVATE_PATH_3" >"$tmp/paths"
    printf '%s\n' "$@" >"$tmp/argv"
    return "$native_exit"
  }
  local native_exit=0 first=$'quotes \' "$[]; &\nlast line' second='two spaces  here'
  private_expect 0 fm_pr_native_windows_private_paths_valid "$first" "$second" "$file"
  assert_equals 1 "$(wc -l <"$tmp/calls" | tr -d ' ')" "PR batch uses one native invocation"
  printf '%s\0' "$first" "$second" "$file" >"$tmp/expected"
  cmp "$tmp/expected" "$tmp/paths" || fail "native path transport changed data bytes"
  assert_grep '-File' "$tmp/argv" "native implementation is loaded from the tracked file"
  assert_no_grep '-Command' "$tmp/argv" "paths must not become interpolated PowerShell commands"
  native_exit=1
  for policy in pr x worker herdr; do
    before=$(wc -l <"$tmp/calls")
    expected=3
    case "$policy" in
      pr) private_expect 1 fm_pr_native_windows_private_paths_valid "$file" "$file" "$file" ;;
      x) private_expect 1 fmx_native_windows_private_path_acl "$file" validate ;;
      worker) expected=1; private_expect 1 fm_private_path_native worker validate directory "$tmp" ;;
      herdr) expected=1; private_expect 1 fm_backend_herdr_presentation_lock_namespace_windows_acl_valid "$tmp" ;;
    esac
    after=$(wc -l <"$tmp/calls")
    assert_equals "$expected" "$((after - before))" "$policy native attempt bound"
  done
  before=$(wc -l <"$tmp/calls")
  private_expect 1 fm_pr_private_file_secure "$file" 600
  private_expect 1 fmx_native_windows_private_path_acl "$file" secure
  after=$(wc -l <"$tmp/calls")
  assert_equals 6 "$((after - before))" "both secure policies retain three attempts"
  pass "native batching, retry counts, and lossless environment transport remain bounded"
)

# shellcheck disable=SC2329 # These tool doubles are called through the imported native dispatcher.
test_private_missing_dependencies() (
  local tmp output missing
  tmp=$(fm_test_tmproot fm-private-dependencies)
  mkdir -p "$tmp/bin"
  cp "$ROOT/bin/fm-pr-lib.sh" "$tmp/bin/"
  if output=$(bash -c '. "$1/bin/fm-pr-lib.sh"' _ "$tmp" 2>&1); then
    fail "copied caller accepted a missing Bash dependency"
  fi
  assert_contains "$output" fm-private-path-lib.sh "missing Bash helper must be named"
  cp "$ROOT/bin/fm-private-path-lib.sh" "$tmp/bin/"
  if output=$(bash -c '
    . "$1/bin/fm-private-path-lib.sh"
    fm_private_path_native worker validate directory "$1"
  ' _ "$tmp" 2>&1); then
    fail "missing native helper was accepted"
  fi
  assert_contains "$output" 'required native helper missing' "missing native helper must be named"
  command() {
    if [ "$1" = -v ] && [ "$2" = "$missing" ]; then return 1; fi
    builtin command "$@"
  }
  cygpath() { printf '%s\n' "$2"; }
  powershell.exe() { : >"$tmp/unexpected-native-call"; return 0; }
  for missing in cygpath powershell.exe; do
    private_expect 1 fm_private_path_native worker validate directory "$tmp"
    assert_absent "$tmp/unexpected-native-call" "missing verification must not become success"
  done
  pass "missing Bash, PowerShell, conversion, or platform helpers refuse without a fallback"
)

test_private_posix_policy() (
  local tmp file device
  case "$(uname -s)" in
    MSYS*|MINGW*|CYGWIN*) printf 'skip - POSIX mode fixtures require a POSIX filesystem\n'; return ;;
  esac
  tmp=$(fm_test_tmproot fm-private-posix)
  file="$tmp/file"
  : >"$file"
  device=$(fm_pr_file_device "$file")
  chmod 600 "$file"
  chmod 700 "$tmp"
  private_expect 0 fm_pr_private_file_valid "$file" 600 "$device"
  private_expect 0 fmx_single_link_file_mode_valid "$file" 600 "$device"
  private_expect 0 fm_backend_herdr_presentation_lock_namespace_valid "$tmp"
  chmod 644 "$file"
  chmod 755 "$tmp"
  private_expect 1 fm_pr_private_file_valid "$file" 600 "$device"
  private_expect 1 fmx_single_link_file_mode_valid "$file" 600 "$device"
  private_expect 1 fm_backend_herdr_presentation_lock_namespace_valid "$tmp"
  chmod 700 "$tmp"
  # shellcheck disable=SC2329 # Called through the imported namespace validator.
  fm_backend_herdr_presentation_lock_namespace_uid() { printf '%s\n' "$(($(id -u) + 1))"; }
  private_expect 1 fm_backend_herdr_presentation_lock_namespace_valid "$tmp"
  pass "POSIX modes and the Herdr-specific ownership gate remain with the callers"
)

test_private_tracked_layouts() {
  local tmp seed layout file git_tmp
  tmp=$(fm_test_tmproot fm-private-layout)
  seed="$tmp/seed"
  fm_git_identity
  fm_git_init_commit "$seed" || fail "could not initialize layout fixture"
  # shellcheck source=tests/private-path-helpers.sh
  . "$ROOT/tests/private-path-helpers.sh"
  fm_test_install_private_paths "$seed" || fail "could not install layout dependencies"
  cp "$ROOT/bin/fm-pr-lib.sh" "$seed/bin/"
  cp "$ROOT/.gitattributes" "$seed/"
  git -C "$seed" add .gitattributes || fail "could not stage the tracked line-ending policy"
  git -C "$seed" add bin || fail "could not stage tracked dependency layout"
  git -C "$seed" commit -qm 'private-path fixture' || fail "could not commit tracked dependency layout"
  git -C "$seed" ls-files --error-unmatch bin/fm-pr-lib.sh >/dev/null \
    || fail "the layout fixture did not track its caller"
  git_tmp=$tmp
  case "$(uname -s)" in
    MSYS*|MINGW*|CYGWIN*)
      # Give native Git an explicit destination for wildcard-like path components.
      git_tmp=$(cygpath -m "$tmp") || fail "could not convert the Git fixture root"
      ;;
  esac
  git clone -q "$seed" "$git_tmp/clone [literal] & space" || fail "could not clone layout fixture"
  git -C "$seed" worktree add -q --detach "$git_tmp/worktree [literal] & space" \
    || fail "could not create worktree layout fixture"
  file="$tmp/"$'artifact \303\251 \'[$] &'
  : >"$file"
  for layout in "$tmp/clone [literal] & space" "$tmp/worktree [literal] & space"; do
    assert_present "$layout/bin/fm-pr-lib.sh" "the cloned/worktree caller is missing"
    bash -c '
      . "$1/bin/fm-pr-lib.sh" || exit 1
      fm_pr_private_file_secure "$2" 600 || exit 1
      device=$(fm_pr_file_device "$2") || exit 1
      fm_pr_private_file_valid "$2" 600 "$device"
    ' _ "$layout" "$file" || fail "tracked clone/worktree dependency or path transport failed"
  done
  pass "tracked clones and worktree-shaped roots carry the native dependency without ambient fallback"
}

fm_test_run_cases \
  test_private_native_policy_variants \
  test_private_native_revalidation_and_inheritance \
  test_private_structural_policies \
  test_private_transport_bounds \
  test_private_missing_dependencies \
  test_private_posix_policy \
  test_private_tracked_layouts

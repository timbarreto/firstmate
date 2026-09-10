#!/usr/bin/env bash
# Native private-path mechanics; callers retain platform, POSIX, and transaction policy.
# fm_private_path_native <policy> <validate|secure> <kind> <path...>
# Accepted combinations: pr/validate/any (1-3 paths), pr/secure/file (1),
# x/{validate,secure}/any (1), {worker,herdr}/validate/directory (1).
# PR and X retry at most three times; worker and Herdr make one native call.
# The platform owner defines the ACL differences. No validation result is cached.

_FM_PRIVATE_PATH_SCRIPT="${BASH_SOURCE[0]%fm-private-path-lib.sh}platform/windows-private-path.ps1"
case "$_FM_PRIVATE_PATH_SCRIPT" in
  /*) ;;
  *) _FM_PRIVATE_PATH_SCRIPT="$PWD/$_FM_PRIVATE_PATH_SCRIPT" ;;
esac
# Only the immutable code location is converted once, never a path verdict.
_FM_PRIVATE_PATH_SCRIPT_NATIVE=

fm_private_path_native() {
  local policy=${1:-} action=${2:-} kind=${3:-} attempts
  [ "$#" -ge 3 ] || {
    printf 'fm-private-path: expected policy, operation, kind, and paths\n' >&2
    return 1
  }
  shift 3
  case "$policy/$action/$kind/$#" in
    pr/validate/any/[123]|pr/secure/file/1|x/validate/any/1|x/secure/any/1) attempts=3 ;;
    worker/validate/directory/1|herdr/validate/directory/1) attempts=1 ;;
    *)
      printf 'fm-private-path: unsupported policy/operation/kind/count: %s/%s/%s/%s\n' \
        "$policy" "$action" "$kind" "$#" >&2
      return 1
      ;;
  esac
  [ -r "$_FM_PRIVATE_PATH_SCRIPT" ] || {
    printf 'fm-private-path: required native helper missing: %s\n' "$_FM_PRIVATE_PATH_SCRIPT" >&2
    return 1
  }
  command -v cygpath >/dev/null 2>&1 || return 1
  command -v powershell.exe >/dev/null 2>&1 || return 1
  if [ -z "$_FM_PRIVATE_PATH_SCRIPT_NATIVE" ]; then
    _FM_PRIVATE_PATH_SCRIPT_NATIVE=$(cygpath -w "$_FM_PRIVATE_PATH_SCRIPT" 2>/dev/null) || return 1
    [ -n "$_FM_PRIVATE_PATH_SCRIPT_NATIVE" ] || return 1
  fi
  local native_1='' native_2='' native_3='' index=0 path native attempt=0
  for path in "$@"; do
    native=$(cygpath -w "$path" 2>/dev/null) || return 1
    index=$((index + 1))
    case "$index" in
      1) native_1=$native ;;
      2) native_2=$native ;;
      3) native_3=$native ;;
    esac
  done
  [ -n "$native_1" ] || return 1
  while [ "$attempt" -lt "$attempts" ]; do
    attempt=$((attempt + 1))
    if FM_PRIVATE_PATH_POLICY=$policy FM_PRIVATE_PATH_ACTION=$action \
      FM_PRIVATE_PATH_KIND=$kind FM_PRIVATE_PATH_COUNT=$# \
      FM_PRIVATE_PATH_1=$native_1 FM_PRIVATE_PATH_2=$native_2 FM_PRIVATE_PATH_3=$native_3 \
      powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "$_FM_PRIVATE_PATH_SCRIPT_NATIVE" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

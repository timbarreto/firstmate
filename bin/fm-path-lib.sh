#!/usr/bin/env bash
# Shared path spelling for Bash consumers; source without changing caller state.
#
# fm_path_absolute <path> [destination-variable]
#   Return an absolute Bash path without resolving symlinks or granting access.
#   On MSYS/Cygwin, fully qualified drive and UNC roots use existing cygpath
#   mapping; the remaining components retain literal dots, separators, and
#   bytes. Drive-relative and current-drive-rooted Windows forms refuse
#   rather than guessing a drive. POSIX absolute paths retain their spelling;
#   relative paths are anchored to the caller's PWD. On POSIX, Windows-looking
#   relative filenames remain literal filenames, not foreign path syntax.
#   Destination form prints nothing; stdout form prints no added newline.
#   Empty paths, invalid destinations, and unavailable required conversion
#   return 1. Caller directories, arguments, IFS, options, and environment stay.
#   The _fm_path_* local-variable prefix is reserved for this implementation.
#
# fm_path_native_argument <path> [destination-variable]
#   Prepare one explicitly path-typed argument for a native Windows program
#   using cygpath -m; on POSIX retain it unchanged. Never convert arbitrary
#   arguments or command text, nor rely on MSYS wildcard-dependent guessing.
#
# fm_path_normalize_context
#   Explicit entrypoint initialization for nonempty FM_ROOT, FM_HOME,
#   FM_ROOT_OVERRIDE, FM_STATE_OVERRIDE, FM_DATA_OVERRIDE, FM_PROJECTS_OVERRIDE,
#   and FM_CONFIG_OVERRIDE. Stage conversions before applying any; unset/empty
#   overrides retain their fallback meaning and export attributes are retained.
#   This never creates directories or modifies the calling process's parent.
#
# Path spelling is not filesystem identity or authorization. Existing callers
# retain existence, traversal, symlink/reparse, ACL, ownership, and publication
# checks; fm_platform_same_directory owns existing-directory identity.

fm_path_absolute() {  # <path> [destination-variable]
  local _fm_path_input=${1-} _fm_path_result _fm_path_destination=${2-}
  local _fm_path_root _fm_path_tail _fm_path_server _fm_path_share _fm_path_separator=/
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] && [ -n "$_fm_path_input" ] || {
    printf 'fm-path: expected a nonempty path and optional destination\n' >&2
    return 1
  }
  if [ "$#" -eq 2 ]; then
    case "$_fm_path_destination" in
      ''|[!a-zA-Z_]*|*[!a-zA-Z0-9_]*|_fm_path_*)
        printf 'fm-path: invalid destination variable\n' >&2
        return 1
        ;;
    esac
  fi
  _fm_path_result=$_fm_path_input
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      case "$_fm_path_input" in
        [a-zA-Z]:[\\/]*|\\\\*)
          _fm_path_result=${_fm_path_input//\\//}
          case "$_fm_path_result" in
            [a-zA-Z]:/*)
              _fm_path_root="${_fm_path_result:0:2}/"
              _fm_path_tail=${_fm_path_result:3}
              ;;
            //*)
              _fm_path_tail=${_fm_path_result#//}
              _fm_path_server=${_fm_path_tail%%/*}
              _fm_path_tail=${_fm_path_tail#*/}
              _fm_path_share=${_fm_path_tail%%/*}
              case "$_fm_path_server/$_fm_path_share" in
                ./*|../*|'?'/*|*/.|*/..) return 1 ;;
              esac
              [ -n "$_fm_path_server" ] && [ -n "$_fm_path_share" ] \
                && [ "$_fm_path_server" != "${_fm_path_result#//}" ] || return 1
              _fm_path_root="//$_fm_path_server/$_fm_path_share/"
              if [ "$_fm_path_tail" = "$_fm_path_share" ]; then
                _fm_path_tail='' _fm_path_separator=''
              else _fm_path_tail=${_fm_path_tail#*/}; fi
              ;;
          esac
          command -v cygpath >/dev/null 2>&1 || {
            printf 'fm-path: cygpath is required for a native Windows path\n' >&2
            return 1
          }
          _fm_path_result=$(cygpath -u "$_fm_path_root" 2>/dev/null) || {
            printf 'fm-path: Windows path conversion failed\n' >&2
            return 1
          }
          case "$_fm_path_result" in
            /*) ;;
            *) printf 'fm-path: Windows path did not resolve to an absolute Bash path\n' >&2; return 1 ;;
          esac
          _fm_path_result="${_fm_path_result%/}$_fm_path_separator$_fm_path_tail"
          ;;
        [a-zA-Z]:*|\\*)
          printf 'fm-path: Windows path must include an absolute drive or UNC share\n' >&2
          return 1
          ;;
      esac
      ;;
  esac
  case "$_fm_path_result" in
    /*) ;;
    *) _fm_path_result="${PWD%/}/$_fm_path_result" ;;
  esac
  if [ "$#" -eq 2 ]; then
    printf -v "$_fm_path_destination" '%s' "$_fm_path_result"
  else
    printf '%s' "$_fm_path_result"
  fi
}

fm_path_native_argument() {  # <path> [destination-variable]
  local _fm_native_value=${1-} _fm_native_output
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] && [ -n "$_fm_native_value" ] || return 1
  if [ "$#" -eq 2 ]; then
    case "$2" in ''|[!a-zA-Z_]*|*[!a-zA-Z0-9_]*|_fm_native_*) return 1 ;; esac
  fi
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      command -v cygpath >/dev/null 2>&1 || return 1
      _fm_native_output=$(cygpath -m -- "$_fm_native_value" && printf '.') || return 1
      _fm_native_output=${_fm_native_output%.}
      _fm_native_value=${_fm_native_output%$'\n'}
      [ -n "$_fm_native_value" ] || return 1
      ;;
  esac
  if [ "$#" -eq 2 ]; then printf -v "$2" '%s' "$_fm_native_value";
  else printf '%s' "$_fm_native_value"; fi
}

fm_path_normalize_context() {
  local _fm_context_name _fm_context_value _fm_context_index=0
  local -a _fm_context_names _fm_context_values
  _fm_context_names=()
  _fm_context_values=()
  for _fm_context_name in FM_ROOT FM_HOME FM_ROOT_OVERRIDE FM_STATE_OVERRIDE \
    FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE FM_CONFIG_OVERRIDE; do
    [ -n "${!_fm_context_name:-}" ] || continue
    if ! fm_path_absolute "${!_fm_context_name}" _fm_context_value; then
      printf 'fm-path: invalid %s\n' "$_fm_context_name" >&2
      return 1
    fi
    _fm_context_names+=("$_fm_context_name")
    _fm_context_values+=("$_fm_context_value")
  done
  while [ "$_fm_context_index" -lt "${#_fm_context_names[@]}" ]; do
    printf -v "${_fm_context_names[$_fm_context_index]}" '%s' "${_fm_context_values[$_fm_context_index]}" || return 1
    _fm_context_index=$((_fm_context_index + 1))
  done
}

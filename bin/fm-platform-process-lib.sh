#!/usr/bin/env bash
# Generic process facts and native command transport; source without side effects.
#
# fm_platform_process_comm|args|ppid <pid>
#   Read FM_PROC_ROOT_OVERRIDE (default /proc), then the existing POSIX ps field.
# fm_platform_windows_pid_matches <native-pid> <executable-name>
#   Prefer one tasklist PID query; use ps -W only when it has no result.
#   This module never caches facts or makes a harness/ownership decision.
# fm_platform_powershell_quote <value>
# fm_platform_windows_location_command <native-path>
# fm_platform_windows_environment_command <name> <value>
# fm_platform_windows_bash_native_path
# fm_platform_windows_bash_script_command <posix-script> [<native-bash-path>]
#   Render literal PowerShell commands, without executing them. Native Bash lookup
#   uses the calling Git Bash's PATH and cygpath, not an extra PowerShell process.
# Missing native tools and invalid environment names return nonzero.

fm_platform_shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

fm_platform_json_escape() {
  local value=$1 code character escaped
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  # Bash cannot carry NUL; encode the remaining JSON control characters.
  for ((code=1; code<32; code++)); do
    printf -v escaped '\\%03o' "$code"
    printf -v character '%b' "$escaped"
    printf -v escaped '\\u%04x' "$code"
    value=${value//"$character"/"$escaped"}
  done
  printf '%s' "$value"
}

fm_platform_resolve_executable() {
  local candidate dir
  candidate=$(type -P -- "$1" 2>/dev/null) || return 1
  [ -x "$candidate" ] || return 1
  case "$candidate" in
    /*) printf '%s\n' "$candidate" ;;
    *)
      dir=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
      printf '%s/%s\n' "$dir" "$(basename "$candidate")"
      ;;
  esac
}

fm_platform_command_supports_option() {
  local executable=$1 option=$2 help
  help=$("$executable" --help 2>&1) || return 1
  printf '%s\n' "$help" | grep -Eq -- "(^|[[:space:]])$option([[:space:]=]|$)"
}

fm_platform_process_comm() {
  local pid=$1 proc_root=${FM_PROC_ROOT_OVERRIDE:-/proc}
  if [ -r "$proc_root/$pid/status" ]; then
    sed -n 's/^Name:[[:space:]]*//p' "$proc_root/$pid/status" | head -1
    return
  fi
  ps -o comm= -p "$pid" 2>/dev/null
}

fm_platform_process_args() {
  local pid=$1 proc_root=${FM_PROC_ROOT_OVERRIDE:-/proc}
  if [ -r "$proc_root/$pid/cmdline" ]; then
    tr '\0' ' ' < "$proc_root/$pid/cmdline"
    return
  fi
  ps -o args= -p "$pid" 2>/dev/null
}

fm_platform_process_ppid() {
  local pid=$1 proc_root=${FM_PROC_ROOT_OVERRIDE:-/proc}
  if [ -r "$proc_root/$pid/status" ]; then
    sed -n 's/^PPid:[[:space:]]*//p' "$proc_root/$pid/status" | head -1
    return
  fi
  ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' '
}

fm_platform_windows_pid_matches() {
  local pid=$1 name=$2 image
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  if command -v tasklist.exe >/dev/null 2>&1; then
    image=$(MSYS_NO_PATHCONV=1 tasklist.exe /FI "PID eq $pid" /FO CSV /NH 2>/dev/null \
      | tr -d '\r' \
      | awk -F, '{ gsub(/"/, ""); print $1; exit }')
    case "$image" in
      "$name") return 0 ;;
      ''|INFO:*) ;;
      *) return 1 ;;
    esac
  fi
  image=$(LC_ALL=C ps -W 2>/dev/null | awk -v p="$pid" '
    NR > 1 && $4 == p { print $NF; exit }
  ') || return 1
  case "$image" in
    "$name"|*\\"$name"|*/"$name") return 0 ;;
  esac
  return 1
}

fm_platform_powershell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/''/g"
  printf "'"
}

fm_platform_windows_location_command() {
  printf 'Set-Location -LiteralPath %s\n' "$(fm_platform_powershell_quote "$1")"
}

fm_platform_windows_environment_command() {
  case "$1" in
    ''|*[!A-Za-z0-9_]*) return 1 ;;
  esac
  printf '%s:%s = %s\n' "\$env" "$1" "$(fm_platform_powershell_quote "$2")"
}

fm_platform_windows_bash_native_path() {
  local path
  command -v cygpath >/dev/null 2>&1 || return 1
  path=$(command -v bash 2>/dev/null) || return 1
  cygpath -w "$path"
}

fm_platform_windows_bash_script_command() {
  local script=$1 bash_path=${2:-}
  [ -n "$bash_path" ] \
    || bash_path=$(fm_platform_windows_bash_native_path) \
    || return 1
  printf '& %s --login %s\n' \
    "$(fm_platform_powershell_quote "$bash_path")" \
    "$(fm_platform_powershell_quote "$script")"
}

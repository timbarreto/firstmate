#!/usr/bin/env bash
# Closed Copilot/Pi interface. Nonpilots stay on their existing caller paths.
#
# fm_harness_registered <name> is the exact-name routing predicate.
# fm_harness_describe <name> <capability> [context]
# fm_harness_identify <name> <evidence-stage> [evidence]
# fm_harness_prepare_launch <name> <kind> <template-or-raw-command>
# fm_harness_owned_wiring <name> <selector> [context]
#
# Wiring selectors shared by both adapters:
#   paths <worktree-or-empty> <state> <id>
#   render <code-root> <state> <id> <generation> <turnend-path>
# Copilot additionally describes hook-path <worktree> <id>, exclusion,
# submission-marker <state> <id>, parent-environment <state> <id> <generation>,
# and inherited-environment. Pi describes primary-turnend <home> and
# primary-watch <home>. Parent and launch environments are shell-quoted text;
# lifecycle callers bind them, never evaluate adapter-supplied configuration.
#
# Describe returns immutable control/profile/launch facts; identify returns the
# existing identity or 1 for no match. Prepare resolves the executable and
# capability-gated template before allocation, setting FM_HARNESS_LAUNCH,
# FM_HARNESS_EXECUTABLE and FM_HARNESS_EXECUTABLE_TOKEN. Callers retain their
# existing order of generic model/effort and operational-path substitution.
# Wiring prints content or exact owned paths, never publishes or deletes them.
# Invalid interface calls and missing/broken adapters diagnose and return 2.
# Adapters never source lifecycle owners or discover plugins from filenames.

FM_HARNESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-platform-process-lib.sh
. "$FM_HARNESS_LIB_DIR/fm-platform-process-lib.sh" || return 2

# Legacy process-name evidence, not the pilot registry. Order is significant
# when a path contains components naming more than one harness.
# shellcheck disable=SC2034 # Compatibility filter consumed by session identity callers.
FM_HARNESS_RE='claude|codex|opencode|grok|kimi|^copilot(\.exe)?$|^pi$|^pi-signed$|^omp$'
FM_HARNESS_NAMES=(claude codex opencode grok kimi copilot copilot.exe pi-signed pi omp)

fm_harness_path_name() {  # <path>
  local path=$1 name
  [ -n "$path" ] || return 1
  for name in "${FM_HARNESS_NAMES[@]}"; do
    case "/$path/" in
      */"$name"/*) printf '%s' "$name"; return 0 ;;
    esac
  done
  return 1
}

fm_harness_registered() {
  case "${1:-}" in copilot|pi) return 0 ;; esac
  return 1
}

_fm_harness_error() {
  printf 'error: harness adapter %s\n' "$*" >&2
  return 2
}

_fm_harness_argument_count() {  # <operation> <expected> <actual>
  [ "$3" -eq "$2" ] || _fm_harness_error "$1 requires $2 arguments; received $3"
}

_fm_harness_require() {
  local harness=$1 path operation loaded=1 loaded_path=
  fm_harness_registered "$harness" || { _fm_harness_error "is not registered: $harness"; return 2; }
  path="$FM_HARNESS_LIB_DIR/harnesses/$harness.sh"
  [ -r "$path" ] || { _fm_harness_error "is missing or unreadable: $path"; return 2; }
  case "$harness" in
    copilot) loaded_path=${_FM_HARNESS_COPILOT_PATH:-} ;;
    pi) loaded_path=${_FM_HARNESS_PI_PATH:-} ;;
  esac
  [ "$loaded_path" = "$path" ] || loaded=0
  for operation in describe identify prepare_launch owned_wiring; do
    declare -F "fm_harness_${harness}_$operation" >/dev/null || loaded=0
  done
  [ "$loaded" -eq 0 ] || return 0
  for operation in describe identify prepare_launch owned_wiring; do
    unset -f "fm_harness_${harness}_$operation"
  done
  case "$harness" in
    copilot)
      # shellcheck source=/dev/null
      . "$path" || { _fm_harness_error "could not load: $path"; return 2; }
      ;;
    pi)
      # shellcheck source=/dev/null
      . "$path" || { _fm_harness_error "could not load: $path"; return 2; }
      ;;
  esac
  for operation in describe identify prepare_launch owned_wiring; do
    declare -F "fm_harness_${harness}_$operation" >/dev/null \
      || { _fm_harness_error "$harness is missing $operation"; return 2; }
  done
  case "$harness" in
    copilot) _FM_HARNESS_COPILOT_PATH=$path ;;
    pi) _FM_HARNESS_PI_PATH=$path ;;
  esac
}

_fm_harness_call() {
  [ "$#" -ge 2 ] || { _fm_harness_error "requires an adapter name"; return 2; }
  local operation=$1 harness=${2:-}
  shift 2
  case "$operation" in
    prepare_launch)
      _fm_harness_argument_count prepare-launch 2 "$#" || return 2
      [ -n "$1" ] && [ -n "$2" ] || { _fm_harness_error "prepare-launch requires a kind and command"; return 2; }
      ;;
    *) [ "$#" -ge 1 ] || { _fm_harness_error "$operation requires a selector"; return 2; } ;;
  esac
  _fm_harness_require "$harness" || return 2
  "fm_harness_${harness}_$operation" "$@"
}

fm_harness_describe() { _fm_harness_call describe "$@"; }
fm_harness_identify() { _fm_harness_call identify "$@"; }
# shellcheck disable=SC2034 # Prepared fields are the caller-visible output contract.
fm_harness_prepare_launch() {
  local status
  FM_HARNESS_LAUNCH='' FM_HARNESS_EXECUTABLE='' FM_HARNESS_EXECUTABLE_TOKEN=''
  if _fm_harness_call prepare_launch "$@"; then return 0; else status=$?; fi
  FM_HARNESS_LAUNCH='' FM_HARNESS_EXECUTABLE='' FM_HARNESS_EXECUTABLE_TOKEN=''
  return "$status"
}
fm_harness_owned_wiring() { _fm_harness_call owned_wiring "$@"; }

_fm_harness_require copilot || return 2
_fm_harness_require pi || return 2

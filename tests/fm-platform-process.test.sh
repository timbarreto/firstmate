#!/usr/bin/env bash
# Process compatibility contracts through the existing Pi/OpenCode and Bash interfaces.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-platform-process)

test_process_compatibility_contracts() {
  node "$ROOT/tests/fm-platform-process.test.mjs" || fail "process compatibility contracts"
  pass "Pi and OpenCode preserve process exports, PID semantics, ownership, and call counts"
}

test_process_facts_preserve_proc_and_ps() {
  local proc="$TMP_ROOT/proc" output
  mkdir -p "$proc/731"
  printf 'Name:\tfixture-name\nPPid:\t730\n' > "$proc/731/status"
  printf 'fixture\0two words\0' > "$proc/731/cmdline"
  output=$(FM_PROC_ROOT_OVERRIDE="$proc" bash -c '
    . "$1" || exit 1
    ps() { echo "unexpected ps" >&2; return 9; }
    fm_session_process_comm 731
    fm_session_process_args 731
    printf "\n"
    fm_session_process_ppid 731
  ' _ "$ROOT/bin/fm-session-lock-lib.sh") || fail "proc facts queried ps"
  [ "$output" = "$(printf 'fixture-name\nfixture two words \n730')" ] \
    || fail "proc process facts changed: $output"
  output=$(FM_PROC_ROOT_OVERRIDE="$proc/absent" bash -c '
    . "$1" || exit 1
    ps() {
      case "$*" in
        "-o comm= -p 731") printf "fallback-name\n" ;;
        "-o args= -p 731") printf "fallback two words\n" ;;
        "-o ppid= -p 731") printf " 730 \n" ;;
        *) return 9 ;;
      esac
    }
    fm_session_process_comm 731
    fm_session_process_args 731
    fm_session_process_ppid 731
  ' _ "$ROOT/bin/fm-session-lock-lib.sh") || fail "ps fallback failed"
  [ "$output" = "$(printf 'fallback-name\nfallback two words\n730')" ] \
    || fail "ps fallback facts changed: $output"
  pass "process facts preserve proc overrides and POSIX fallback formatting"
}

test_transport_preserves_literal_data() {
  local value command
  value=$(printf "C:\\\\Crew O'Brien [x]; \044env:PATH\nsecond line")
  command=$(bash -c '
    . "$1" || exit 1
    fm_backend_herdr_windows_set_environment_command FM_TRANSPORT "$2"
  ' _ "$ROOT/bin/backends/herdr.sh" "$value") || fail "transport rendering failed"
  [ "$command" = "$(printf "\044env:FM_TRANSPORT = 'C:\\\\Crew O''Brien [x]; \044env:PATH\nsecond line'")" ] \
    || fail "transport changed literal metacharacters or newlines: $command"
  pass "Windows transport preserves quotes, metacharacters, and multiline data"
}

fm_test_run_cases \
  test_process_compatibility_contracts \
  test_process_facts_preserve_proc_and_ps \
  test_transport_preserves_literal_data

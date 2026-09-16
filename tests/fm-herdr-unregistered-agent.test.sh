#!/usr/bin/env bash
# Missing runtime registration is not proof of an exited process. Exercise the
# public recovery-grade state, including Windows native descendants, without
# querying or mutating a live Herdr session.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/backends/herdr.sh
. "$ROOT/bin/backends/herdr.sh"
FOREGROUND=copilot.exe
NATIVE_ROWS=$'101\t1000000\tpowershell.exe\tpowershell.exe\n102\t1000001\tcopilot.exe\tcopilot.exe'
NATIVE_RC=0
fm_backend_herdr_cli() {
  case "$2 $3" in
    'pane get') printf '%s\n' '{"result":{"type":"pane_info","pane":{"pane_id":"w1:p1"}}}' ;;
    'agent get') printf '%s\n' '{"error":{"code":"agent_not_found"}}'; return 1 ;;
    'pane process-info')
      jq -cn --arg name "$FOREGROUND" '{result:{type:"pane_process_info",process_info:{pane_id:"w1:p1",shell_pid:101,foreground_processes:[{pid:101,name:$name,argv0:$name,cmdline:$name}]}}}' ;;
    'status --json') printf '%s\n' '{"server":{"running":true}}' ;;
    *) return 1 ;;
  esac
}
# These are the platform's fact interfaces, not alternative lifecycle policy.
fm_platform_windows_host() { return 0; }
fm_platform_windows_process_supported() { return 0; }
fm_platform_windows_descendant_processes() {
  [ "$1" = 101 ] || return 2
  [ "$NATIVE_RC" = 0 ] || return "$NATIVE_RC"
  printf '%s\n' "$NATIVE_ROWS"
}
assert_equals alive "$(fm_backend_herdr_agent_state fixture:w1:p1)" \
  "an unregistered foreground Copilot process is still alive"
pass "absent Herdr registration does not demote a live foreground agent"

FOREGROUND=powershell.exe
assert_equals alive "$(fm_backend_herdr_agent_state fixture:w1:p1)" \
  "a native Copilot descendant below PowerShell is still alive"
pass "native descendants protect an unregistered Windows Copilot worker"

NATIVE_ROWS=$'101\t1000000\tpowershell.exe\tpowershell.exe\n102\t1000001\tbash.exe\tbash.exe'
assert_equals dead "$(fm_backend_herdr_agent_state fixture:w1:p1)" \
  "a fresh native shell-only tree can prove the agent stopped"
NATIVE_RC=2
assert_equals unreadable "$(fm_backend_herdr_agent_state fixture:w1:p1)" \
  "failed native observation cannot prove absence"
NATIVE_RC=0
NATIVE_ROWS=$'101\t1000000\tpowershell.exe\tpowershell.exe\n102\t1000001\tnode.exe\tnode.exe unknown-program.js'
FM_BACKEND_HERDR_IDLE_SHELL_PROOF_POLLS=1
assert_equals unreadable "$(fm_backend_herdr_agent_state fixture:w1:p1)" \
  "an unregistered unknown native process is not a stopped worker"
pass "native absence requires readable shell-only facts, not a missing registration"

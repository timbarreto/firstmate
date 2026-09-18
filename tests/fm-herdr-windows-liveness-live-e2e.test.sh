#!/usr/bin/env bash
# Token-free native Windows guard for installed harnesses launched through the
# same env/exec and PowerShell/Git Bash boundary as Herdr workers. No prompts,
# live fleet operations, or credentials are required; even an auth/trust screen
# must never become proof of death. Recognized native harnesses must be alive;
# an unregistered interpreter-hosted harness may remain conservatively unreadable.
# All lifecycle operations use a named lab.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_live_gate default-on FM_HERDR_WINDOWS_LIVENESS herdr jq powershell.exe
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) echo 'skip: native Windows Git Bash required'; exit 0 ;;
esac
# shellcheck source=tests/herdr-test-safety.sh
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
# shellcheck source=bin/backends/herdr.sh
. "$ROOT/bin/backends/herdr.sh"

SCRATCH=$(fm_test_tmproot fm-herdr-win-liveness)
HELPER="$ROOT/bin/fm-herdr-lab.sh"
SESSION=''
cleanup() {
  local rc=$?
  trap - EXIT
  if [ -n "$SESSION" ]; then
    "$HELPER" teardown "$SESSION" || rc=1
  fi
  fm_test_cleanup
  exit "$rc"
}
trap cleanup EXIT
SESSION=$("$HELPER" name win-liveness)
"$HELPER" provision "$SESSION"
CHECKED=0
for harness in claude codex copilot opencode pi pi-signed grok kimi cursor gemini muse rovo omp agy; do
  binary=''
  if [ "$harness" = cursor ]; then
    binary=$(fm_cursor_resolve_binary 2>/dev/null) || binary=''
  elif [ "$harness" = kimi ] && ! command -v kimi >/dev/null 2>&1; then
    [ ! -x "$HOME/.kimi-code/bin/kimi" ] || binary="$HOME/.kimi-code/bin/kimi"
  else
    binary=$(type -P "$harness") || binary=''
  fi
  if [ -z "$binary" ] || [ ! -x "$binary" ]; then
    printf '# skip: %s is not installed; its Windows liveness is unverified\n' "$harness"
    continue
  fi
  version=$("$binary" --version 2>/dev/null | head -1 | tr -d '\r') || version=unknown
  printf '# checking %s (%s)\n' "$harness" "$version"
  mkdir -p "$SCRATCH/$harness"
  launch="$SCRATCH/$harness/launch.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'unset FM_HOME FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_TASK_ID\n'
    printf 'env -u CLAUDECODE -u PI_CODING_AGENT -u FM_PI_HARNESS -u GROK_AGENT env -u COPILOT_CLI -u COPILOT_AGENT_SESSION_ID -u COPILOT_LOADER_PID '
    fm_platform_shell_quote "$binary"
    [ "$harness" != cursor ] || printf ' --trust'
    printf '\nexit "$?"\n'
  } > "$launch"
  workspace=$("$HELPER" run "$SESSION" workspace create --cwd "$SCRATCH/$harness" --label "liveness-$harness" --no-focus)
  pane=$(printf '%s' "$workspace" | jq -er '.result.root_pane.pane_id')
  command=$(fm_backend_herdr_windows_bash_script_command "$launch")
  "$HELPER" run "$SESSION" pane run "$pane" "$command" >/dev/null
  state=''
  # Unknown foreground programs normally receive extra settle samples. This
  # guard tests the settled ownership boundary, not that retry cadence.
  for _ in $(seq 1 8); do
    process_state=$(FM_BACKEND_HERDR_IDLE_SHELL_PROOF_POLLS=1 fm_backend_herdr_pane_process_state "$SESSION" "$pane")
    [ "$process_state" != agent ] || break
    sleep 0.1
  done
  case "$process_state" in
    agent|other) ;;
    *) fail "$harness ($version): no live non-shell process attributed to its pane ($process_state)" ;;
  esac
  state=$(FM_BACKEND_HERDR_IDLE_SHELL_PROOF_POLLS=1 fm_backend_herdr_agent_state "$SESSION:$pane")
  case "$state" in
    alive) pass "$harness ($version): Windows Herdr exec launch remains alive" ;;
    unreadable)
      case "$harness" in
        claude|copilot) fail "$harness ($version): recognized native worker became unreadable" ;;
      esac
      pass "$harness ($version): live descendant preserved; unregistered identity remains safely unreadable (not certified alive)"
      ;;
    *) fail "$harness ($version): live exec worker misclassified '$state'" ;;
  esac
  CHECKED=$((CHECKED + 1))
  "$HELPER" run "$SESSION" pane close "$pane" >/dev/null
done
[ "$CHECKED" -gt 0 ] || fail 'no installed harness was checked'
printf 'checked=%s herdr=%s\n' "$CHECKED" "$(herdr --version)"

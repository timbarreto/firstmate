#!/usr/bin/env bash
# Opt-in live Claude session identity across SessionStart, Bash, and both Stop
# registrations. Uses the working-tree .claude/settings.json in a throwaway
# project, replacing operational hook bodies with real lock/ownership probes.
# No bootstrap, network sweeps, watcher, or real fleet home is touched. The real
# Claude executable is launched by native Node, so Windows crosses the same
# native -> Git Bash edge as a Claude session started from PowerShell.
# Costs one short model turn through the installed Claude's existing auth:
#   FM_CLAUDE_SESSION_LOCK_LIVE_E2E=1 bin/fm-test-run.sh tests/fm-claude-session-lock-live-e2e.test.sh
# shellcheck disable=SC2016 # Probe variables expand in the fixture hook shell.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate opt-in FM_CLAUDE_SESSION_LOCK_LIVE_E2E claude node jq

TMP_ROOT=$(fm_test_tmproot fm-claude-session-lock-live)
LAB="$TMP_ROOT/project"
mkdir -p "$LAB/.claude" "$LAB/bin" "$LAB/state"
git init -q "$LAB" || fail "could not create isolated Claude project"
cp "$ROOT/.claude/settings.json" "$LAB/.claude/settings.json" || fail "active Claude registration is missing"
printf '# Isolated hook identity test\n' > "$LAB/CLAUDE.md"
CLAUDE_VERSION=$(claude --version) || fail "could not read installed Claude version"

cat > "$LAB/probe.sh" <<'SH'
#!/usr/bin/env bash
set -u
name=$(basename "$0")
if [ "$name" = fm-sessionstart-run.sh ]; then
  if ! "$FM_TEST_CODE_ROOT/bin/fm-lock.sh" > "$FM_HOME/state/acquire.out" 2>&1; then
    printf '%s acquisition failed: %s\n' "$name" "$(<"$FM_HOME/state/acquire.out")" >> "$FM_HOME/state/failures"
    # The test asserts the failure file; do not cause repeated model turns.
    exit 0
  fi
fi
. "$FM_TEST_CODE_ROOT/bin/fm-session-lock-lib.sh" || exit 2
if ! fm_session_lock_owned_by_self "$FM_HOME/state"; then
  printf '%s ownership failed\n' "$name" >> "$FM_HOME/state/failures"
  exit 0
fi
owner=$(<"$FM_HOME/state/.lock")
if ! fm_harness_pid_alive "$owner"; then
  printf '%s liveness failed\n' "$name" >> "$FM_HOME/state/failures"
  exit 0
fi
printf '%s %s\n' "$name" "$owner" >> "$FM_HOME/state/verified-hooks"
if [ "$name" = fm-sessionstart-run.sh ]; then
  printf 'FM_CLAUDE_SESSION_LOCK_READY\n'
fi
exit 0
SH
for hook in fm-sessionstart-run.sh fm-arm-pretool-check.sh fm-cd-pretool-check.sh \
  fm-subagent-pretool-check.sh fm-turnend-guard.sh fm-claude-stop-autoarm.sh; do
  cp "$LAB/probe.sh" "$LAB/bin/$hook"
  chmod +x "$LAB/bin/$hook"
done

# Node only launches the real executable and bounds its lifetime. No process
# identity, ancestry row, or hook result is synthesized here.
cat > "$LAB/launch.cjs" <<'JS'
const { spawnSync } = require("node:child_process");
const { existsSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");
let executable = process.env.FM_TEST_CLAUDE;
if (process.platform === "win32" && !existsSync(executable) && existsSync(`${executable}.exe`)) {
  executable += ".exe";
}
const prompt = "Run exactly printf 'FM_CLAUDE_LOCK_TOOL_OK\\n' with Bash once, then reply with exactly FM_CLAUDE_LOCK_DONE. Do not use any other command.";
const result = spawnSync(executable, [
  "-p", prompt, "--no-session-persistence", "--setting-sources", "project",
  "--strict-mcp-config", "--disable-slash-commands", "--no-chrome",
  "--tools", "Bash", "--allowedTools", "Bash", "--permission-mode", "dontAsk",
  "--effort", "low", "--output-format", "json",
], {
  cwd: process.env.FM_TEST_NATIVE_LAB, env: process.env,
  encoding: "utf8", timeout: 180000, maxBuffer: 4 * 1024 * 1024,
});
writeFileSync(join(process.env.FM_TEST_NATIVE_LAB, "expected-owner"), String(result.pid));
writeFileSync(join(process.env.FM_TEST_NATIVE_LAB, "transcript.json"), result.stdout || "");
writeFileSync(join(process.env.FM_TEST_NATIVE_LAB, "stderr.log"), result.stderr || "");
if (result.error) {
  console.error(`Claude session launch failed: ${result.error.code || result.error.name}`);
}
process.exit(result.status ?? 1);
JS

NATIVE_LAB=$LAB
CLAUDE_PATH=$(command -v claude)
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    NATIVE_LAB=$(cygpath -w "$LAB") || fail "could not convert native lab path"
    CLAUDE_PATH=$(cygpath -w "$CLAUDE_PATH") || fail "could not convert Claude executable path"
    ;;
esac
RC=0
env -u COPILOT_CLI -u COPILOT_LOADER_PID -u COPILOT_AGENT_SESSION_ID \
  -u CLAUDECODE -u CLAUDE_PID -u CLAUDE_CODE_SESSION_ID \
  -u GROK_AGENT -u GROK_HOOK_EVENT -u FM_PROC_ROOT_OVERRIDE \
  FM_HOME="$LAB" FM_STATE_OVERRIDE="$LAB/state" FM_ROOT_OVERRIDE="$LAB" \
  FM_TEST_CODE_ROOT="$ROOT" FM_TEST_CLAUDE="$CLAUDE_PATH" FM_TEST_NATIVE_LAB="$NATIVE_LAB" \
  CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false \
  node "$LAB/launch.cjs" || RC=$?

if [ -s "$LAB/state/failures" ]; then
  fail "Claude $CLAUDE_VERSION (launched native PID $(<"$LAB/expected-owner")): $(<"$LAB/state/failures")"
fi
[ "$RC" -eq 0 ] || fail "Claude $CLAUDE_VERSION: live identity session exited $RC"
jq -e '.is_error == false and (.result | contains("FM_CLAUDE_LOCK_DONE"))' \
  "$LAB/transcript.json" >/dev/null || fail "Claude $CLAUDE_VERSION: the requested tool turn did not complete"

# The async Stop hook can still be finishing after the print process exits.
for ((attempt=0; attempt<300; attempt++)); do
  grep -q '^fm-claude-stop-autoarm.sh ' "$LAB/state/verified-hooks" 2>/dev/null && break
  [ ! -s "$LAB/state/failures" ] || fail "Claude $CLAUDE_VERSION: $(<"$LAB/state/failures")"
  sleep 0.1
done
[ ! -s "$LAB/state/failures" ] || fail "Claude $CLAUDE_VERSION: $(<"$LAB/state/failures")"
OWNER=$(<"$LAB/state/.lock")
case "$OWNER" in ''|*[!0-9]*|0|1) fail "Claude $CLAUDE_VERSION: invalid owner PID" ;; esac
[ "$OWNER" = "$(<"$LAB/expected-owner")" ] \
  || fail "Claude $CLAUDE_VERSION: the recorded owner is not the Claude process launched by this test"
for hook in fm-sessionstart-run.sh fm-arm-pretool-check.sh fm-cd-pretool-check.sh \
  fm-subagent-pretool-check.sh fm-turnend-guard.sh fm-claude-stop-autoarm.sh; do
  grep -Fxq "$hook $OWNER" "$LAB/state/verified-hooks" \
    || fail "Claude $CLAUDE_VERSION: $hook did not verify the session-start owner"
done
awk -v owner="$OWNER" '$2 != owner { exit 1 }' "$LAB/state/verified-hooks" \
  || fail "Claude $CLAUDE_VERSION: ownership changed between hook processes"
pass "Claude $CLAUDE_VERSION: SessionStart, Bash pre-tool hooks, and both Stop hooks verify one live session owner"

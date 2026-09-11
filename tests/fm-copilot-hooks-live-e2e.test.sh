#!/usr/bin/env bash
# Opt-in live guard for GitHub Copilot CLI repository hook discovery, ordering,
# asynchronous notifications, and coexistence with enabled Claude settings.
# The coexistence case uses the tracked registrations and recorder hook bodies
# in an isolated project; no fleet bootstrap or supervision is invoked.
# Run all cases with FM_COPILOT_HOOKS_LIVE_E2E=1, or select one with FM_TEST_ONLY.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate opt-in FM_COPILOT_HOOKS_LIVE_E2E

COPILOT_BIN=${FM_COPILOT_BIN:-$(command -v copilot || true)}
[ -n "$COPILOT_BIN" ] && [ -x "$COPILOT_BIN" ] \
  || fail "copilot not found; install it or set FM_COPILOT_BIN. This guard refuses to pass without checking the real harness."
COPILOT_VERSION=$("$COPILOT_BIN" --version 2>/dev/null | head -1)
[ -n "$COPILOT_VERSION" ] || fail "copilot did not report a version"
printf 'harness: %s\n' "$COPILOT_VERSION"

make_hook_project() {
  local lab=$1
  mkdir -p "$lab/.github/hooks" || fail "could not create the isolated hook directory"
  git init -q "$lab" || fail "could not initialize the isolated hook repository"
  git -C "$lab" -c user.email=fmtest@example.invalid -c user.name=fmtest \
    commit -q --allow-empty -m init || fail "could not initialize the hook fixture history"
}

test_repository_hook_discovery_and_order() {
  local lab out rc order
  command -v timeout >/dev/null 2>&1 || fail "timeout not found"
  lab=$(fm_test_tmproot fm-copilot-hooks)
  make_hook_project "$lab"
  cat > "$lab/.github/hooks/firstmate.json" <<'JSON'
{"version":1,"hooks":{"sessionStart":[{"type":"command","bash":"printf 'firstmate\\n' >> hook-order.log","powershell":"Add-Content -LiteralPath 'hook-order.log' -Value 'firstmate'","cwd":".","timeoutSec":10}]}}
JSON
  cat > "$lab/.github/hooks/zz-firstmate-probe.json" <<'JSON'
{"version":1,"hooks":{"sessionStart":[{"type":"command","bash":"printf 'visible\\n' >> hook-order.log","powershell":"Add-Content -LiteralPath 'hook-order.log' -Value 'visible'","cwd":".","timeoutSec":10}]}}
JSON
  cat > "$lab/.github/hooks/.firstmate-hidden-probe.json" <<'JSON'
{"version":1,"hooks":{"sessionStart":[{"type":"command","bash":"printf 'hidden\\n' >> hook-order.log","powershell":"Add-Content -LiteralPath 'hook-order.log' -Value 'hidden'","cwd":".","timeoutSec":10}]}}
JSON
  out=$(timeout 240 "$COPILOT_BIN" -C "$lab" --allow-all --no-ask-user \
    -p "Reply only with OK." 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || fail "Copilot prompt failed before hook discovery could be verified: $out"
  [ -f "$lab/hook-order.log" ] || fail "Copilot loaded no repository sessionStart hooks"
  order=$(tr -d '\r' < "$lab/hook-order.log")
  [ "$order" = $'visible\nfirstmate' ] \
    || fail "expected visible generated hook before firstmate.json and hidden hook skipped, got: $order"
  pass "Copilot repository hooks ignore hidden files and load visible files in descending filename order"
}

test_async_shell_completion_context() {
  local lab token tool command prompt out rc
  command -v timeout >/dev/null 2>&1 || fail "timeout not found"
  lab=$(fm_test_tmproot fm-copilot-async)
  token="FM_COPILOT_ASYNC_NOTIFICATION_$$"
  make_hook_project "$lab"
  cat > "$lab/notification.sh" <<EOF
#!/usr/bin/env bash
set -u
payload=\$(cat)
printf '%s\n' "\$payload" >> notification.log
jq -n --arg c "$token" '{additionalContext:\$c}'
EOF
  chmod +x "$lab/notification.sh"
  cat > "$lab/notification.ps1" <<EOF
\$payload = [Console]::In.ReadToEnd()
Add-Content -LiteralPath "notification.log" -Value \$payload
@{ additionalContext = "$token" } | ConvertTo-Json -Compress
EOF
  cat > "$lab/.github/hooks/async-notification.json" <<'JSON'
{
  "version": 1,
  "hooks": {
    "notification": [
      {
        "matcher": "shell_completed",
        "type": "command",
        "bash": "bash ./notification.sh",
        "powershell": "& './notification.ps1'",
        "cwd": ".",
        "timeoutSec": 10
      }
    ]
  }
}
JSON
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) tool=powershell; command='Start-Sleep -Seconds 2' ;;
    *) tool=bash; command='sleep 2' ;;
  esac
  prompt="Use the $tool tool exactly once with its native asynchronous mode and the exact command: $command
After that tool call returns, reply exactly ASYNC_STARTED.
If a later system message contains $token, reply exactly $token.
Do not run any other tool."
  out=$(COPILOT_TASK_WAIT_TIMEOUT_SECONDS=60 timeout 300 "$COPILOT_BIN" -C "$lab" \
    --allow-all --no-ask-user --available-tools "$tool" -p "$prompt" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || fail "Copilot async shell notification probe failed: $out"
  assert_contains "$out" "ASYNC_STARTED" \
    "Copilot did not continue the initiating turn after starting the background shell task"
  assert_contains "$out" "$token" \
    "a background shell completion did not inject notification additionalContext into an idle Copilot session"
  [ -f "$lab/notification.log" ] \
    || fail "the shell completion did not fire the configured notification hook"
  grep -q '"notification_type":"shell_completed"' "$lab/notification.log" \
    || fail "the notification hook did not receive a shell_completed payload: $(cat "$lab/notification.log")"
  pass "Copilot background shell completion asynchronously injects a follow-up turn"
}

test_claude_settings_coexist_with_copilot() {
  local lab native_lab native_copilot script
  command -v node >/dev/null 2>&1 || fail "node not found"
  lab=$(fm_test_tmproot fm-copilot-claude-hooks)
  make_hook_project "$lab"
  mkdir -p "$lab/.claude" "$lab/bin" "$lab/state" "$lab/.github/skills/fm-hook-probe"
  cp "$ROOT/.claude/settings.json" "$lab/.claude/settings.json" || fail "active Claude settings are missing"
  cp "$ROOT/.github/hooks/firstmate.json" "$lab/.github/hooks/firstmate.json"
  for script in fm-sessionstart-run.sh fm-arm-pretool-check.sh fm-cd-pretool-check.sh \
    fm-subagent-pretool-check.sh fm-turnend-guard.sh fm-claude-stop-autoarm.sh; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> claude.invoked\n' "$script" > "$lab/bin/$script"
    chmod +x "$lab/bin/$script"
  done
  cat > "$lab/bin/fm-ghcp-hook.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> copilot.invoked
if [ "${1:-}:${2:-}" = pretool:probe ] && [ -f deny-tools ]; then
  printf '%s\n' '{"permissionDecision":"deny","permissionDecisionReason":"FM_NATIVE_PRETOOL_DENIAL"}'
fi
exit 0
SH
  cat > "$lab/bin/fm-ghcp-hook.ps1" <<'PS'
param([string]$Action, [string]$Policy)
Add-Content -LiteralPath 'copilot.invoked' -Value ("$Action $Policy".Trim())
if ($Action -eq 'pretool' -and $Policy -eq 'probe' -and (Test-Path -LiteralPath 'deny-tools')) {
    '{"permissionDecision":"deny","permissionDecisionReason":"FM_NATIVE_PRETOOL_DENIAL"}'
}
exit 0
PS
  cat > "$lab/.github/hooks/zz-firstmate-pretool-probe.json" <<'JSON'
{"version":1,"hooks":{"PreToolUse":[{"matcher":".*","type":"command","bash":"bash ./bin/fm-ghcp-hook.sh pretool probe","powershell":"& './bin/fm-ghcp-hook.ps1' pretool probe","cwd":".","timeoutSec":10}]}}
JSON
  cat > "$lab/.github/skills/fm-hook-probe/SKILL.md" <<'MD'
---
name: fm-hook-probe
description: Read the exact fact file supplied in the prompt and report its content.
---
Use the view tool to read the absolute file path supplied in the prompt and report its exact contents.
Do not run commands or modify files.
MD
  native_lab=$lab
  native_copilot=$COPILOT_BIN
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      native_lab=$(cygpath -w "$lab") || fail "could not convert Copilot fixture path"
      native_copilot=$(cygpath -w "$COPILOT_BIN") || fail "could not convert Copilot executable path"
      ;;
  esac
  FM_COPILOT_LIVE_LAB="$native_lab" FM_COPILOT_LIVE_BIN="$native_copilot" \
    node --input-type=module <<'JS' || fail "$COPILOT_VERSION: Claude/Copilot hook coexistence failed"
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
const lab = process.env.FM_COPILOT_LIVE_LAB;
let executable = process.env.FM_COPILOT_LIVE_BIN;
if (process.platform === "win32" && !existsSync(executable) && existsSync(`${executable}.exe`)) executable += ".exe";
const token = `FM_READ_${randomUUID()}`;
const fact = join(lab, "fact.txt");
writeFileSync(fact, `${token}\n`);
const env = { ...process.env, FM_HOME: lab, FM_STATE_OVERRIDE: join(lab, "state"), FM_ROOT_OVERRIDE: lab };
for (const name of ["COPILOT_CLI", "COPILOT_LOADER_PID", "COPILOT_AGENT_SESSION_ID", "CLAUDECODE", "CLAUDE_PID", "CLAUDE_PROJECT_DIR", "GROK_AGENT", "GROK_HOOK_EVENT"]) delete env[name];
function run(prompt, tools) {
  const result = spawnSync(executable, [
    "-C", lab, "--available-tools", ...tools, "--allow-tool", "view", "--allow-tool", "skill", "--no-ask-user",
    "--no-custom-instructions", "--disable-builtin-mcps", "--no-auto-update", "--no-remote", "--no-remote-export",
    "--log-dir", join(lab, "logs"), "--output-format", "json", "-p", prompt,
  ], { cwd: lab, env, encoding: "utf8", timeout: 120000, maxBuffer: 4 * 1024 * 1024 });
  assert.equal(result.error?.code, undefined, "Copilot launch must finish within its bound");
  assert.equal(result.status, 0, "Copilot prompt must finish successfully");
  // Inspect only structured tool verdicts and public replies, never credentials,
  // opaque model state, or raw debug logs.
  const events = (result.stdout || "").split(/\r?\n/).flatMap(line => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
  const names = new Map(events.filter(e => e.type === "tool.execution_start").map(e => [e.data.toolCallId, e.data.toolName]));
  const toolsUsed = events.filter(e => e.type === "tool.execution_complete").map(e => ({
    name: names.get(e.data.toolCallId), success: e.data.success, error: e.data.error?.message || "",
  }));
  assert.ok(toolsUsed.length > 0, "Copilot must actually try a tool");
  for (const tool of toolsUsed) assert.ok(!tool.error.includes("hook errored"), `${tool.name}: ${tool.error}`);
  const replies = events.filter(e => e.type === "assistant.message").map(e => e.data.content || "").join("\n");
  return { toolsUsed, replies };
}
const healthy = run(`Use the skill tool to load fm-hook-probe first, then use view to read ${JSON.stringify(fact)}. Reply with that file's entire contents. Use no other tool.`, ["view", "skill"]);
for (const name of ["skill", "view"]) {
  assert.ok(healthy.toolsUsed.some(tool => tool.name === name && tool.success), `Copilot must successfully execute ${name}`);
}
assert.ok(healthy.replies.includes(token), "the read must deliver the actual file contents");
assert.ok(!existsSync(join(lab, "claude.invoked")), "Copilot must not execute imported Claude operational scripts");
const nativeEvents = readFileSync(join(lab, "copilot.invoked"), "utf8").split(/\r?\n/);
for (const event of ["session-start", "primary-stop", "pretool probe"]) {
  assert.ok(nativeEvents.includes(event), `Copilot's native ${event} hook must remain active`);
}
writeFileSync(join(lab, "deny-tools"), "deny\n");
const denied = run(`Use view once to read ${JSON.stringify(fact)}. If it is denied, report the denial and stop. Do not use another tool.`, ["view"]);
assert.ok(denied.toolsUsed.some(tool => tool.name === "view" && !tool.success && tool.error.includes("FM_NATIVE_PRETOOL_DENIAL")), "Copilot's native pre-tool policy must still be able to deny access");
assert.ok(!existsSync(join(lab, "claude.invoked")), "the negative control must not execute Claude scripts either");
JS
  pass "$COPILOT_VERSION: skill and file reads work with Claude settings enabled; native Copilot hooks still run and enforce denial"
}

fm_test_run_cases \
  test_repository_hook_discovery_and_order \
  test_async_shell_completion_context \
  test_claude_settings_coexist_with_copilot

// Execute only through the shell guard, which supplies an isolated fixture and
// the installed binaries. No credentials or real fleet home are copied here.
import assert from "node:assert/strict";
import http from "node:http";
import { spawn, spawnSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, rmSync, chmodSync } from "node:fs";
import { join, dirname } from "node:path";

const root = process.env.FM_COPILOT_TEST_ROOT;
const lab = process.env.FM_COPILOT_TEST_LAB;
const bash = process.env.FM_COPILOT_TEST_BASH;
const copilot = process.env.FM_COPILOT_TEST_BIN;
assert.ok(root && lab && bash && copilot, "run through the shell test entrypoint");
const helper = join(root, "bin/fm-herdr-lab.sh");
const state = join(lab, "state");
const profile = join(lab, "profile");
const helperEnv = { ...process.env, FM_HERDR_LAB_STATE_DIR: join(lab, "herdr-lab-records") };
for (const name of ["COPILOT_CLI", "COPILOT_LOADER_PID", "COPILOT_AGENT_SESSION_ID", "COPILOT_PROVIDER_API_KEY", "COPILOT_PROVIDER_BEARER_TOKEN", "COPILOT_PROVIDER_HEADERS", "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", "CLAUDECODE", "CLAUDE_PID", "GROK_AGENT", "GROK_HOOK_EVENT", "MSYS_NO_PATHCONV"]) delete helperEnv[name];
let session;
let pane;
let provisionAttempted = false;
let calls = 0;
let requests = [];
let phase = "initial";
let readAttempts = 0;
let lastReadId;
let retireReplies = 0;
let requestError;
let transcript;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function helperCall(args, timeout = 35000) {
  return new Promise((resolve, reject) => {
    // Exercise the helper's real argument transport, including slash commands.
    const env = { ...helperEnv };
    const child = spawn(bash, [helper, ...args], { env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => { child.kill("SIGTERM"); reject(new Error(`Herdr helper timed out: ${args.slice(0, 4).join(" ")}`)); }, timeout);
    child.stdout.on("data", chunk => { stdout += chunk; });
    child.stderr.on("data", chunk => { stderr += chunk; });
    child.on("error", error => { clearTimeout(timer); reject(error); });
    child.on("close", code => { clearTimeout(timer); resolve({ code, stdout, stderr }); });
  });
}
const herdr = (...args) => helperCall(["run", session, ...args]);
function events() {
  if (!transcript) {
    const directory = join(profile, "session-state");
    if (!existsSync(directory)) return [];
    for (const id of readdirSync(directory)) {
      const candidate = join(directory, id, "events.jsonl");
      if (existsSync(candidate)) { transcript = candidate; break; }
    }
  }
  if (!transcript) return [];
  return readFileSync(transcript, "utf8").split(/\r?\n/).flatMap(line => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
}
function replied(text) {
  return events().some(event => event.type === "assistant.message" && event.data.content?.includes(text));
}
function watcherCount() {
  const file = join(state, "watch-count");
  return existsSync(file) ? Number(readFileSync(file, "utf8")) : 0;
}
async function waitFor(predicate, description, attempts = 450) {
  for (let i = 0; i < attempts; i++) {
    if (requestError) throw requestError;
    if (await predicate()) return;
    await delay(200);
  }
  const recent = events().slice(-8).map(event => ({ type: event.type, at: event.timestamp, hook: event.data?.hookType }));
  throw new Error(`${description}; requests=${calls}, watcherStarts=${watcherCount()}, lastEvents=${JSON.stringify(recent)}`);
}
function tool(name, args, id) {
  return { role: "assistant", tool_calls: [{ index: 0, id, type: "function", function: {
    name, arguments: JSON.stringify(args),
  } }] };
}
function shell(command, mode, id) {
  return tool("powershell", { command, mode, ...(mode === "async" ? { shellId: id } : {}), description: "Exercise isolated Firstmate supervision" }, id);
}
function readReady(which) {
  assert.ok(++readAttempts <= 12, "the real arm wrapper must confirm startup within its bound");
  lastReadId = `read-${which}-${readAttempts}`;
  phase = `confirm-${which}`;
  return tool("read_powershell", { shellId: `${which}-watch`, delay: 5 }, lastReadId);
}

mkdirSync(state, { recursive: true });
mkdirSync(profile, { recursive: true });
mkdirSync(join(lab, ".github/hooks"), { recursive: true });
mkdirSync(join(lab, ".claude"), { recursive: true });
cpSync(join(root, "bin"), join(lab, "bin"), { recursive: true });
cpSync(join(root, ".github/hooks/firstmate.json"), join(lab, ".github/hooks/firstmate.json"));
cpSync(join(root, ".claude/settings.json"), join(lab, ".claude/settings.json"));
writeFileSync(join(lab, "AGENTS.md"), "# Isolated Firstmate supervision fixture\n");
writeFileSync(join(state, "fixture.meta"), "project=fixture\n");
writeFileSync(join(profile, "config.json"), JSON.stringify({ trustedFolders: [lab], firstLaunchAt: new Date().toISOString() }));
for (const args of [["init", "-q", lab], ["-C", lab, "-c", "user.name=fmtest", "-c", "user.email=fmtest@example.invalid", "commit", "-qm", "fixture", "--allow-empty"]]) {
  assert.equal(spawnSync("git", args, { encoding: "utf8" }).status, 0, "initialize the isolated primary");
}
writeFileSync(join(lab, "bin/fm-sessionstart-run.sh"), `#!/usr/bin/env bash
"$(dirname "$0")/fm-lock.sh" > "$FM_HOME/startup.log" 2>&1
`);
writeFileSync(join(lab, "bin/fm-wake-drain.sh"), `#!/usr/bin/env bash
printf drained >> "$FM_HOME/state/drained"
`);
writeFileSync(join(lab, "bin/fm-watch.sh"), `#!/usr/bin/env bash
set -eu
. "$(dirname "$0")/fm-wake-lib.sh"
lock="$STATE/.watch.lock"
fm_lock_try_acquire "$lock" || exit 1
printf '%s\\n' "$FM_HOME" > "$lock/fm-home"
printf '%s\\n' "$FM_WAKE_LIB_DIR/fm-watch.sh" > "$lock/watcher-path"
fm_pid_identity "$$" > "$lock/pid-identity"
trap 'fm_lock_release "$lock"' EXIT
trap 'exit 143' TERM
n=0
[ ! -f "$STATE/watch-count" ] || n=$(<"$STATE/watch-count")
n=$((n + 1))
printf '%s\\n' "$n" > "$STATE/watch-count"
for ((i=0; i<900; i++)); do
  touch "$STATE/.last-watcher-beat"
  [ ! -e "$STATE/release-$n" ] || break
  sleep 0.2
done
printf 'stale: fixture watcher %s completed\\n' "$n"
`);

for (const name of ["fm-sessionstart-run.sh", "fm-wake-drain.sh", "fm-watch.sh"]) chmodSync(join(lab, "bin", name), 0o755);

const server = http.createServer((req, res) => {
  let raw = "";
  req.on("data", chunk => { raw += chunk; });
  req.on("end", () => {
    try {
      if (req.method === "GET" && req.url.endsWith("/models")) {
        res.setHeader("Content-Type", "application/json");
        res.end(JSON.stringify({ object: "list", data: [{ id: "gpt-5-mini", object: "model", owned_by: "fixture" }] }));
        return;
      }
      assert.equal(req.method, "POST", "only the local model endpoint is expected");
      assert.ok(req.url.endsWith("/chat/completions"));
      const body = JSON.parse(raw);
      calls++;
      requests.push({ number: calls, phase, hasRepair: raw.includes("TURN WOULD END BLIND"), hasNotification: raw.includes("tracked asynchronous watcher task completed") });
      let message;
      switch (phase) {
        case "initial":
          phase = "repair";
          message = { role: "assistant", content: "FIRST_RESPONSE" }; break;
        case "repair":
          assert.ok(raw.includes("TURN WOULD END BLIND"), "the actual Stop repair must reach the model");
          phase = "read-first";
          message = shell(".\\bin\\fm-watch-arm.ps1", "async", "first-watch"); break;
        case "read-first": message = readReady("first"); break;
        case "confirm-first":
        case "confirm-second": {
          const which = phase.endsWith("first") ? "first" : "second";
          const result = body.messages.findLast(entry => entry.role === "tool" && entry.tool_call_id === lastReadId);
          const output = JSON.stringify(result?.content || "");
          assert.ok(!output.includes("watcher: FAILED"), `the ${which} watcher startup failed: ${output}`);
          if (/watcher: (started|attached) pid=/.test(output)) {
            phase = which === "first" ? "ping" : "done";
            readAttempts = 0;
            message = { role: "assistant", content: which === "first" ? "MONITORING_STARTED" : "MONITORING_REARMED" };
          } else message = readReady(which);
          break;
        }
        case "ping":
          assert.ok(raw.includes("MONITORING_PING"), "a real prompt must remain responsive while the watcher runs");
          phase = "notification";
          message = { role: "assistant", content: "MONITORING_RESPONSIVE" }; break;
        case "notification": {
          const notice = JSON.stringify(body.messages.findLast(entry => entry.role === "user")?.content || "");
          assert.ok(notice.includes("first-watch") && notice.includes("completed"), "the native completion notification must reach the model");
          phase = "completion-output";
          message = tool("read_powershell", { shellId: "first-watch", delay: 1 }, "completed-first-watch"); break;
        }
        case "completion-output": {
          const result = body.messages.findLast(entry => entry.role === "tool" && entry.tool_call_id === "completed-first-watch");
          assert.ok(JSON.stringify(result?.content).includes("stale: fixture watcher 1 completed"), "the native completion must retain the watcher output");
          phase = "drained";
          message = shell(".\\bin\\fm-windows-git-bash.ps1 'bin/fm-wake-drain.sh'", "sync", "drain"); break;
        }
        case "drained":
          phase = "read-second";
          message = shell(".\\bin\\fm-watch-arm.ps1", "async", "second-watch"); break;
        case "read-second": message = readReady("second"); break;
        case "retiring": {
          const notice = JSON.stringify(body.messages.findLast(entry => entry.role === "user")?.content || "");
          assert.ok((notice.includes("second-watch") && notice.includes("completed")) || notice.includes("FIRSTMATE_OP:"), "only a native completion or delayed recovery notice may arrive while retiring");
          assert.ok(++retireReplies <= 2, "retirement must not enter a continuation loop");
          message = { role: "assistant", content: "MONITORING_FINISHED" }; break;
        }
        default: throw new Error(`unexpected model request ${calls} after monitoring was restored`);
      }
      const base = { id: `fixture-${calls}`, created: Math.floor(Date.now() / 1000), model: body.model || "gpt-5-mini" };
      const finish = message.tool_calls ? "tool_calls" : "stop";
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" });
      res.write(`data: ${JSON.stringify({ ...base, object: "chat.completion.chunk", choices: [{ index: 0, delta: message, finish_reason: null }] })}\n\n`);
      res.write(`data: ${JSON.stringify({ ...base, object: "chat.completion.chunk", choices: [{ index: 0, delta: {}, finish_reason: finish }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } })}\n\n`);
      res.end("data: [DONE]\n\n");
    } catch (error) {
      requestError = error;
      if (!res.headersSent) res.writeHead(500);
      res.end("fixture request failed");
    }
  });
});

try {
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const named = await helperCall(["name", "copilot-primary"]);
  assert.equal(named.code, 0, named.stderr);
  session = named.stdout.trim();
  provisionAttempted = true;
  const provisioned = await helperCall(["provision", session], 80000);
  assert.equal(provisioned.code, 0, provisioned.stderr);
  const env = {
    COPILOT_HOME: profile, COPILOT_OFFLINE: "true", COPILOT_AUTO_UPDATE: "false", COPILOT_ALLOW_ALL: "true", COPILOT_OTEL_ENABLED: "false",
    COPILOT_PROVIDER_BASE_URL: `http://127.0.0.1:${server.address().port}/v1`,
    COPILOT_PROVIDER_TYPE: "openai", COPILOT_PROVIDER_WIRE_API: "completions", COPILOT_PROVIDER_TRANSPORT: "http",
    COPILOT_PROVIDER_MODEL_ID: "gpt-5-mini", COPILOT_PROVIDER_WIRE_MODEL: "gpt-5-mini", COPILOT_MODEL: "gpt-5-mini",
    FM_HOME: lab, FM_ROOT_OVERRIDE: lab, FM_STATE_OVERRIDE: state, FM_ARM_CONFIRM_TIMEOUT: "30",
    PATH: `${dirname(copilot)};${process.env.Path || process.env.PATH}`,
  };
  const created = await herdr("workspace", "create", "--cwd", lab, "--label", "copilot-primary-proof", "--no-focus", ...Object.entries(env).flatMap(([key, value]) => ["--env", `${key}=${value}`]));
  assert.equal(created.code, 0, created.stderr);
  pane = JSON.parse(created.stdout).result.root_pane.pane_id;
  let started;
  for (let i = 0; i < 10; i++) {
    started = await herdr("agent", "start", "primary-proof", "--kind", "copilot", "--pane", pane, "--timeout", "20000");
    if (!started.code || !started.stderr.includes("agent_pane_busy")) break;
    await delay(500);
  }
  assert.equal(started.code, 0, started.stderr);
  await waitFor(async () => {
    const screen = await herdr("pane", "read", pane, "--source", "visible", "--lines", "8");
    return screen.stdout.includes("/ commands") && screen.stdout.includes("? help");
  }, "Copilot must render its ready composer", 100);
  const sent = await herdr("agent", "prompt", "primary-proof", "Reply exactly FIRST_RESPONSE.");
  assert.equal(sent.code, 0, sent.stderr);
  await waitFor(() => {
    if (watcherCount() !== 1 || !replied("MONITORING_STARTED")) return false;
    const es = events();
    const reply = es.findLast(event => event.type === "assistant.message" && event.data.content?.includes("MONITORING_STARTED"));
    return es.some(event => event.type === "hook.end" && event.data.hookType === "agentStop" && event.timestamp > reply.timestamp && event.data.success && event.data.output?.decision !== "block");
  }, "the blocked Stop must launch one native asynchronous watcher and then allow a healthy stop");
  const start = events().find(event => event.type === "session.start");
  console.log(`harness: Copilot ${start?.data.copilotVersion}`);
  // MSYS system symlinks are intentionally opaque to native Node. Ask the
  // production Bash predicate rather than treating them as NTFS directories.
  const health = spawnSync(bash, ["-c", '. "$1/bin/fm-wake-lib.sh"; fm_watcher_healthy "$2" "$FM_WAKE_LIB_DIR/fm-watch.sh" 300 "$FM_HOME"', "_", lab, state], {
    env: { ...helperEnv, FM_HOME: lab, FM_STATE_OVERRIDE: state }, encoding: "utf8", timeout: 15000,
  });
  assert.equal(health.status, 0, "watcher must own the real process lock and fresh beacon");
  const ping = await herdr("agent", "prompt", "primary-proof", "Reply MONITORING_PING without running any tools.");
  assert.equal(ping.code, 0, ping.stderr);
  await waitFor(() => {
    const es = events();
    const reply = es.findLast(event => event.type === "assistant.message" && event.data.content?.includes("MONITORING_RESPONSIVE"));
    return reply && es.some(event => event.type === "hook.end" && event.data.hookType === "agentStop" && event.timestamp > reply.timestamp && event.data.success && event.data.output?.decision !== "block");
  }, "the user must remain responsive and settle normally while monitoring runs");
  assert.equal(watcherCount(), 1, "an ordinary prompt must not duplicate the live watcher");
  writeFileSync(join(state, "release-1"), "release\n");
  await waitFor(() => watcherCount() === 2 && replied("MONITORING_REARMED"), "shell completion must resume handling and rearm monitoring");
  assert.ok(existsSync(join(state, "drained")), "completion must drain before rearming");
  const toolStarts = events().filter(event => event.type === "tool.execution_start");
  assert.equal(toolStarts.filter(event => event.data.toolName === "powershell" && event.data.arguments?.mode === "async").length, 2, "both watcher launches must use native async mode");
  phase = "retiring";
  const notificationsBefore = events().filter(event => event.type === "hook.end" && event.data.hookType === "notification").length;
  rmSync(join(state, "fixture.meta"));
  writeFileSync(join(state, "release-2"), "release\n");
  await waitFor(() => {
    const notifications = events().filter(event => event.type === "hook.end" && event.data.hookType === "notification");
    const es = events();
    const reply = es.findLast(event => event.type === "assistant.message" && event.data.content?.includes("MONITORING_FINISHED"));
    return !existsSync(join(state, ".watch.lock")) && notifications.length > notificationsBefore && notifications.at(-1).data.success && !notifications.at(-1).data.output?.additionalContext && reply && es.some(event => event.type === "hook.end" && event.data.hookType === "agentStop" && event.timestamp > reply.timestamp && event.data.success && event.data.output?.decision !== "block");
  }, "the second watcher must finish and its no-work notification must settle without a repair loop");
  assert.equal(watcherCount(), 2, "no-work completion must not start a third watcher");
  assert.ok(!requestError);
  const owner = Number(readFileSync(join(state, ".lock"), "utf8").trim());
  const alive = () => { try { process.kill(owner, 0); return true; } catch { return false; } };
  assert.ok(alive(), "the fixture's native Copilot process must still be alive before /exit");
  const exited = await herdr("pane", "run", pane, "/exit");
  assert.equal(exited.code, 0, exited.stderr);
  await waitFor(() => !alive(), "literal /exit must exit the fixture agent, not become a Windows pathname", 150);
  console.log("ok - native Copilot repairs a missing watcher, stays responsive, handles its completion, rearms exactly once, and accepts literal /exit");
} catch (error) {
  const diagnostics = events().filter(event => event.type === "tool.execution_complete").slice(-4).map(event => ({
    success: event.data.success, error: event.data.error?.message, result: event.data.result,
  }));
  const hookResults = events().filter(event => event.type === "hook.start" || event.type === "hook.end").slice(-12).map(event => ({
    type: event.type, hook: event.data.hookType, success: event.data.success,
    notificationType: event.data.input?.notificationType || event.data.input?.notification_type,
    output: event.data.output,
  }));
  console.error(JSON.stringify({ phase, watcherStarts: watcherCount(), requests, toolResults: diagnostics, hookResults }, null, 2).slice(0, 10000));
  throw error;
} finally {
  writeFileSync(join(lab, "request-summary.json"), JSON.stringify(requests, null, 2));
  rmSync(join(state, "fixture.meta"), { force: true });
  for (let n = 1; n <= 8; n++) writeFileSync(join(state, `release-${n}`), "release\n");
  await delay(1500);
  try {
    if (session && provisionAttempted) {
      const cleanup = await helperCall(["teardown", session], 45000);
      assert.equal(cleanup.code, 0, `isolated Herdr cleanup: ${cleanup.stderr}`);
    }
  } finally {
    server.closeAllConnections();
    server.close();
  }
}

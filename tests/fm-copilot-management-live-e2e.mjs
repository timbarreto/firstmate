// Run through the shell entrypoint. Real Copilot/PowerShell/Herdr transports,
// a local deterministic model provider, and fixture-only waiting jobs.
import assert from "node:assert/strict";
import http from "node:http";
import { spawn } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const root = process.env.FM_COPILOT_TEST_ROOT;
const lab = process.env.FM_COPILOT_TEST_LAB;
const bash = process.env.FM_COPILOT_TEST_BASH;
let copilot = process.env.FM_COPILOT_TEST_BIN;
assert.ok(root && lab && bash && copilot);
if (!existsSync(copilot) && existsSync(`${copilot}.exe`)) copilot += ".exe";
const helper = join(root, "bin/fm-herdr-lab.sh");
const profile = join(lab, "profile");
const env = { ...process.env, FM_HERDR_LAB_STATE_DIR: join(lab, "lab-records") };
for (const name of ["COPILOT_CLI", "COPILOT_LOADER_PID", "COPILOT_AGENT_SESSION_ID", "COPILOT_PROVIDER_API_KEY", "COPILOT_PROVIDER_BEARER_TOKEN", "COPILOT_PROVIDER_HEADERS", "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", "CLAUDECODE", "CLAUDE_PID", "MSYS_NO_PATHCONV"]) delete env[name];
let session;
let provisioned = false;
let pane;
let phase = "deny";
let failure;
let calls = 0;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

function run(args, timeout = 45000) {
  return new Promise((resolve, reject) => {
    const child = spawn(bash, args, { env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "", stderr = "";
    const timer = setTimeout(() => { child.kill("SIGTERM"); reject(new Error("bounded lab command timed out")); }, timeout);
    child.stdout.on("data", data => { stdout += data; });
    child.stderr.on("data", data => { stderr += data; });
    child.on("error", error => { clearTimeout(timer); reject(error); });
    child.on("close", code => { clearTimeout(timer); resolve({ code, stdout, stderr }); });
  });
}
const labCall = (...args) => run([helper, ...args]);
const herdr = (...args) => labCall("run", session, ...args);
function events() {
  const directory = join(profile, "session-state");
  if (!existsSync(directory)) return [];
  const file = readdirSync(directory).map(id => join(directory, id, "events.jsonl")).find(existsSync);
  if (!file) return [];
  return readFileSync(file, "utf8").split(/\r?\n/).flatMap(line => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
}
function replied(text) {
  return events().some(event => event.type === "assistant.message" && event.data.content?.includes(text));
}
async function waitFor(test, message, attempts = 300) {
  for (let i = 0; i < attempts; i++) {
    if (failure) throw failure;
    if (await test()) return;
    await delay(200);
  }
  throw new Error(`${message}; phase=${phase}, calls=${calls}`);
}
const tool = (name, args, id) => ({ role: "assistant", tool_calls: [{ index: 0, id, type: "function", function: { name, arguments: JSON.stringify(args) } }] });
const shell = (command, mode, id) => tool("powershell", { command, mode, shellId: id, description: "Isolated management contract" }, id);
const message = content => ({ role: "assistant", content });

mkdirSync(join(lab, ".github/hooks"), { recursive: true });
mkdirSync(profile, { recursive: true });
cpSync(join(root, "bin"), join(lab, "bin"), { recursive: true });
writeFileSync(join(lab, "AGENTS.md"), "# Isolated management fixture\n");
const registrations = JSON.parse(readFileSync(join(root, ".github/hooks/firstmate.json"), "utf8"));
writeFileSync(join(lab, ".github/hooks/firstmate.json"), JSON.stringify({ version: 1, hooks: { PreToolUse: registrations.hooks.PreToolUse } }));
writeFileSync(join(profile, "config.json"), JSON.stringify({ trustedFolders: [lab], firstLaunchAt: new Date().toISOString() }));
writeFileSync(join(profile, "settings.json"), JSON.stringify({ ide: { autoConnect: false } }));
const shellQuotedCopilot = "'" + copilot.replaceAll("\\", "/").replaceAll("'", "'\\''") + "'";
writeFileSync(join(lab, "launch-worker.sh"), `#!/usr/bin/env bash\n${shellQuotedCopilot} --no-auto-update --no-remote --no-remote-export --no-custom-instructions --allow-all --no-ask-user\n`);
writeFileSync(join(lab, "bin/fm-watch-arm.ps1"), `Add-Content -LiteralPath "$PSScriptRoot/../watch-starts" -Value started
Write-Output 'watcher: started pid=fixture (beacon fresh)'
while (!(Test-Path -LiteralPath "$PSScriptRoot/../release-watch")) { Start-Sleep -Milliseconds 200 }
Write-Output 'WATCH_FINISHED'
`);
writeFileSync(join(lab, "management.ps1"), `Set-Content -LiteralPath "$PSScriptRoot/management-started" -Value started
while (!(Test-Path -LiteralPath "$PSScriptRoot/release-management")) { Start-Sleep -Milliseconds 200 }
Write-Output 'MANAGEMENT_FINISHED'
`);
// The production classifier still performs all API and native queries. This
// transport wrapper merely routes every Herdr call through the lab guard.
writeFileSync(join(lab, "classify.sh"), `#!/usr/bin/env bash
set -eu
root=$1; helper=$2; session=$3; pane=$4; missing=\${5:-0}
. "$root/bin/fm-backend.sh"
herdr() {
  local count=$#
  [ "$count" -ge 2 ] || return 2
  [ "\${@: -2:1}" = --session ] && [ "\${@: -1}" = "$session" ] || return 2
  if [ "$missing" = 1 ] && [ "$1 $2" = 'agent get' ]; then
    printf '%s\\n' '{"error":{"code":"agent_not_found"}}'
    return 1
  fi
  bash "$helper" run "$session" "\${@:1:count-2}"
}
fm_backend_agent_state herdr "$session:$pane"
`);

const server = http.createServer((req, res) => {
  let raw = "";
  req.on("data", data => { raw += data; });
  req.on("end", () => {
    try {
      if (req.method === "GET" && req.url.endsWith("/models")) {
        res.setHeader("Content-Type", "application/json");
        res.end(JSON.stringify({ object: "list", data: [{ id: "gpt-5-mini", object: "model", owned_by: "fixture" }] }));
        return;
      }
      assert.ok(req.url.endsWith("/chat/completions"));
      const request = JSON.parse(raw);
      const lastTool = request.messages.findLast(entry => entry.role === "tool");
      const output = JSON.stringify(lastTool?.content || "");
      let reply;
      switch (phase) {
        case "deny":
          phase = "denied";
          reply = shell("./bin/fm-watch-arm.ps1 | Out-Null", "sync", "denied-watch"); break;
        case "denied":
          assert.ok(output.includes("watcher-pipeline") || output.includes("watcher-bundled"), "the real command policy must deny the composed watch command");
          assert.ok(!existsSync(join(lab, "watch-starts")), "a denied command must never execute");
          phase = "read-watch";
          reply = shell("./bin/fm-watch-arm.ps1", "async", "watch-proof"); break;
        case "read-watch":
          phase = "confirmed-watch";
          reply = tool("read_powershell", { shellId: "watch-proof", delay: 1 }, "short-confirmation"); break;
        case "confirmed-watch":
          if (!output.includes("watcher: started")) {
            assert.ok(calls < 12, "short startup confirmation must remain bounded");
            reply = tool("read_powershell", { shellId: "watch-proof", delay: 1 }, `short-${calls}`);
          } else {
            phase = "started-management";
            reply = shell("./management.ps1", "async", "management-proof");
          }
          break;
        case "started-management": phase = "ping"; reply = message("MANAGEMENT_STARTED"); break;
        case "ping":
          assert.ok(raw.includes("MANAGEMENT_PING"), "a new prompt must arrive while both jobs are active");
          assert.ok(!existsSync(join(lab, "release-management")));
          phase = "management-notice";
          reply = message("MANAGEMENT_RESPONSIVE"); break;
        case "management-notice":
          assert.ok(raw.includes("management-proof") && raw.includes("completed"));
          phase = "management-output";
          reply = tool("read_powershell", { shellId: "management-proof", delay: 1 }, "completed-management"); break;
        case "management-output":
          assert.ok(output.includes("MANAGEMENT_FINISHED"));
          phase = "watch-notice";
          reply = message("MANAGEMENT_COMPLETE"); break;
        case "watch-notice":
          assert.ok(raw.includes("watch-proof") && raw.includes("completed"));
          phase = "done";
          reply = message("WATCH_COMPLETE"); break;
        default: throw new Error(`unexpected request after ${phase}`);
      }
      calls++;
      const base = { id: `management-${calls}`, created: Math.floor(Date.now() / 1000), model: request.model || "gpt-5-mini", object: "chat.completion.chunk" };
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" });
      res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: reply, finish_reason: null }] })}\n\n`);
      res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta: {}, finish_reason: reply.tool_calls ? "tool_calls" : "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } })}\n\n`);
      res.end("data: [DONE]\n\n");
    } catch (error) {
      failure = error;
      if (!res.headersSent) res.writeHead(500);
      res.end("fixture request failed");
    }
  });
});

try {
  const initialized = await run(["-c", 'git init -q "$1" && git -C "$1" -c user.name=fmtest -c user.email=fmtest@example.invalid commit -qm fixture --allow-empty', "_", lab]);
  assert.equal(initialized.code, 0, "initialize only the isolated hook repository");
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const named = await labCall("name", "copilot-mgmt");
  assert.equal(named.code, 0, named.stderr);
  session = named.stdout.trim();
  provisioned = true;
  const prepared = await run([helper, "provision", session], 80000);
  assert.equal(prepared.code, 0, prepared.stderr);
  const variables = {
    COPILOT_HOME: profile, COPILOT_OFFLINE: "true", COPILOT_AUTO_UPDATE: "false", COPILOT_ALLOW_ALL: "true", COPILOT_OTEL_ENABLED: "false",
    COPILOT_PROVIDER_BASE_URL: `http://127.0.0.1:${server.address().port}/v1`, COPILOT_PROVIDER_TYPE: "openai", COPILOT_PROVIDER_WIRE_API: "completions", COPILOT_PROVIDER_TRANSPORT: "http",
    COPILOT_PROVIDER_MODEL_ID: "gpt-5-mini", COPILOT_PROVIDER_WIRE_MODEL: "gpt-5-mini", COPILOT_MODEL: "gpt-5-mini", COPILOT_PROVIDER_API_KEY: "fixture",
    FM_HOME: lab, FM_ROOT_OVERRIDE: lab, FM_STATE_OVERRIDE: join(lab, "state"), HOME: profile,
    PATH: `${dirname(copilot)};${process.env.Path || process.env.PATH}`,
  };
  const created = await herdr("workspace", "create", "--cwd", lab, "--label", "copilot-management-proof", "--no-focus", ...Object.entries(variables).flatMap(([key, value]) => ["--env", `${key}=${value}`]));
  assert.equal(created.code, 0, created.stderr);
  pane = JSON.parse(created.stdout).result.root_pane.pane_id;
  // Match Firstmate's real Windows worker shape: PowerShell -> Git Bash
  // launch script -> native Copilot, rather than Herdr's registered agent start.
  const command = `& '${bash.replaceAll("'", "''")}' --login '${join(lab, "launch-worker.sh").replaceAll("'", "''")}'`;
  const started = await herdr("pane", "run", pane, command);
  assert.equal(started.code, 0, started.stderr);
  await waitFor(async () => {
    const screen = await herdr("pane", "read", pane, "--source", "visible", "--lines", "8");
    return screen.stdout.includes("/ commands") && screen.stdout.includes("? help");
  }, "the real CLI must reach its ready composer", 60);
  const registration = await herdr("agent", "get", pane);
  const naturallyMissing = JSON.parse(registration.stdout || registration.stderr).error?.code === "agent_not_found";
  const state = await run([join(lab, "classify.sh"), root, helper, session, pane]);
  assert.equal(state.code, 0, state.stderr);
  assert.equal(state.stdout.trim(), "alive", "the real native Copilot worker must not be reported stopped");
  // Preserve a real process tree and vary only the registry reply. Detection
  // timing can register a fresh lab worker even when the captured incident did
  // not; this controlled counterfactual is not claimed as a live registry loss.
  const missing = await run([join(lab, "classify.sh"), root, helper, session, pane, "1"]);
  assert.equal(missing.code, 0, missing.stderr);
  assert.equal(missing.stdout.trim(), "alive", "registry loss must not demote the real native worker");
  console.log(`native registry initially missing: ${naturallyMissing}; missing-registry counterfactual: alive`);
  await delay(500);
  assert.equal((await herdr("pane", "run", pane, "Begin the management proof.")).code, 0);
  await waitFor(() => replied("MANAGEMENT_STARTED"), "the policy/async startup sequence must finish");
  console.log(`harness: Copilot ${events().find(event => event.type === "session.start").data.copilotVersion}`);
  assert.equal((await herdr("pane", "run", pane, "MANAGEMENT_PING")).code, 0);
  await waitFor(() => replied("MANAGEMENT_RESPONSIVE"), "the session must stay responsive during management");
  writeFileSync(join(lab, "release-management"), "release\n");
  await waitFor(() => replied("MANAGEMENT_COMPLETE"), "the original async operation must complete without duplication");
  assert.equal(readFileSync(join(lab, "watch-starts"), "utf8").trim().split(/\r?\n/).length, 1, "management must preserve exactly one monitor");
  writeFileSync(join(lab, "release-watch"), "release\n");
  await waitFor(() => replied("WATCH_COMPLETE"), "monitor completion must reach the real session");
  const es = events();
  assert.ok(es.some(event => event.type === "tool.execution_complete" && event.data.success === false), "the negative command control must run");
  assert.ok(!es.some(event => event.type === "hook.end" && event.data.error), "command hooks must finish without timeout/errors");
  assert.equal((await herdr("pane", "run", pane, "/exit")).code, 0);
  await waitFor(async () => {
    const result = await run([join(lab, "classify.sh"), root, helper, session, pane]);
    return result.code === 0 && result.stdout.trim() === "dead";
  }, "native exit must reach a proven shell-only state", 20);
  console.log("ok - native command denial, separate async confirmation, responsive management, and real worker identity/exit with missing-registry counterfactual");
} catch (error) {
  if (pane) {
    const screen = await herdr("pane", "read", pane, "--source", "visible", "--lines", "12");
    console.error(`isolated pane: ${screen.stdout.slice(0, 3500)}`);
  }
  const recent = events().filter(event => ["hook.end", "tool.execution_complete"].includes(event.type)).slice(-8).map(event => ({ type: event.type, hook: event.data.hookType, success: event.data.success, error: event.data.error?.message }));
  console.error(JSON.stringify({ phase, calls, recent }));
  throw error;
} finally {
  if (process.env.FM_COPILOT_LIVE_EVIDENCE) {
    const evidence = events().filter(event => ["session.start", "hook.start", "hook.end", "tool.execution_start", "tool.execution_complete"].includes(event.type)).map(event => ({
      type: event.type, timestamp: event.timestamp, version: event.data.copilotVersion,
      hook: event.data.hookType, success: event.data.success, error: event.data.error,
      tool: event.data.toolName, id: event.data.toolCallId, mode: event.data.arguments?.mode,
      result: event.type === "tool.execution_complete" ? event.data.result : undefined,
    }));
    try {
      writeFileSync(process.env.FM_COPILOT_LIVE_EVIDENCE, JSON.stringify({ phase, calls, events: evidence }, null, 2));
    } catch { console.error("optional diagnostic evidence could not be saved"); }
  }
  writeFileSync(join(lab, "release-management"), "release\n");
  writeFileSync(join(lab, "release-watch"), "release\n");
  await delay(1000);
  try {
    if (session && provisioned) {
      const cleanup = await labCall("teardown", session);
      assert.equal(cleanup.code, 0, cleanup.stderr);
    }
  } finally {
    server.closeAllConnections();
    server.close();
  }
}

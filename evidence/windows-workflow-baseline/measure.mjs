// Task-scoped timers around existing executable/extension interfaces.
// No vendor session is started; see run.sh and REPORT.md for each fixture boundary.
import assert from "node:assert/strict";
import cp from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { syncBuiltinESMExports } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const [family, code, out] = process.argv.slice(2);
assert.equal(process.platform, "win32", "This packet measures native Windows only");
const fixture = process.env.WF_FIXTURE_ROOT;
assert(!fs.existsSync(`${out}/samples.jsonl`), "Use a fresh OUTPUT_DIR for each run");
const assets = path.dirname(fileURLToPath(import.meta.url));
const traced = process.env.WF_TRACE === "1";
const warmups = traced ? 0 : Number(process.env.WF_WARMUPS ?? 3);
const samples = traced ? 1 : Number(process.env.WF_SAMPLES ?? 20);
assert(Number.isInteger(samples) && samples > 0);
assert(Number.isInteger(warmups) && warmups >= 0);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const native = value => value.startsWith("/")
  ? cp.execFileSync("cygpath", ["-m", value], { encoding: "utf8" }).trim() : value;
const read = file => fs.readFileSync(file, "utf8");
const maybeRead = file => fs.existsSync(file) ? read(file) : "";
const writeJSON = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
const hash = value => createHash("sha256").update(value).digest("hex");
const baseEnv = { ...process.env };
for (const key of Object.keys(baseEnv)) {
  if (/^(FM_|TASKS_AXI_|COPILOT_|HERDR_|CLAUDECODE$|PI_CODING_AGENT$|GROK_AGENT$|TMUX$|BASH_ENV$|SHELLOPTS$)/i.test(key)) delete baseEnv[key];
}
const inheritedPath = process.env.PATH;
for (const key of Object.keys(baseEnv)) if (key.toLowerCase() === "path") delete baseEnv[key];
baseEnv.PATH = inheritedPath;
Object.assign(baseEnv, { FM_BACKEND: "tmux", FM_GATE_REFUSE_BYPASS: "1", FM_LIVE: "0" });
const envFor = (home, extra = {}, fakebin) => ({
  ...baseEnv, FM_HOME: home, FM_ROOT_OVERRIDE: code,
  FM_STATE_OVERRIDE: `${home}/state`, FM_DATA_OVERRIDE: `${home}/data`,
  FM_CONFIG_OVERRIDE: `${home}/config`, FM_PROJECTS_OVERRIDE: `${home}/projects`,
  ...(fakebin ? { PATH: `${fakebin};${inheritedPath}` } : {}), ...extra,
});
const idleHome = `${fixture}/unused-home`;
const ps = `${process.env.SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe`;
const scenarios = [];
function command(id, file, args, env, verify, extra = {}) {
  const spec = { id, file, args, env, cwd: code, ...extra };
  scenarios.push({ ...spec, verify, run: () => execute(spec) });
}
function execute(spec) {
  return new Promise((resolve, reject) => {
    const child = cp.spawn(spec.file, spec.args, {
      cwd: spec.cwd, env: spec.env, windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "", stderr = "";
    child.stdout.setEncoding("utf8").on("data", chunk => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
    child.once("error", reject);
    child.once("close", (status, signal) => resolve({ status, signal, stdout, stderr, pid: child.pid }));
    child.stdin.on("error", error => { if (error.code !== "EPIPE") reject(error); });
    child.stdin.end(spec.input ?? "");
  });
}
const succeeded = result => assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`);
const silent = result => { succeeded(result); assert.equal(result.stdout.trim(), ""); };
command("control-bash", "bash", ["-c", ":"], envFor(idleHome), silent);
if (family === "copilot") command("control-powershell", ps,
  ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "exit 0"], envFor(idleHome), silent);

if (family === "reporting") {
  command("status-201", "bash", ["-c", '. "$1"; status_open_decisions "$2"', "_",
    `${code}/bin/fm-classify-lib.sh`, `${fixture}/routine.status`], envFor(idleHome), result => {
    succeeded(result);
    assert.equal(result.stdout.trim(), "choice\tneeds-decision\tchoose the release");
  });
  for (const shape of ["empty", "small"]) {
    const home = `${fixture}/${shape}`;
    command(`snapshot-${shape}`, "bash", [`${code}/bin/fm-fleet-snapshot.sh`, "--json"], envFor(home), result => {
      succeeded(result);
      const data = JSON.parse(result.stdout);
      assert.equal(data.schema, "fm-fleet-snapshot.v1");
      assert.equal(data.tasks.length, shape === "empty" ? 0 : 3);
      for (const task of data.tasks) {
        assert.equal(task.current_state.state, "unknown");
        assert.equal(task.hints.open_decisions[0].summary, 'preserve "quoted" notes');
        assert.equal(task.paths.worktree.present, false);
      }
    });
    command(`bearings-${shape}`, "bash", [`${code}/bin/fm-bearings-snapshot.sh`, "--json"], envFor(home), result => {
      succeeded(result);
      assert.equal(JSON.parse(result.stdout).schema, "fm-bearings.v1");
    });
  }
}

function seedDirectory(dir, name) {
  const seed = `${fixture}/seeds/${name}`;
  fs.mkdirSync(path.dirname(seed), { recursive: true });
  fs.cpSync(dir, seed, { recursive: true });
  return () => {
    fs.rmSync(dir, { recursive: true, force: true });
    fs.cpSync(seed, dir, { recursive: true });
  };
}
if (family === "startup") {
  const minimalPath = cp.execFileSync("cygpath", ["-wp", process.env.WF_STARTUP_BASE_PATH], { encoding: "utf8" }).trim();
  for (const line of read(`${fixture}/startup-worlds`).trim().split(/\r?\n/)) {
    const [name, rootP, homeP, fakeP] = line.split("|");
    const root = native(rootP), home = native(homeP), fakebin = native(fakeP);
    const harness = name.split("-")[0];
    const env = envFor(home, {
      FM_ROOT_OVERRIDE: root, FM_PROC_ROOT_OVERRIDE: `${home}/no-proc`,
      FM_FAKE_HARNESS: harness, FM_FAKE_HARNESS_PID: process.env.WF_FIXTURE_PARENT_PID,
      PATH: `${fakebin};${minimalPath}`,
      ...(harness === "pi" ? { PI_CODING_AGENT: "true", FM_PI_HARNESS: "pi" } : {}),
    });
    command(`startup-${name}`, "bash", [`${code}/bin/fm-session-start.sh`], env, result => {
      succeeded(result);
      assert(!/^.*STARTUP TRUNCATED.*$/m.test(result.stdout.replace(/^  - or a STARTUP TRUNCATED.*$/m, "")), "truncated startup is not a completed sample");
      assert(result.stdout.includes("lock acquired:"), "expected the fixture's owned startup path");
      assert(result.stdout.includes("data/backlog.md") && result.stdout.includes("data/learnings.md"));
      if (name.endsWith("small")) assert(result.stdout.includes("task-3.meta"));
    }, {
      prepare: seedDirectory(home, name),
      after: async round => {
        fs.mkdirSync(`${out}/stages`, { recursive: true });
        const timingFile = `${home}/state/.session-start.timings`;
        if (fs.existsSync(timingFile)) fs.copyFileSync(timingFile, `${out}/stages/${name}-${round}.tsv`);
        // Wait OUTSIDE the digest timer for the isolated deferred completion
        // records, then allow one second for tail cleanup; this is not a native
        // descendant-exit census.
        const started = performance.now();
        while (performance.now() - started < 150000) {
          const status = maybeRead(`${home}/state/.startup-network.status`);
          const summary = fs.existsSync(`${home}/state/home-summary.json`);
          if (/^state=(done|failed|timeout)$/m.test(status) && /^finished=[1-9]/m.test(status) && summary) {
            await delay(1000);
            return;
          }
          await delay(100);
        }
        throw new Error(`Isolated startup deferred work did not settle: ${maybeRead(`${home}/state/.startup-network.status`)}`);
      },
    });
  }
}

if (family === "copilot") {
  const payload = commandText => JSON.stringify({ tool_name: "powershell", tool_input: { command: commandText } });
  for (const [name, text] of [["allow", "printf fixture"], ["deny", "bin/fm-watch-arm.sh &"]]) {
    command(`copilot-command-${name}`, ps,
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", `${code}/bin/fm-ghcp-hook.ps1`, "pretool", "arm"],
      envFor(idleHome, { COPILOT_CLI: "1" }), result => {
        succeeded(result);
        if (name === "allow") assert.equal(result.stdout.trim(), "");
        else {
          const data = JSON.parse(result.stdout);
          assert.equal(data.permissionDecision, "deny");
          assert(data.permissionDecisionReason.includes("[watcher-background]"));
        }
      }, { input: payload(text) });
  }
  for (const state of ["healthy", "repair"]) {
    const home = `${fixture}/${state}`;
    command(state === "healthy" ? "copilot-stop-healthy" : "copilot-stop-repair-owner",
      state === "healthy" ? ps : "bash",
      state === "healthy"
        ? ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", `${home}/bin/fm-ghcp-hook.ps1`, "primary-stop"]
        : [`${home}/bin/fm-ghcp-hook.sh`, "primary-stop"],
      envFor(home, { FM_ROOT_OVERRIDE: home, COPILOT_CLI: "1", COPILOT_LOADER_PID: "876543",
        COPILOT_AGENT_SESSION_ID: "sess-copilot", FM_FAKE_COPILOT_HEALTHY: state === "healthy" ? "1" : "0" }, `${home}/fakebin`),
      result => {
        succeeded(result);
        if (state === "healthy") assert.equal(result.stdout.trim(), "");
        else {
          assert.equal(JSON.parse(result.stdout).decision, "block");
          assert.match(read(`${home}/state/.turnend-copilot-continuations`), /^count=1$/m);
        }
        assert(!fs.existsSync(`${home}/state/arm-ran`));
      }, { input: '{"sessionId":"sess-copilot","stop_hook_active":false}' });
  }
}

if (family === "pi") {
  const home = `${fixture}/pi`;
  const env = envFor(home);
  for (const key of Object.keys(process.env)) {
    if (/^(FM_|TASKS_AXI_|COPILOT_|HERDR_|CLAUDECODE$|PI_CODING_AGENT$|GROK_AGENT$|TMUX$)/i.test(key)) delete process.env[key];
  }
  Object.assign(process.env, env);
  // Forward real execFile calls unchanged; retain the ChildProcess solely to
  // await progress's helper exit (the event callback itself is fire-and-forget).
  const realExecFile = cp.execFile;
  let lastChild;
  cp.execFile = (...args) => { lastChild = realExecFile(...args); return lastChild; };
  syncBuiltinESMExports();
  const handlers = {};
  (await import(pathToFileURL(`${home}/generated.ts`).href)).default({
    on: (name, handler) => { handlers[name] = handler; },
    events: { on: (name, handler) => { handlers[name] = handler; } },
  });
  const primary = {};
  (await import(pathToFileURL(`${code}/.pi/extensions/fm-primary-turnend-guard.ts`).href)).default({
    on: (name, handler) => { primary[name] = handler; }, sendMessage() {},
  });
  const waitChild = child => new Promise((resolve, reject) => {
    if (child.exitCode !== null) { child.exitCode === 0 ? resolve() : reject(new Error(`helper exit ${child.exitCode}`)); return; }
    child.once("error", reject);
    child.once("close", status => status === 0 ? resolve() : reject(new Error(`helper exit ${status}`)));
  });
  let priorSeq;
  for (const [id, handler, state] of [["pi-busy", "agent_start", "busy"], ["pi-idle", "agent_settled", "idle"]]) {
    scenarios.push({ id, boundary: `generated artifact ${handler} -> real Bash helper close`, env,
      prepare: () => { priorSeq = Number(read(`${home}/state/task.busy-state`).match(/\bseq=(\d+)/)[1]); },
      run: async () => { await handlers[handler]({}, { isIdle: () => true }); await waitChild(lastChild); return { status: 0, stdout: "", stderr: "" }; },
      verify: () => {
        const record = read(`${home}/state/task.busy-state`);
        assert(record.includes(`state=${state} source=pi-ext`));
        assert.equal(Number(record.match(/\bseq=(\d+)/)[1]), priorSeq + 1);
      },
    });
  }
  let progressAt = 0;
  scenarios.push({ id: "pi-progress", boundary: "generated progress callback -> real Bash helper close", env,
    prepare: async () => {
      await delay(Math.max(0, 1100 - (Date.now() - progressAt)));
      fs.rmSync(`${home}/state/task.progress`, { force: true });
    },
    run: async () => {
      progressAt = Date.now();
      handlers["codex-native:progress"]();
      await waitChild(lastChild);
      return { status: 0, stdout: "", stderr: "" };
    },
    verify: () => assert(fs.existsSync(`${home}/state/task.progress`)),
  });
  for (const [kind, text] of [["allow", "printf fixture"], ["deny", "bin/fm-watch-arm.sh &"]]) {
    scenarios.push({ id: `pi-tool-${kind}`, boundary: "real primary extension tool_call -> policy result", env,
      run: async () => ({ status: 0, stdout: JSON.stringify(await primary.tool_call({
        type: "tool_call", toolName: "bash", input: { command: text },
      })), stderr: "" }),
      verify: result => {
        const data = JSON.parse(result.stdout);
        if (kind === "allow") assert.deepEqual(data, {});
        else { assert.equal(data.block, true); assert(data.reason.includes("watcher-background")); }
      },
    });
  }
}

if (family === "relaunch") {
  for (const line of read(`${fixture}/relaunch-worlds`).trim().split(/\r?\n/)) {
    const [harness, id, dirP] = line.split("|");
    const dir = native(dirP), home = `${dir}/home`;
    const resetHome = seedDirectory(home, `${harness}-home`);
    const resetFake = seedDirectory(`${dir}/fake`, `${harness}-fake`);
    const tasktmp = native(`/tmp/fm-${id}`);
    command(`relaunch-${harness}`, "bash", [`${code}/bin/fm-control.sh`, id, "relaunch", "--note", "continue the isolated fixture"],
      envFor(home, {
        HOME: `${dir}/user-home`, USERPROFILE: `${dir}/user-home`, CLAUDE_CONFIG_DIR: "",
        FM_FAKE_DIR: `${dir}/fake`, FM_SPAWN_NO_GUARD: "1", GROK_HOME: `${dir}/grokhome`,
        FM_CONTROL_POLL: "0.01", FM_CONTROL_EXIT_WAIT: "0.05", FM_CONTROL_LAUNCH_WAIT: "0.05",
      }, `${dir}/fakebin`), result => {
        succeeded(result);
        assert(result.stdout.includes(`relaunched ${id} harness=${harness}`));
        assert.match(read(`${home}/state/${id}.control-relaunch`), /^phase=complete$/m);
        assert(read(`${dir}/fake/literal`).includes("encode launch-brief"));
        const wiring = harness === "pi" ? `${home}/state/${id}.pi-ext.ts` : `${dir}/wt/.github/hooks/zz-firstmate-${id}.json`;
        assert(fs.existsSync(wiring));
      }, { prepare: () => {
        resetHome(); resetFake();
        fs.rmSync(tasktmp, { recursive: true, force: true });
        fs.rmSync(`${dir}/wt/.github/hooks/zz-firstmate-${id}.json`, { force: true });
      } });
  }
}

const selected = scenarios.filter(s => !process.env.WF_ONLY || process.env.WF_ONLY.split(",").includes(s.id));
assert(selected.length, "No selected scenario");
fs.mkdirSync(`${out}/outputs`, { recursive: true });
const sha = cp.execFileSync("git", ["-C", code, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
cp.execFileSync("git", ["-C", code, "diff", "--quiet", "HEAD"], { stdio: "pipe" });
const manifest = selected.map(s => ({ id: s.id, file: s.file, args: s.args, boundary: s.boundary, cwd: s.cwd,
  input: s.input, env: Object.fromEntries(Object.entries(s.env).filter(([key]) => /^(FM_|COPILOT_|PI_CODING_AGENT$|HOME$|USERPROFILE$|GROK_HOME$|CLAUDE_CONFIG_DIR$)/.test(key))),
  pathEntries: s.env.PATH.split(";").length, pathSHA256: hash(s.env.PATH),
}));
const cpu = () => os.cpus().reduce((sum, c) => ({ idle: sum.idle + c.times.idle,
  total: sum.total + Object.values(c.times).reduce((a, b) => a + b, 0) }), { idle: 0, total: 0 });
const busy = (before, after) => after.total === before.total ? null : 100 * (1 - (after.idle - before.idle) / (after.total - before.total));
const rows = [];
const metadata = { family, codeSHA: sha, codeRoot: code, fixture, traced, samples, warmups,
  started: new Date().toISOString(), node: process.version, platform: process.platform, release: os.release(),
  arch: process.arch, cpus: os.cpus().length, cpuModel: os.cpus()[0].model, totalMem: os.totalmem(),
  freeMem: os.freemem(), bashResolution: cp.execFileSync("where.exe", ["bash"], { encoding: "utf8" }).trim().split(/\r?\n/),
  manifest,
};
writeJSON(`${out}/manifest.json`, metadata);
const totalCpuStart = cpu();
try {
  for (let round = -warmups; round < samples; round++) {
    const offset = (round + warmups) % selected.length;
    const order = [...selected.slice(offset), ...selected.slice(0, offset)];
    for (const scenario of order) {
      await scenario.prepare?.();
      if (traced) {
        fs.mkdirSync(`${out}/traces`, { recursive: true });
        const log = `${out}/traces/${scenario.id}.log`;
        fs.writeFileSync(log, "");
        scenario.env.BASH_ENV = `${assets}/trace-hook.sh`;
        scenario.env.WF_TRACE_LOG = log;
        if (family === "pi") { process.env.BASH_ENV = scenario.env.BASH_ENV; process.env.WF_TRACE_LOG = log; }
      }
      const beforeCpu = cpu();
      const startedAt = new Date().toISOString();
      const started = performance.now();
      const result = await scenario.run();
      const ms = performance.now() - started;
      const afterCpu = cpu();
      const row = { scenario: scenario.id, round, warmup: round < 0, traced, startedAt, ms,
        cpuBusyPercent: busy(beforeCpu, afterCpu), status: result.status, signal: result.signal,
        stdoutBytes: Buffer.byteLength(result.stdout), stdoutSHA256: hash(result.stdout), pid: result.pid };
      rows.push(row);
      fs.appendFileSync(`${out}/samples.jsonl`, JSON.stringify(row) + "\n");
      fs.writeFileSync(`${out}/outputs/${scenario.id}.stdout.txt`, result.stdout);
      fs.writeFileSync(`${out}/outputs/${scenario.id}.stderr.txt`, result.stderr);
      // Verification and state resets are deliberately outside the latency interval.
      try { scenario.verify?.(result); }
      finally { await scenario.after?.(round); }
      console.log(`${scenario.id} ${round < 0 ? "warmup" : `sample ${round + 1}`} ${ms.toFixed(1)} ms`);
    }
  }
  const quantile = (values, q) => [...values].sort((a, b) => a - b)[Math.max(0, Math.ceil(values.length * q) - 1)];
  const median = values => {
    const sorted = [...values].sort((a, b) => a - b);
    return (sorted[Math.floor((sorted.length - 1) / 2)] + sorted[Math.floor(sorted.length / 2)]) / 2;
  };
  const summary = selected.map(s => {
    const measured = rows.filter(r => r.scenario === s.id && !r.warmup);
    const values = measured.map(r => r.ms);
    const half = Math.floor(values.length / 2);
    return { scenario: s.id, n: values.length, medianMs: median(values),
      p95Ms: quantile(values, 0.95), maxMs: Math.max(...values),
      firstHalfMedianMs: median(values.slice(0, half || 1)),
      secondHalfMedianMs: median(values.slice(half)),
      meanCpuBusyPercent: measured.reduce((sum, r) => sum + r.cpuBusyPercent, 0) / measured.length };
  });
  writeJSON(`${out}/summary.json`, { ...metadata, finished: new Date().toISOString(),
    meanHostCpuBusyPercent: busy(totalCpuStart, cpu()), summary });
} catch (error) {
  writeJSON(`${out}/failure.json`, { message: String(error), stack: error.stack, rows });
  throw error;
}

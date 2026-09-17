// Task-scoped paired orchestration of the baseline packet's Pi boundaries,
// adding native generated Copilot worker commands, not primary Stop or repair.
// Derived from 82fe66d0's measure.mjs and the metadata attempt's paired loop.
import assert from "node:assert/strict";
import cp from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { syncBuiltinESMExports } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const [base, candidate, out] = process.argv.slice(2);
assert.equal(process.platform, "win32", "Native Windows is required");
const fixture = process.env.WF_FIXTURE_ROOT;
assert(fixture && base && candidate && out);
assert.equal(path.dirname(base), path.dirname(candidate), "Use sibling code copies");
assert.equal(base.length, candidate.length, "Use equal-length source paths");
assert(!fs.existsSync(`${out}/samples.jsonl`), "Use a fresh output directory");
const assets = path.dirname(fileURLToPath(import.meta.url));
const traced = process.env.WF_TRACE === "1";
const warmups = traced ? 0 : Number(process.env.WF_WARMUPS ?? 3);
const samples = traced ? 1 : Number(process.env.WF_SAMPLES ?? 20);
assert(Number.isInteger(warmups) && warmups >= 0);
assert(Number.isInteger(samples) && samples > 0);
const hash = value => createHash("sha256").update(value).digest("hex");
const read = file => fs.readFileSync(file, "utf8");
const writeJSON = (name, value) => fs.writeFileSync(`${out}/${name}`, JSON.stringify(value, null, 2) + "\n");
const git = (root, ...args) => cp.execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trim();
const pins = Object.fromEntries(Object.entries({ base, candidate }).map(([version, root]) => {
  git(root, "diff", "--quiet", "HEAD");
  return [version, { root, sha: git(root, "rev-parse", "HEAD") }];
}));
const fileNames = ["run.sh", "measure.mjs", "trace-hook.sh"];
git(assets, "ls-files", "--error-unmatch", "--", ...fileNames);
git(assets, "diff", "--quiet", "HEAD", "--", ".");
const driverSHA = git(assets, "rev-parse", "HEAD");
const driverFiles = Object.fromEntries(fileNames.map(name => [name, hash(read(`${assets}/${name}`))]));
const baseEnv = { ...process.env };
const cleanKey = key => /^(FM_|TASKS_AXI_|COPILOT_|HERDR_|CLAUDECODE$|PI_CODING_AGENT$|GROK_AGENT$|TMUX$|BASH_ENV$|SHELLOPTS$)/i.test(key);
for (const key of Object.keys(baseEnv)) if (cleanKey(key)) delete baseEnv[key];
const inheritedPath = process.env.PATH;
for (const key of Object.keys(baseEnv)) if (key.toLowerCase() === "path") delete baseEnv[key];
baseEnv.PATH = inheritedPath;
Object.assign(baseEnv, { FM_BACKEND: "tmux", FM_GATE_REFUSE_BYPASS: "1", FM_LIVE: "0" });
const envFor = (home, code, extra = {}) => ({
  ...baseEnv, FM_HOME: home, FM_ROOT_OVERRIDE: code,
  FM_STATE_OVERRIDE: `${home}/state`, FM_DATA_OVERRIDE: `${home}/data`,
  FM_CONFIG_OVERRIDE: `${home}/config`, FM_PROJECTS_OVERRIDE: `${home}/projects`, ...extra,
});
const ps = `${process.env.SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe`;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function observeChild(child) {
  let stdout = "", stderr = "";
  return new Promise(resolve => {
    child.stdout?.setEncoding("utf8").on("data", chunk => { stdout += chunk; });
    child.stderr?.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
    child.once("error", error => resolve({ status: null, signal: null, stdout, stderr: stderr + String(error), pid: child.pid }));
    child.once("close", (status, signal) => resolve({ status, signal, stdout, stderr, pid: child.pid }));
  });
}
function execute(spec) {
  const child = cp.spawn(spec.file, spec.args, {
    cwd: spec.cwd, env: spec.env, windowsHide: true, stdio: ["pipe", "pipe", "pipe"],
  });
  const done = observeChild(child);
  child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
  child.stdin.end(spec.input ?? "");
  return done;
}
const silent = result => {
  assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`);
  assert.equal(result.signal, null);
  assert.equal(result.stdout, "");
  assert.equal(result.stderr, "");
};

// Forward the real execFile call, arguments, callback, and ChildProcess unchanged.
// As in the baseline, retain completion to await the fire-and-forget progress
// helper, never to advertise it as synchronous callback blocking.
const realExecFile = cp.execFile;
let lastCall;
cp.execFile = (...args) => {
  const child = realExecFile(...args);
  lastCall = { child, done: observeChild(child) };
  return child;
};
syncBuiltinESMExports();
const handlers = {};
for (const version of Object.keys(pins)) {
  handlers[version] = {};
  const register = (name, handler) => { handlers[version][name] = handler; };
  (await import(pathToFileURL(`${fixture}/pi/${version}.ts`).href)).default({ on: register, events: { on: register } });
}
const homes = Object.fromEntries(["pi", "copilot"].map(harness => [harness, `${fixture}/${harness}`]));
const seeds = Object.fromEntries(Object.entries(homes).map(([harness, home]) => [harness, {
  "task.busy-gen": read(`${home}/state/task.busy-gen`),
  "task.busy-state": read(`${home}/state/task.busy-state`),
}]));
function resetState(harness) {
  const state = `${homes[harness]}/state`;
  fs.rmSync(state, { recursive: true, force: true });
  fs.mkdirSync(state, { mode: 0o700 });
  for (const [name, content] of Object.entries(seeds[harness])) fs.writeFileSync(`${state}/${name}`, content, { mode: 0o600 });
}
function captureState(harness) {
  const state = `${homes[harness]}/state`;
  return Object.fromEntries(fs.readdirSync(state).sort().map(name => {
    const file = `${state}/${name}`, stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink()) return [name, { kind: stat.isDirectory() ? "directory" : "unexpected" }];
    const bytes = fs.readFileSync(file);
    return [name, { kind: "file", bytes: bytes.length, sha256: hash(bytes), text: bytes.toString("utf8") }];
  }));
}
function verifyState(scenario, actual) {
  const harness = scenario.harness;
  const expectedNames = ["task.busy-gen", "task.busy-state"];
  if (scenario.id === "pi-progress") expectedNames.push("task.progress");
  if (scenario.id === "copilot-busy") expectedNames.push("task.copilot-prompt-submitted");
  if (scenario.id === "copilot-idle") expectedNames.push("task.turn-ended");
  assert.deepEqual(Object.keys(actual).sort(), expectedNames.sort(), "Unexpected or missing lifecycle artifact");
  assert(Object.values(actual).every(entry => entry.kind === "file"));
  assert.equal(actual["task.busy-gen"].text, seeds[harness]["task.busy-gen"], "Event changed its generation");
  if (scenario.id === "pi-progress") {
    assert.equal(actual["task.busy-state"].text, seeds.pi["task.busy-state"], "Progress changed semantic state");
    assert.equal(actual["task.progress"].bytes, 0);
    return;
  }
  const generation = seeds[harness]["task.busy-gen"].trim();
  const match = actual["task.busy-state"].text.match(/^v1 gen=([^ ]+) seq=([0-9]+) state=([^ ]+) source=([^ ]+) event=([^ ]+) ts=([0-9]+)\n$/);
  assert(match, "Incomplete or malformed busy record");
  assert.deepEqual(match.slice(1, 6), [generation, "2", scenario.state, scenario.source, scenario.event]);
  assert(Number(match[6]) > 0);
  if (scenario.id === "copilot-busy") {
    const ack = actual["task.copilot-prompt-submitted"].text;
    assert(ack.startsWith(`${generation}:`), "Submission acknowledgement lost generation binding");
    assert.match(ack.slice(generation.length), /^:[0-9]+:[0-9]+\n$/);
  }
  if (scenario.id === "copilot-idle") assert.equal(actual["task.turn-ended"].bytes, 0);
}
const scenarios = [
  { id: "control-bash", control: true, file: "bash", args: () => ["-c", ":"] },
  { id: "pi-busy", harness: "pi", primary: true, handler: "agent_start", state: "busy", source: "pi-ext", event: "agent-start" },
  { id: "control-powershell", control: true, file: ps, args: () => ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "exit 0"] },
  { id: "copilot-busy", harness: "copilot", primary: true, state: "busy", source: "copilot-hook", event: "user-prompt-submitted", hook: "userPromptSubmitted" },
  { id: "pi-idle", harness: "pi", primary: true, handler: "agent_settled", state: "idle", source: "pi-ext", event: "agent-settled" },
  { id: "copilot-idle", harness: "copilot", primary: true, state: "idle", source: "copilot-hook", event: "agent-stop", hook: "agentStop" },
  { id: "pi-progress", harness: "pi", primary: false, handler: "codex-native:progress" },
];
const only = process.env.WF_ONLY?.split(",");
if (only) assert(only.every(id => scenarios.some(s => s.id === id)), "Unknown smoke scenario");
const selected = scenarios.filter(s => !only || only.includes(s.id));
assert(selected.length);
const manifest = selected.flatMap(s => Object.entries(pins).map(([version, pin]) => {
  const home = s.harness ? homes[s.harness] : `${fixture}/unused-home`;
  const spec = { id: s.id, version, cwd: pin.root, env: envFor(home, pin.root, s.harness === "copilot" ? { COPILOT_CLI: "1" } : {}) };
  if (s.control) Object.assign(spec, { file: s.file, args: s.args() });
  if (s.harness === "copilot") {
    const hook = JSON.parse(read(`${home}/${version}.json`)).hooks[s.hook][0];
    assert.equal(hook.type, "command");
    assert.equal(hook.timeoutSec, 10, "Do not change the generated vendor hook bound");
    Object.assign(spec, { file: ps, args: ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", `${hook.powershell}; exit $LASTEXITCODE`],
      boundary: "native generated PowerShell worker command -> hook owner -> busy writer close", input: "{}", vendorTimeoutSec: hook.timeoutSec });
  }
  if (s.harness === "pi") spec.boundary = s.id === "pi-progress"
    ? "generated progress callback -> real Bash helper close; NOT synchronous callback blocking"
    : `generated ${s.handler} callback -> real Bash helper close`;
  return spec;
}));
const toolVersion = (file, args) => cp.execFileSync(file, args, { encoding: "utf8", env: baseEnv }).trim();
const cpu = () => os.cpus().reduce((sum, c) => ({ idle: sum.idle + c.times.idle,
  total: sum.total + Object.values(c.times).reduce((a, b) => a + b, 0) }), { idle: 0, total: 0 });
const busy = (before, after) => after.total === before.total ? null : 100 * (1 - (after.idle - before.idle) / (after.total - before.total));
const metadata = {
  pins, driverSHA, driverFiles, traced, samples, warmups,
  purpose: traced ? "partial-attribution" : samples === 20 && warmups === 3 && selected.length === 7 ? "qualification-batch" : "smoke",
  fixture, seeds, started: new Date().toISOString(), platform: process.platform, release: os.release(),
  arch: process.arch, cpus: os.cpus().length, cpuModel: os.cpus()[0].model, totalMem: os.totalmem(), freeMem: os.freemem(),
  tools: { node: process.version, git: toolVersion("git", ["--version"]), bash: toolVersion("bash", ["--version"]),
    powershell: toolVersion(ps, ["-NoProfile", "-NonInteractive", "-Command", "$PSVersionTable.PSVersion.ToString()"]),
    jq: toolVersion("jq", ["--version"]), perl: toolVersion("perl", ["-e", "print $^V"]), cygpath: toolVersion("cygpath", ["--version"]) },
  bashResolution: toolVersion("where.exe", ["bash"]).split(/\r?\n/),
  hookBashResolution: toolVersion(ps, ["-NoProfile", "-NonInteractive", "-Command", `. '${base.replaceAll("'", "''")}/bin/fm-windows-git-bash.ps1'; Resolve-FirstmateGitBash`]),
  pathEntries: inheritedPath.split(";").length, pathSHA256: hash(inheritedPath),
  generated: Object.fromEntries(["pi/base.ts", "pi/candidate.ts", "copilot/base.json", "copilot/candidate.json"].map(name => [name, hash(read(`${fixture}/${name}`))])),
  manifest: manifest.map(s => ({ ...s, env: Object.fromEntries(Object.entries(s.env).filter(([key]) => /^(FM_|COPILOT_|HOME$|USERPROFILE$)/.test(key))) })),
};
writeJSON("manifest.json", metadata);
fs.mkdirSync(`${out}/outputs`, { recursive: true });
if (traced) fs.mkdirSync(`${out}/traces`, { recursive: true });
const rows = [], totalCpuStart = cpu(), progressAt = { base: 0, candidate: 0 };
let stage;
try {
  for (let round = -warmups; round < samples; round++) {
    const offset = (round + warmups) % selected.length;
    const order = [...selected.slice(offset), ...selected.slice(0, offset)];
    // Each scenario alternates first version on successive paired rounds.
    const versions = (round + warmups) % 2 === 0 ? ["base", "candidate"] : ["candidate", "base"];
    for (const scenario of order) {
      for (const version of versions) {
        const spec = manifest.find(s => s.id === scenario.id && s.version === version);
        stage = { scenario: scenario.id, version, round, phase: "prepare" };
        if (scenario.harness) resetState(scenario.harness);
        if (scenario.id === "pi-progress") await delay(Math.max(0, 1100 - (Date.now() - progressAt[version])));
        if (traced) {
          spec.env.BASH_ENV = `${assets}/trace-hook.sh`;
          spec.env.WF_TRACE_LOG = `${out}/traces/${scenario.id}-${version}.log`;
        }
        for (const key of Object.keys(process.env)) if (cleanKey(key) || key === "WF_TRACE_LOG") delete process.env[key];
        Object.assign(process.env, spec.env);
        process.chdir(spec.cwd);
        lastCall = undefined;
        stage.phase = "operation";
        const beforeCpu = cpu(), startedAt = new Date().toISOString(), started = performance.now();
        let result;
        try {
          if (scenario.harness === "pi") {
            if (scenario.id === "pi-progress") {
              progressAt[version] = Date.now();
              handlers[version][scenario.handler]();
            } else await handlers[version][scenario.handler]({}, { isIdle: () => true });
            assert(lastCall, "Generated callback did not launch its helper");
            result = await lastCall.done;
          } else result = await execute(spec);
        } catch (error) { result = { status: null, signal: null, stdout: "", stderr: String(error) }; }
        const ms = performance.now() - started, afterCpu = cpu();
        stage.phase = "verify";
        const outputName = `${scenario.id}-${version}-${round}`;
        fs.writeFileSync(`${out}/outputs/${outputName}.stdout.txt`, result.stdout);
        fs.writeFileSync(`${out}/outputs/${outputName}.stderr.txt`, result.stderr);
        let error;
        try {
          const actual = scenario.harness ? captureState(scenario.harness) : {};
          writeJSON(`outputs/${outputName}.state.json`, actual);
          silent(result);
          if (scenario.harness) verifyState(scenario, actual);
        } catch (failure) { error = failure; }
        const row = { scenario: scenario.id, version, round, warmup: round < 0, traced, startedAt, ms,
          cpuBusyPercent: busy(beforeCpu, afterCpu), status: result.status, signal: result.signal, pid: result.pid,
          stdoutBytes: Buffer.byteLength(result.stdout), stdoutSHA256: hash(result.stdout), stderrBytes: Buffer.byteLength(result.stderr),
          outputName, verified: !error, error: error ? String(error) : undefined };
        rows.push(row);
        fs.appendFileSync(`${out}/samples.jsonl`, JSON.stringify(row) + "\n");
        if (error) throw error;
        console.log(`${scenario.id} ${version} ${round < 0 ? "warmup" : `sample ${round + 1}`} ${ms.toFixed(1)} ms`);
      }
    }
  }
  for (const pin of Object.values(pins)) {
    assert.equal(git(pin.root, "rev-parse", "HEAD"), pin.sha);
    git(pin.root, "diff", "--quiet", "HEAD");
  }
  assert.equal(git(assets, "rev-parse", "HEAD"), driverSHA);
  for (const [name, digest] of Object.entries(driverFiles)) assert.equal(hash(read(`${assets}/${name}`)), digest);
  const quantile = (values, q) => [...values].sort((a, b) => a - b)[Math.max(0, Math.ceil(values.length * q) - 1)];
  const median = values => {
    const sorted = [...values].sort((a, b) => a - b);
    return (sorted[Math.floor((sorted.length - 1) / 2)] + sorted[Math.floor(sorted.length / 2)]) / 2;
  };
  const summary = selected.map(s => {
    const stats = Object.fromEntries(["base", "candidate"].map(version => {
      const measured = rows.filter(row => row.scenario === s.id && row.version === version && !row.warmup);
      const values = measured.map(row => row.ms), half = Math.floor(values.length / 2);
      return [version, { n: values.length, medianMs: median(values), p95Ms: quantile(values, 0.95), maxMs: Math.max(...values),
        firstHalfMedianMs: median(values.slice(0, half || 1)), secondHalfMedianMs: median(values.slice(half)),
        meanCpuBusyPercent: measured.reduce((sum, row) => sum + row.cpuBusyPercent, 0) / measured.length }];
    }));
    const pairs = Array.from({ length: samples }, (_, round) => Object.fromEntries(rows.filter(row => row.scenario === s.id && row.round === round).map(row => [row.version, row.ms])));
    const fasterPairs = pairs.filter(pair => pair.candidate < pair.base).length;
    const medianReductionMs = stats.base.medianMs - stats.candidate.medianMs;
    const medianReductionPercent = 100 * medianReductionMs / stats.base.medianMs;
    const p95NonIncreasing = stats.candidate.p95Ms <= stats.base.p95Ms;
    return { scenario: s.id, primary: !!s.primary, control: !!s.control, ...stats, fasterPairs, medianReductionMs, medianReductionPercent, p95NonIncreasing,
      accepted: metadata.purpose === "qualification-batch" && !s.control && p95NonIncreasing &&
        (!s.primary || (medianReductionMs >= 100 && medianReductionPercent >= 10 && fasterPairs >= 15)) };
  });
  writeJSON("summary.json", { ...metadata, finished: new Date().toISOString(), meanHostCpuBusyPercent: busy(totalCpuStart, cpu()), summary,
    accepted: metadata.purpose === "qualification-batch" && summary.filter(s => !s.control).every(s => s.accepted) });
} catch (error) {
  writeJSON("failure.json", { message: String(error), stack: error.stack, stage, rows });
  throw error;
}

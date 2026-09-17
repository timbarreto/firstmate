// Paired orchestration of the baseline packet's reporting entrypoints/timers.
// Derived from windows-workflow-baseline/measure.mjs at 82fe66d0f349e520c8bd91617e49934f0b7bb1bb.
// This is task evidence, not a production benchmark framework or live fleet.
import assert from "node:assert/strict";
import cp from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const [base, candidate, out] = process.argv.slice(2);
assert.equal(process.platform, "win32", "Native Windows is required");
const fixture = process.env.WF_FIXTURE_ROOT;
assert(fixture && base && candidate && out);
assert.equal(path.dirname(base), path.dirname(candidate), "Use sibling code copies for comparable source paths");
assert.equal(base.length, candidate.length, "Use equal-length code-root paths");
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
git(assets, "diff", "--quiet", "HEAD", "--", ".");
const driverSHA = git(assets, "rev-parse", "HEAD");
const driverFiles = Object.fromEntries(["run.sh", "measure.mjs", "trace-hook.sh"].map(name => [name, hash(read(`${assets}/${name}`))]));
const baseEnv = { ...process.env };
for (const key of Object.keys(baseEnv)) {
  if (/^(FM_|TASKS_AXI_|COPILOT_|HERDR_|CLAUDECODE$|PI_CODING_AGENT$|GROK_AGENT$|TMUX$|BASH_ENV$|SHELLOPTS$)/i.test(key)) delete baseEnv[key];
}
const inheritedPath = process.env.PATH;
for (const key of Object.keys(baseEnv)) if (key.toLowerCase() === "path") delete baseEnv[key];
baseEnv.PATH = inheritedPath;
Object.assign(baseEnv, { FM_BACKEND: "tmux", FM_GATE_REFUSE_BYPASS: "1", FM_LIVE: "0" });
const envFor = (home, code) => ({
  ...baseEnv, FM_HOME: home, FM_ROOT_OVERRIDE: code,
  FM_STATE_OVERRIDE: `${home}/state`, FM_DATA_OVERRIDE: `${home}/data`,
  FM_CONFIG_OVERRIDE: `${home}/config`, FM_PROJECTS_OVERRIDE: `${home}/projects`,
});
function execute(spec) {
  return new Promise((resolve, reject) => {
    const child = cp.spawn(spec.file, spec.args, {
      cwd: spec.cwd, env: spec.env, windowsHide: true, stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "", stderr = "";
    child.stdout.setEncoding("utf8").on("data", chunk => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
    child.once("error", reject);
    child.once("close", (status, signal) => resolve({ status, signal, stdout, stderr, pid: child.pid }));
    child.stdin.on("error", error => { if (error.code !== "EPIPE") reject(error); });
    child.stdin.end();
  });
}
const succeeded = result => {
  assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`);
  assert.equal(result.signal, null);
  assert.equal(result.stderr, "");
};
const idsFor = shape => shape === "small" ? ["task-1", "task-2", "task-3"] : [];
const scenarios = [{
  id: "control-bash", shape: "unused-home", file: "bash", args: () => ["-c", ":"],
  verify: result => { succeeded(result); assert.equal(result.stdout, ""); },
}];
for (const shape of ["empty", "small"]) {
  scenarios.push({
    id: `snapshot-${shape}`, shape, file: "bash", args: code => [`${code}/bin/fm-fleet-snapshot.sh`, "--json"],
    verify: result => {
      succeeded(result);
      const data = JSON.parse(result.stdout);
      assert.equal(data.schema, "fm-fleet-snapshot.v1");
      assert.deepEqual(data.tasks.map(task => task.id), idsFor(shape));
      assert.deepEqual(data.tasks.map(task => task.harness), shape === "small" ? ["copilot", "pi", "copilot"] : []);
      for (const task of data.tasks) {
        assert.equal(task.project, 'literal="data"');
        assert.equal(task.current_state.state, "unknown");
        assert.equal(task.current_state.detail, "worktree gone (torn down?)");
        assert.equal(task.backend, "tmux");
        assert.equal(task.endpoint.target, null);
        assert.equal(task.hints.open_decisions.length, 1);
        assert.equal(task.hints.open_decisions[0].summary, 'preserve "quoted" notes');
        assert.equal(task.paths.worktree.present, false);
      }
    },
  });
  scenarios.push({
    id: `bearings-${shape}`, shape, file: "bash", args: code => [`${code}/bin/fm-bearings-snapshot.sh`, "--json"],
    verify: result => {
      succeeded(result);
      const data = JSON.parse(result.stdout);
      assert.equal(data.schema, "fm-bearings.v1");
      assert.deepEqual(data.in_flight.map(task => task.id), idsFor(shape));
      for (const task of data.in_flight) {
        assert.equal(task.state, "unknown");
        assert.equal(task.doing, "worktree gone (torn down?)");
        assert.equal(task.repo, 'literal="data"');
      }
      assert.deepEqual(data.recorded_prs, idsFor(shape).map((id, index) => ({ id, url: `https://github.com/example/repo/pull/${index + 1}` })));
    },
  });
}
const only = process.env.WF_ONLY?.split(",");
if (only) assert(only.every(id => scenarios.some(s => s.id === id)), "Unknown smoke scenario");
const selected = scenarios.filter(s => !only || only.includes(s.id));
assert(selected.length);
const manifest = selected.flatMap(s => Object.entries(pins).map(([version, pin]) => ({
  id: s.id, version, file: s.file, args: s.args(pin.root), cwd: pin.root,
  env: envFor(`${fixture}/${s.shape}`, pin.root),
})));
// These reports share byte-identical read-only input paths. Refuse any mutation
// before handing the same fixture to the other version; do not reset away drift.
function captureInputs() {
  const entries = [];
  function walk(dir) {
    for (const name of fs.readdirSync(dir).sort()) {
      const file = `${dir}/${name}`, stat = fs.lstatSync(file);
      const relative = path.relative(fixture, file).replaceAll("\\", "/");
      if (stat.isDirectory()) { entries.push({ path: relative, directory: true }); walk(file); }
      else {
        assert(stat.isFile() && !stat.isSymbolicLink(), `Unexpected fixture entry: ${relative}`);
        entries.push({ path: relative, bytes: stat.size, sha256: hash(fs.readFileSync(file)) });
      }
    }
  }
  for (const shape of ["empty", "small"]) walk(`${fixture}/${shape}`);
  return entries;
}
const inputs = captureInputs();
const toolVersion = (file, args) => cp.execFileSync(file, args, { encoding: "utf8", env: baseEnv }).trim();
const cpu = () => os.cpus().reduce((sum, c) => ({ idle: sum.idle + c.times.idle,
  total: sum.total + Object.values(c.times).reduce((a, b) => a + b, 0) }), { idle: 0, total: 0 });
const busy = (before, after) => after.total === before.total ? null : 100 * (1 - (after.idle - before.idle) / (after.total - before.total));
const metadata = {
  pins, driverSHA, driverFiles, traced, samples, warmups,
  purpose: traced ? "partial-attribution" : samples === 20 && warmups === 3 && selected.length === 5 ? "qualification-batch" : "smoke",
  fixture, inputs, started: new Date().toISOString(), platform: process.platform, release: os.release(),
  arch: process.arch, cpus: os.cpus().length, cpuModel: os.cpus()[0].model,
  totalMem: os.totalmem(), freeMem: os.freemem(),
  tools: { node: process.version, git: toolVersion("git", ["--version"]), bash: toolVersion("bash", ["--version"]),
    jq: toolVersion("jq", ["--version"]), awk: toolVersion("awk", ["--version"]),
    perl: toolVersion("perl", ["-e", "print $^V"]), cygpath: toolVersion("cygpath", ["--version"]) },
  bashResolution: toolVersion("where.exe", ["bash"]).split(/\r?\n/),
  pathEntries: inheritedPath.split(";").length, pathSHA256: hash(inheritedPath),
  manifest: manifest.map(s => ({ ...s, env: Object.fromEntries(Object.entries(s.env).filter(([key]) => /^(FM_|HOME$|USERPROFILE$)/.test(key))) })),
};
writeJSON("manifest.json", metadata);
fs.mkdirSync(`${out}/outputs`, { recursive: true });
if (traced) fs.mkdirSync(`${out}/traces`, { recursive: true });
const rows = [], totalCpuStart = cpu();
try {
  for (let round = -warmups; round < samples; round++) {
    const offset = (round + warmups) % selected.length;
    const order = [...selected.slice(offset), ...selected.slice(0, offset)];
    const versions = (round + warmups) % 2 === 0 ? ["base", "candidate"] : ["candidate", "base"];
    for (const scenario of order) {
      for (const version of versions) {
        const spec = manifest.find(s => s.id === scenario.id && s.version === version);
        if (traced) {
          spec.env.BASH_ENV = `${assets}/trace-hook.sh`;
          spec.env.WF_TRACE_LOG = `${out}/traces/${scenario.id}-${version}.log`;
        }
        const beforeCpu = cpu(), startedAt = new Date().toISOString(), started = performance.now();
        let result;
        try { result = await execute(spec); }
        catch (error) { result = { status: null, signal: null, stdout: "", stderr: String(error) }; }
        const ms = performance.now() - started, afterCpu = cpu();
        const outputName = `${scenario.id}-${version}-${round}`;
        fs.writeFileSync(`${out}/outputs/${outputName}.stdout.txt`, result.stdout);
        fs.writeFileSync(`${out}/outputs/${outputName}.stderr.txt`, result.stderr);
        let error;
        try { scenario.verify(result); assert.deepEqual(captureInputs(), inputs, "Reporting mutated the comparison inputs"); }
        catch (failure) { error = failure; }
        const row = { scenario: scenario.id, version, round, warmup: round < 0, traced, startedAt, ms,
          cpuBusyPercent: busy(beforeCpu, afterCpu), status: result.status, signal: result.signal, pid: result.pid,
          stdoutBytes: Buffer.byteLength(result.stdout), stdoutSHA256: hash(result.stdout),
          stderrBytes: Buffer.byteLength(result.stderr), outputName, verified: !error, error: error ? String(error) : undefined };
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
    const pairs = Array.from({ length: samples }, (_, round) => Object.fromEntries(rows
      .filter(row => row.scenario === s.id && row.round === round).map(row => [row.version, row.ms])));
    const fasterPairs = pairs.filter(pair => pair.candidate < pair.base).length;
    const medianReductionMs = stats.base.medianMs - stats.candidate.medianMs;
    const medianReductionPercent = 100 * medianReductionMs / stats.base.medianMs;
    const primary = s.id.endsWith("-small"), control = s.id === "control-bash";
    const p95NonIncreasing = stats.candidate.p95Ms <= stats.base.p95Ms;
    return { scenario: s.id, primary, control, ...stats, fasterPairs, medianReductionMs, medianReductionPercent, p95NonIncreasing,
      accepted: metadata.purpose === "qualification-batch" && !control && p95NonIncreasing &&
        (!primary || (medianReductionMs >= 500 && medianReductionPercent >= 5 && fasterPairs >= 15)) };
  });
  writeJSON("summary.json", { ...metadata, finished: new Date().toISOString(), meanHostCpuBusyPercent: busy(totalCpuStart, cpu()), summary,
    accepted: metadata.purpose === "qualification-batch" && summary.filter(s => !s.control).every(s => s.accepted) });
} catch (error) {
  writeJSON("failure.json", { message: String(error), stack: error.stack, rows });
  throw error;
}

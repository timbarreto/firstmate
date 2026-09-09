#!/usr/bin/env node
// Bounded reconciliation checks; fm-test-run.sh still owns test execution and
// fm-timeout-lib.sh still owns process-group deadlines.
//
// node validate-local.mjs --plan <json> --state-dir <outside-repo-dir>
//   [--root <checkout>] [--bash <recorded-bash>] [--budget-seconds 1200]
//   [--max-timeouts 2] [--resume] [--preflight-only]
//
// Plan: { context: { fork: "<sha>", upstream: "<sha>" }, checks: [
//   { id: "runner-case", kind: "test"|"gate", command: ["bash", "..."],
//     ci: "owning CI job", requires: [["node", "--version"]],
//     env: { FM_TEST_ONLY: "test_name" }, timeoutSeconds: 180,
//     cache: true, inputs: ["bin", "tests", "AGENTS.md"] }
// ], deferred: [{ id: "broad-regression", ci: "CI lanes", reason: "..." }] }
//
// Commands are argv arrays, never implicitly shell-evaluated. Inputs are
// explicit repository-relative files/directories; cache is opt-in and requires
// a reviewed complete dependency set. External-state and git-history checks
// must leave cache off. Cache identity includes context, controller/timeout
// bytes, input bytes/modes, command, environment digest, host and tool probes.
// Each completion is persisted atomically to result.json; only successful,
// non-skipped checks enter cache.json. Logs and cache stay outside the checkout.
// A state directory admits one invocation; a stale lock requires proof that its
// recorded owner is dead before removal. Resume never treats interrupted work
// as passed. Exit 0=all local checks passed, 1=failure, 2=invalid input,
// 75=incomplete/deferred/preflight-only. None of these means merge-ready.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const self = fileURLToPath(import.meta.url);
const digest = (value) => createHash("sha256").update(value).digest("hex");
const inside = (root, target) => {
  const relative = path.relative(root, target);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) &&
    relative !== ".." && !path.isAbsolute(relative));
};
const positive = (value, name) => {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number <= 0) throw new Error(`${name} must be a positive integer`);
  return number;
};
const argv = (value, name) => {
  if (!Array.isArray(value) || value.length === 0 ||
      value.some((part) => typeof part !== "string" || part.includes("\0")) || !value[0]) {
    throw new Error(`${name} must be a nonempty argv array`);
  }
};
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
function atomicJson(file, value) {
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: "wx", mode: 0o600 });
  fs.renameSync(temporary, file);
}
function options(args) {
  const result = { root: process.cwd(), bash: "bash", budget: 1200, maxTimeouts: 2 };
  for (let index = 0; index < args.length; index++) {
    const argument = args[index];
    if (argument === "--resume") result.resume = true;
    else if (argument === "--preflight-only") result.preflightOnly = true;
    else {
      const keys = { "--plan": "plan", "--state-dir": "stateDir", "--root": "root",
        "--bash": "bash", "--budget-seconds": "budget", "--max-timeouts": "maxTimeouts" };
      if (!keys[argument] || !args[index + 1]) throw new Error(`unknown or incomplete option: ${argument}`);
      result[keys[argument]] = args[++index];
    }
  }
  if (!result.plan || !result.stateDir) throw new Error("--plan and --state-dir are required");
  result.budget = positive(result.budget, "--budget-seconds");
  result.maxTimeouts = positive(result.maxTimeouts, "--max-timeouts");
  if (process.platform === "win32" && !path.isAbsolute(result.bash)) {
    throw new Error("Windows requires --bash with the recorded absolute Git-for-Windows bash.exe path");
  }
  return result;
}
function inputDigest(root, inputs) {
  const rows = [];
  function visit(file, ancestors) {
    const real = fs.realpathSync(file);
    if (!inside(root, real)) throw new Error(`input escapes repository: ${file}`);
    if (ancestors.has(real)) throw new Error(`cyclic input: ${file}`);
    const info = fs.lstatSync(file);
    const name = path.relative(root, file);
    if (info.isSymbolicLink()) {
      rows.push([name, "link", fs.readlinkSync(file)]);
      visit(real, new Set([...ancestors, file]));
    } else if (info.isDirectory()) {
      rows.push([name, "directory", info.mode & 0o777]);
      for (const child of fs.readdirSync(file).sort()) visit(path.join(file, child), new Set([...ancestors, real]));
    } else if (info.isFile()) rows.push([name, info.mode & 0o777, digest(fs.readFileSync(file))]);
    else throw new Error(`unsupported input type: ${file}`);
  }
  for (const input of [...inputs].sort()) {
    if (typeof input !== "string" || !input || path.isAbsolute(input)) throw new Error("inputs must be repository-relative paths");
    const file = path.resolve(root, input);
    if (!inside(root, file) || file === root) throw new Error(`unbounded input: ${input}`);
    visit(file, new Set());
  }
  return digest(JSON.stringify(rows));
}
function validatePlan(plan) {
  if (!plan.context || !["fork", "upstream"].every((key) => /^[a-f0-9]{40}$/.test(plan.context[key]))) {
    throw new Error("context must name literal 40-character fork and upstream SHAs");
  }
  if (!Array.isArray(plan.checks) || plan.checks.length === 0) throw new Error("checks must be nonempty");
  const ids = new Set();
  for (const check of plan.checks) {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(check.id) || ids.has(check.id)) throw new Error(`invalid or duplicate check id: ${check.id}`);
    ids.add(check.id);
    if (!["test", "gate"].includes(check.kind) || typeof check.ci !== "string" || !check.ci.trim()) {
      throw new Error(`${check.id}: kind and an owning CI job are required`);
    }
    argv(check.command, `${check.id}.command`);
    if (!Array.isArray(check.requires)) throw new Error(`${check.id}: requires must explicitly list prerequisite probes`);
    for (const probe of check.requires) argv(probe, `${check.id}.requires`);
    if (check.timeoutSeconds !== undefined) positive(check.timeoutSeconds, `${check.id}.timeoutSeconds`);
    if (check.cache !== undefined && typeof check.cache !== "boolean") throw new Error(`${check.id}: cache must be boolean`);
    if (check.cache && (!Array.isArray(check.inputs) || check.inputs.length === 0)) throw new Error(`${check.id}: caching requires explicit dependency inputs`);
    if (check.env !== undefined && (!check.env || Array.isArray(check.env) || typeof check.env !== "object" ||
      Object.entries(check.env).some(([key, value]) => !/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) || typeof value !== "string" || value.includes("\0")))) {
      throw new Error(`${check.id}: env must contain string environment assignments`);
    }
  }
  for (const deferred of plan.deferred ?? []) {
    if (!deferred.id || !deferred.ci || !deferred.reason) throw new Error("every deferred item needs id, ci, and reason");
  }
}
async function main() {
  const config = options(process.argv.slice(2));
  const root = fs.realpathSync(config.root);
  const stateDir = path.resolve(config.stateDir);
  if (inside(root, stateDir)) throw new Error("state directory must be outside the checkout");
  fs.mkdirSync(stateDir, { recursive: true });
  if (inside(root, fs.realpathSync(stateDir))) throw new Error("state directory resolves inside the checkout");
  const plan = readJson(config.plan);
  validatePlan(plan);
  const timeoutLibrary = path.join(root, "bin", "fm-timeout-lib.sh");
  const ownerHash = digest(Buffer.concat([fs.readFileSync(self), fs.readFileSync(timeoutLibrary)]));
  const lock = path.join(stateDir, "validation.lock");
  fs.writeFileSync(lock, JSON.stringify({ pid: process.pid, started: new Date().toISOString() }), { flag: "wx", mode: 0o600 });
  try {
    const cacheFile = path.join(stateDir, "cache.json");
    const cache = fs.existsSync(cacheFile) ? readJson(cacheFile) : { schema: 1, passed: {} };
    if (cache.schema !== 1 || !cache.passed || typeof cache.passed !== "object" || Array.isArray(cache.passed)) {
      throw new Error("invalid validation cache");
    }
    const started = Date.now();
    const deadline = started + config.budget * 1000;
    const logDirectory = path.join(stateDir, "logs", `${started}-${process.pid}`);
    fs.mkdirSync(logDirectory, { recursive: true });
    const results = [];
    const probes = new Map();
    let timeouts = 0;
    const remaining = () => Math.floor((deadline - Date.now()) / 1000);
    const snapshot = () => atomicJson(path.join(stateDir, "result.json"), {
      schema: 1, context: plan.context, started: new Date(started).toISOString(),
      updated: new Date().toISOString(), budgetSeconds: config.budget,
      elapsedMs: Date.now() - started, timeouts, results, deferred: plan.deferred ?? [],
    });
    async function bounded(command, env, seconds, logName) {
      if (seconds < 1) return { exit: 124, output: "", elapsedMs: 0 };
      const shellPath = (value) => process.platform === "win32"
        ? value.replace(/^([A-Za-z]):[\\/]/, (_, drive) => `/${drive.toLowerCase()}/`).replaceAll("\\", "/")
        : value;
      const logFile = path.join(logDirectory, logName);
      const descriptor = fs.openSync(logFile, "w", 0o600);
      const begin = Date.now();
      let output = "";
      let skipped = false;
      let skipTail = "\n";
      try {
        const child = spawn(config.bash, ["-c",
          'set +e; . "$1"; shift; command -v "$2" >/dev/null 2>&1 || { printf "prerequisite or command not found: %s\\n" "$2" >&2; exit 127; }; fm_run_timed "$@"',
          "_", shellPath(timeoutLibrary), String(seconds), shellPath(command[0]), ...command.slice(1)],
        { cwd: root, env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
        const collect = (chunk) => {
          fs.writeSync(descriptor, chunk);
          process.stdout.write(chunk);
          const text = chunk.toString();
          const scan = skipTail + text;
          skipped ||= /\nskip:/.test(scan);
          skipTail = scan.slice(-5);
          if (output.length < 65536) output += text.slice(0, 65536 - output.length);
        };
        child.stdout.on("data", collect);
        child.stderr.on("data", collect);
        const exit = await new Promise((resolve, reject) => {
          child.once("error", reject);
          child.once("close", (code, signal) => resolve(code ?? (signal ? 130 : 1)));
        });
        return { exit, output, skipped, elapsedMs: Date.now() - begin, log: logFile };
      } finally {
        fs.closeSync(descriptor);
      }
    }
    snapshot();
    for (const check of plan.checks) {
      const base = { id: check.id, kind: check.kind, ci: check.ci, command: check.command };
      if (remaining() < 1 || timeouts >= config.maxTimeouts) {
        results.push({ ...base, status: "deferred", reason: remaining() < 1 ? "local budget exhausted" : "timeout circuit breaker" });
        snapshot();
        console.log(`FM_RECONCILE_DEFER ${check.id} ci=${check.ci}`);
        continue;
      }
      const env = { ...process.env, ...check.env };
      const envHash = digest(JSON.stringify(Object.entries(env).sort(([a], [b]) => a.localeCompare(b))));
      const versions = [];
      let missing = false;
      for (let index = 0; index < check.requires.length; index++) {
        const probe = check.requires[index];
        const key = digest(JSON.stringify([probe, envHash]));
        if (!probes.has(key)) {
          const result = await bounded(probe, env, Math.min(30, remaining()), `${check.id}.preflight-${index}.log`);
          probes.set(key, result);
          if (result.exit === 124) timeouts++;
        }
        const result = probes.get(key);
        versions.push([probe, result.exit, digest(result.output)]);
        if (result.exit !== 0) {
          results.push({ ...base, status: "deferred", reason: "prerequisite probe failed", prerequisite: probe, exit: result.exit, log: result.log });
          console.log(`FM_RECONCILE_DEFER ${check.id} prerequisite=${JSON.stringify(probe)} ci=${check.ci}`);
          missing = true;
          break;
        }
      }
      if (missing || config.preflightOnly) {
        if (!missing) results.push({ ...base, status: "preflight-only" });
        snapshot();
        continue;
      }
      const fingerprint = digest(JSON.stringify({ context: plan.context, ownerHash,
        host: [process.platform, process.arch, os.release(), process.version, config.bash],
        command: check.command, envHash, versions,
        inputs: check.cache ? inputDigest(root, check.inputs) : null }));
      if (config.resume && check.cache && cache.passed[fingerprint]) {
        results.push({ ...base, status: "cached", fingerprint, reused: cache.passed[fingerprint] });
        console.log(`FM_RECONCILE_CACHED ${check.id}`);
        snapshot();
        continue;
      }
      console.log(`FM_RECONCILE_BEGIN ${check.id}`);
      const result = await bounded(check.command, env,
        Math.min(check.timeoutSeconds ?? config.budget, remaining()), `${check.id}.log`);
      const skipped = result.skipped;
      const status = result.exit === 124 ? "timeout" : result.exit !== 0 ? "failed" : skipped ? "deferred" : "passed";
      if (status === "timeout") timeouts++;
      results.push({ ...base, status, fingerprint, exit: result.exit, elapsedMs: result.elapsedMs, log: result.log,
        ...(skipped ? { reason: "command reported an optional-tool or live-policy skip" } : {}) });
      if (check.cache && status === "passed") {
        cache.passed[fingerprint] = { id: check.id, completed: new Date().toISOString(), log: result.log };
        atomicJson(cacheFile, cache);
      }
      snapshot();
      console.log(`FM_RECONCILE_END ${check.id} status=${status} duration_ms=${result.elapsedMs}`);
    }
    if (results.some((result) => result.status === "failed")) return 1;
    if (results.some((result) => !["passed", "cached"].includes(result.status))) return 75;
    return 0;
  } finally {
    fs.unlinkSync(lock);
  }
}
try {
  if (process.argv.slice(2).length === 1 && process.argv[2] === "--help") {
    const lines = fs.readFileSync(self, "utf8").split("\n");
    console.log(lines.slice(1, lines.findIndex((line) => line.startsWith("import ")))
      .map((line) => line.replace(/^\/\/ ?/, "")).join("\n"));
  } else process.exitCode = await main();
} catch (error) {
  console.error(`fm-reconcile-validation: ${error.message}`);
  process.exitCode = 2;
}

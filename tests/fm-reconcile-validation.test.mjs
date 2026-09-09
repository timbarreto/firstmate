import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const controller = path.join(root, "skills", "reconcile-firstmate-upstream", "scripts", "validate-local.mjs");
const bash = process.env.FM_RECONCILE_TEST_BASH ??
  (process.platform === "win32" ? path.join(process.env.ProgramFiles ?? "C:\\Program Files", "Git", "bin", "bash.exe") : "bash");
const context = { fork: "1".repeat(40), upstream: "2".repeat(40) };

function fixture(t) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "fm-reconcile-validation-"));
  const repo = path.join(temporary, "repo");
  const state = path.join(temporary, "state");
  const planFile = path.join(temporary, "plan.json");
  fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
  fs.copyFileSync(path.join(root, "bin", "fm-timeout-lib.sh"), path.join(repo, "bin", "fm-timeout-lib.sh"));
  fs.writeFileSync(path.join(repo, "input.txt"), "initial");
  fs.writeFileSync(path.join(repo, "unrelated.md"), "documentation");
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const marker = path.join(temporary, "executions");
  const command = [process.execPath, "-e",
    'require("node:fs").appendFileSync(process.argv[1], "run\\n")', marker];
  function check(id = "fixture", extra = {}) {
    return { id, kind: "test", command, requires: [], ci: "fixture-ci", ...extra };
  }
  function run(checks, options = {}) {
    fs.writeFileSync(planFile, JSON.stringify({ context: options.context ?? context, checks }));
    const result = spawnSync(process.execPath, [controller, "--plan", planFile, "--root", repo,
      "--state-dir", state, "--bash", bash,
      ...(options.defaultBudget ? [] : ["--budget-seconds", String(options.budget ?? 30)]),
      ...(options.resume ? ["--resume"] : []), ...(options.preflight ? ["--preflight-only"] : [])],
    { encoding: "utf8", timeout: 60000, env: { ...process.env, ...options.env } });
    assert.equal(result.error, undefined, result.error?.message);
    const artifact = path.join(state, "result.json");
    return { ...result, document: fs.existsSync(artifact) ? JSON.parse(fs.readFileSync(artifact, "utf8")) : null };
  }
  return { repo, state, marker, temporary, check, run };
}

test("the default wall budget is 40 minutes and explicit overrides are honored", (t) => {
  const f = fixture(t);
  for (const [options, expected] of [
    [{ defaultBudget: true }, 2400],
    [{ budget: 45 }, 45],
  ]) {
    const result = f.run([f.check()], options);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(result.document.budgetSeconds, expected);
    assert.equal(result.document.results[0].status, "passed");
  }
  assert.equal(fs.readFileSync(f.marker, "utf8"), "run\nrun\n");
});

test("preflight defers a missing prerequisite without executing the check", (t) => {
  const f = fixture(t);
  const result = f.run([f.check("missing", { requires: [["fm-nonexistent-prerequisite-5645cf38", "--version"]] })]);
  assert.equal(result.status, 75, result.stdout + result.stderr);
  assert.equal(result.document.results[0].status, "deferred");
  assert.equal(result.document.results[0].exit, 127);
  assert.equal(result.document.results[0].ci, "fixture-ci");
  assert.equal(fs.existsSync(f.marker), false);
});

test("preflight-only never certifies or executes a check", (t) => {
  const f = fixture(t);
  const result = f.run([f.check("probe", { requires: [[process.execPath, "--version"]] })], { preflight: true });
  assert.equal(result.status, 75, result.stdout + result.stderr);
  assert.equal(result.document.results[0].status, "preflight-only");
  assert.equal(fs.existsSync(f.marker), false);
});

test("resume reuses exact inputs, ignores unrelated prose, and invalidates changed inputs", (t) => {
  const f = fixture(t);
  const checks = [f.check("cache", { cache: true, inputs: ["input.txt"] })];
  const first = f.run(checks);
  assert.equal(first.status, 0, first.stdout + first.stderr);
  const originalLog = first.document.results[0].log;
  fs.writeFileSync(path.join(f.repo, "unrelated.md"), "updated documentation");
  const cached = f.run(checks, { resume: true });
  assert.equal(cached.status, 0, cached.stdout + cached.stderr);
  assert.equal(cached.document.results[0].status, "cached");
  assert.equal(cached.document.results[0].reused.log, originalLog);
  assert.equal(fs.readFileSync(f.marker, "utf8"), "run\n");
  fs.writeFileSync(path.join(f.repo, "input.txt"), "new behavior");
  const changed = f.run(checks, { resume: true });
  assert.equal(changed.status, 0, changed.stdout + changed.stderr);
  assert.equal(changed.document.results[0].status, "passed");
  assert.notEqual(changed.document.results[0].log, originalLog);
  assert.equal(fs.readFileSync(f.marker, "utf8"), "run\nrun\n");
});

test("cache identity includes environment, frozen context, and prerequisite versions", (t) => {
  const f = fixture(t);
  const versionFile = path.join(f.temporary, "tool-version");
  fs.writeFileSync(versionFile, "v1");
  const checks = [f.check("identity", { cache: true, inputs: ["input.txt"],
    requires: [[process.execPath, "-e", 'process.stdout.write(require("node:fs").readFileSync(process.argv[1]))', versionFile]] })];
  assert.equal(f.run(checks).status, 0);
  assert.equal(f.run(checks, { resume: true, env: { FM_RECONCILE_FIXTURE: "changed" } }).document.results[0].status, "passed");
  assert.equal(f.run(checks, { resume: true, context: { ...context, upstream: "3".repeat(40) } }).document.results[0].status, "passed");
  fs.writeFileSync(versionFile, "v2");
  assert.equal(f.run(checks, { resume: true }).document.results[0].status, "passed");
  assert.equal(fs.readFileSync(f.marker, "utf8"), "run\n".repeat(4));
});

test("failures and successful exits with skips never enter the pass cache", (t) => {
  const f = fixture(t);
  const checks = [
    f.check("failure", { cache: true, inputs: ["input.txt"], command: [process.execPath, "-e", "process.exit(3)"] }),
    f.check("skip", { cache: true, inputs: ["input.txt"], command: [process.execPath, "-e", 'console.log("x".repeat(70000)); console.log("skip: optional fixture capability absent")'] }),
  ];
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = f.run(checks, { resume: true });
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.deepEqual(result.document.results.map((item) => item.status), ["failed", "deferred"]);
    assert.equal(fs.existsSync(path.join(f.state, "cache.json")), false);
  }
});

test("two timeouts persist partial results and defer additional work", (t) => {
  const f = fixture(t);
  const slow = { command: [process.execPath, "-e", "setInterval(() => {}, 1000)"], timeoutSeconds: 2 };
  const result = f.run([f.check("timeout-one", slow), f.check("timeout-two", slow), f.check("not-started")]);
  assert.equal(result.status, 75, result.stdout + result.stderr);
  assert.deepEqual(result.document.results.map((item) => item.status), ["timeout", "timeout", "deferred"]);
  assert.equal(result.document.results[2].reason, "timeout circuit breaker");
  assert.equal(result.document.timeouts, 2);
  assert.equal(fs.existsSync(f.marker), false);
});

test("the wall budget cancels a running command and prevents its delayed result", async (t) => {
  const f = fixture(t);
  const started = path.join(f.temporary, "started");
  const late = path.join(f.temporary, "late");
  const command = [process.execPath, "-e",
    'const fs=require("node:fs"); fs.writeFileSync(process.argv[1],"started"); setTimeout(()=>fs.writeFileSync(process.argv[2],"late"),8000)',
    started, late];
  const begin = Date.now();
  const result = f.run([f.check("budget", { command }), f.check("not-started")], { budget: 3 });
  assert.equal(result.status, 75, result.stdout + result.stderr);
  assert.equal(fs.existsSync(started), true, "budget test must reach the real command");
  assert.equal(result.document.results[0].status, "timeout");
  assert.equal(result.document.results[1].reason, "local budget exhausted");
  assert.ok(Date.now() - begin < 15000, "the budget must interrupt rather than wait for a command to finish");
  await delay(Math.max(0, 10000 - (Date.now() - begin)));
  assert.equal(fs.existsSync(late), false, "timed-out command survived and wrote its delayed result");
  assert.equal(fs.existsSync(f.marker), false);
});

test("caching refuses missing or out-of-scope dependency inputs", (t) => {
  const f = fixture(t);
  for (const inputs of [[], ["."], ["../"], ["absent"]]) {
    const result = f.run([f.check("invalid", { cache: true, inputs })]);
    assert.equal(result.status, 2, result.stdout + result.stderr);
    assert.equal(fs.existsSync(f.marker), false);
  }
});

test("registered shell cases preserve default order, select exactly one, and refuse typos", (t) => {
  const f = fixture(t);
  const library = path.join(root, "tests", "lib.sh").replaceAll("\\", "/");
  const script = `. "$1"\ntest_first() { echo first; }\ntest_second() { echo second; }\nfm_test_run_cases test_first test_second`;
  const run = (env) => spawnSync(bash, ["-c", script, "_", library],
    { encoding: "utf8", timeout: 30000, env: { ...process.env, TMPDIR: f.temporary.replaceAll("\\", "/"), ...env } });
  assert.match(run({ FM_TEST_ONLY: "", FM_TEST_LIST_CASES: "0" }).stdout, /first\nsecond/);
  const selected = run({ FM_TEST_ONLY: "test_second", FM_TEST_LIST_CASES: "0" });
  assert.equal(selected.status, 0, selected.stdout + selected.stderr);
  assert.equal(selected.stdout.trim(), "second");
  const listed = run({ FM_TEST_ONLY: "", FM_TEST_LIST_CASES: "1" });
  assert.equal(listed.status, 0, listed.stderr);
  assert.equal(listed.stdout.trim(), "test_first\ntest_second");
  const typo = run({ FM_TEST_ONLY: "test_typo", FM_TEST_LIST_CASES: "0" });
  assert.notEqual(typo.status, 0);
  assert.match(typo.stderr, /unknown case: test_typo/);
  assert.equal(typo.stdout, "");
  const invalidListing = run({ FM_TEST_ONLY: "", FM_TEST_LIST_CASES: "typo" });
  assert.notEqual(invalidListing.status, 0);
  assert.equal(invalidListing.stdout, "");
});

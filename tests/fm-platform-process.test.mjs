// Exercise the compatibility interfaces in fresh processes so each has its own cache.
import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { fileURLToPath } from "node:url";
import { once } from "node:events";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

const subjects = [
  new URL("../.pi/extensions/lib/fm-process-ancestry.ts", import.meta.url),
  new URL("../.opencode/plugins/lib/fm-process-ancestry.js", import.meta.url),
];
const cases = ["exports", "invalid", "posix", "windows-cache", "windows-missing-row", "windows-signal", "windows-terminate"];
const [scenario, subject] = process.argv.slice(2);

if (!scenario) {
  for (const url of subjects) {
    for (const name of cases) {
      const result = childProcess.spawnSync(process.execPath, [
        fileURLToPath(import.meta.url), name, url.href,
      ], { encoding: "utf8", timeout: 15000 });
      assert.equal(result.status, 0, `${url.pathname}: ${name}\n${result.stdout}${result.stderr}`);
    }
  }
  const pi = await import(subjects[0]);
  const opencode = await import(subjects[1]);
  for (const name of Object.keys(opencode)) {
    assert.equal(pi[name], opencode[name], `${name} must have one implementation`);
  }
  console.log("ok - both process compatibility interfaces pass isolated behavioral contracts");
  if (process.platform === "win32") await nativeContracts(pi);
  else {
    assert.equal(pi.isPidInCurrentAncestry(String(process.pid)), true);
    assert.equal(pi.isPidInCurrentAncestry(String(process.ppid)), true);
    assert.equal(pi.pidAlive(String(process.pid)), true);
    assert.equal(pi.shellVisibleProcessPid(), process.pid);
  }
} else {
  const calls = [];
  const signals = [];
  const windows = scenario.startsWith("windows");
  Object.defineProperty(process, "platform", { value: windows ? "win32" : "linux" });
  const nativePid = String(process.pid);
  const parentPid = String(process.ppid);
  const psRows = [
    " PID PPID PGID WINPID TTY UID STIME COMMAND",
    ` 71 70 71 ${nativePid} ? 1 00:00 node`,
    ` 70 1 70 ${parentPid} ? 1 00:00 bash`,
  ].join("\n");
  let alive = true;
  let nativeStatus = 0;
  let signalStatus = 0;
  process.kill = (pid, signal) => {
    signals.push([pid, signal]);
    if (!alive) throw new Error("ESRCH");
    return true;
  };
  childProcess.spawnSync = (command, args, options) => {
    calls.push({ command, args, options });
    if (command === "ps") {
      if (args[0] === "-W") return { status: 0, stdout: scenario === "windows-missing-row" ? "" : psRows };
      assert.deepEqual(args, ["-o", "ppid=", "-p", parentPid]);
      return { status: 0, stdout: " 1 \n" };
    }
    if (command === "bash") {
      assert.deepEqual(args, ["-c", 'kill -TERM "$1"', "firstmate-watch-arm-signal", "70"]);
      return { status: signalStatus };
    }
    assert.match(command, /\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe$/);
    assert.ok(args.includes("-File"));
    assert.match(args.at(-2), /windows-process\.ps1$/);
    assert.equal(args.at(-1), scenario === "windows-signal" ? "find-watch-arm-roots" : "stop-watch-arm-tree");
    assert.equal(options.env.FM_WATCH_ARM_ROOT_PID, "713");
    assert.equal(options.windowsHide, true);
    return { status: nativeStatus, stdout: `${nativePid}\r\n${parentPid}\r\n` };
  };
  syncBuiltinESMExports();
  const mod = await import(subject);
  const isPi = subject.endsWith(".ts");

  switch (scenario) {
    case "exports": {
      const names = ["isPidInCurrentAncestry", "signalWatchArmProcess", "terminateWatchArmProcessTree"];
      if (isPi) names.push("pidAlive", "shellVisibleProcessPid");
      assert.deepEqual(Object.keys(mod).sort(), names.sort());
      assert.equal(calls.length, 0);
      break;
    }
    case "invalid":
      for (const pid of ["", "0", "1", "-1", "2;exit", "2.5", " 2"]) {
        assert.equal(mod.isPidInCurrentAncestry(pid), false);
        if (isPi) assert.equal(mod.pidAlive(pid), false);
      }
      for (const pid of [undefined, 0, 1, -1, 2.5, NaN, Infinity, "713"]) {
        assert.equal(mod.signalWatchArmProcess(pid), false);
        assert.equal(mod.terminateWatchArmProcessTree(pid), false);
      }
      assert.deepEqual(calls, []);
      assert.deepEqual(signals, []);
      break;
    case "posix":
      assert.equal(mod.isPidInCurrentAncestry(nativePid), true);
      assert.equal(mod.isPidInCurrentAncestry(parentPid), true);
      assert.equal(mod.isPidInCurrentAncestry("999999"), false);
      assert.equal(calls.length, 1);
      assert.equal(mod.isPidInCurrentAncestry(nativePid, 0), false);
      if (isPi) {
        assert.equal(mod.shellVisibleProcessPid(), process.pid);
        assert.equal(mod.pidAlive("713"), true);
      }
      assert.equal(mod.signalWatchArmProcess(713), true);
      assert.equal(mod.terminateWatchArmProcessTree(714), true);
      alive = false;
      assert.equal(mod.signalWatchArmProcess(713), false);
      assert.equal(mod.terminateWatchArmProcessTree(714), false);
      assert.deepEqual(signals.slice(-4), [[713, "SIGTERM"], [714, "SIGTERM"], [713, "SIGTERM"], [714, "SIGTERM"]]);
      break;
    case "windows-cache":
      assert.equal(mod.isPidInCurrentAncestry("71"), true);
      assert.equal(mod.isPidInCurrentAncestry(nativePid), true);
      assert.equal(mod.isPidInCurrentAncestry("70"), true);
      assert.equal(mod.isPidInCurrentAncestry(parentPid), true);
      assert.equal(calls.length, 1);
      alive = false;
      assert.equal(mod.isPidInCurrentAncestry("71"), false);
      assert.equal(calls.length, 1, "cached ancestry must still verify native liveness");
      if (isPi) {
        assert.equal(mod.shellVisibleProcessPid(), 71);
        assert.equal(calls.length, 1);
        assert.equal(mod.pidAlive("71"), false);
        assert.equal(mod.pidAlive("71"), false);
        assert.equal(calls.length, 3, "ordinary PID liveness must not use an ancestry cache");
      }
      break;
    case "windows-missing-row":
      assert.equal(mod.isPidInCurrentAncestry(nativePid), true);
      assert.equal(mod.isPidInCurrentAncestry(parentPid), true);
      assert.equal(mod.isPidInCurrentAncestry("71"), false);
      if (isPi) assert.equal(mod.shellVisibleProcessPid(), process.pid);
      assert.equal(calls.length, 1);
      break;
    case "windows-signal":
      assert.equal(mod.signalWatchArmProcess(713, "owned.token-1"), true);
      assert.equal(calls.length, 3, "signal uses one native query, one MSYS table, one TERM");
      assert.equal(calls[0].options.env.FM_WATCH_ARM_OWNER_TOKEN, "owned.token-1");
      nativeStatus = 3;
      assert.equal(mod.signalWatchArmProcess(713, "bad'; token"), false);
      assert.equal(calls.at(-1).options.env.FM_WATCH_ARM_OWNER_TOKEN, "");
      assert.equal(calls.length, 4, "failed native proof must not signal a candidate");
      nativeStatus = 0;
      signalStatus = 1;
      assert.equal(mod.signalWatchArmProcess(713), false);
      assert.deepEqual(signals, []);
      break;
    case "windows-terminate":
      assert.equal(mod.terminateWatchArmProcessTree(713, "owned.token-1"), true);
      assert.equal(calls.length, 1, "tree cleanup must use one batched native operation");
      assert.deepEqual(signals, []);
      assert.equal(calls[0].options.env.FM_WATCH_ARM_OWNER_TOKEN, "owned.token-1");
      // Preserve the existing direct-PID fallback, not a new cached authorization.
      nativeStatus = 3;
      assert.equal(mod.terminateWatchArmProcessTree(713), true);
      assert.deepEqual(signals, [[713, "SIGTERM"]]);
      alive = false;
      assert.equal(mod.terminateWatchArmProcessTree(713), false);
      break;
    default:
      throw new Error(`unknown process contract: ${scenario}`);
  }
}

async function nativeContracts(mod) {
  const root = process.env.FM_PROCESS_TEST_ROOT;
  assert.ok(root, "the shell entrypoint must supply its isolated fixture root");
  const directory = join(root, "Crew O'Brien [literal]; $value");
  mkdirSync(directory, { recursive: true });
  const script = join(directory, "fm-watch-arm.sh");
  const marker = join(directory, "stopped");
  writeFileSync(script, [
    "#!/usr/bin/env bash",
    "trap 'printf stopped > \"$FM_PROCESS_STOP_MARKER\"; exit 0' TERM",
    "printf 'ready:%s\\n' \"$$\"",
    "while :; do sleep 0.1; done",
    "",
  ].join("\n"));
  const graceful = childProcess.spawn("bash", [script, `fm-${randomUUID()}`], {
    env: { ...process.env, FM_PROCESS_STOP_MARKER: marker },
    stdio: ["ignore", "pipe", "inherit"],
  });
  const gracefulClosed = once(graceful, "close");
  const token = graceful.spawnargs.at(-1);
  try {
    const text = await readyLine(graceful);
    assert.match(text, /^ready:\d+/);
    assert.equal(mod.pidAlive(String(graceful.pid)), true);
    assert.equal(mod.signalWatchArmProcess(graceful.pid, token), true);
    await boundedWait(gracefulClosed, "graceful Bash TERM");
    assert.equal(readFileSync(marker, "utf8"), "stopped");
  } finally {
    if (graceful.exitCode === null && graceful.signalCode === null) {
      graceful.kill("SIGTERM");
      await boundedWait(gracefulClosed, "graceful fixture cleanup");
    }
  }

  const launched = [];
  function launchTree(owner) {
    const child = childProcess.spawn(process.execPath, [
      "-e",
      'const {spawn}=require("node:child_process"); const child=spawn(process.execPath,["-e","setInterval(()=>{},1000)"],{stdio:"ignore"}); console.log(JSON.stringify({root:process.pid,child:child.pid})); setInterval(()=>{},1000);',
      "fm-watch-arm.sh", owner,
    ], { stdio: ["ignore", "pipe", "inherit"] });
    const entry = { child, closed: once(child, "close"), ids: [] };
    launched.push(entry);
    return entry;
  }
  const owner = `fm-${randomUUID()}`;
  const owned = launchTree(owner);
  const foreign = launchTree(`fm-${randomUUID()}`);
  try {
    for (const entry of launched) {
      const ids = JSON.parse(await readyLine(entry.child));
      entry.ids = [ids.root, ids.child];
      assert.equal(ids.root, entry.child.pid);
    }
    assert.equal(mod.isPidInCurrentAncestry(String(foreign.child.pid)), false);
    assert.equal(mod.signalWatchArmProcess(2147483647, `stale-${randomUUID()}`), false);
    assert.equal(mod.terminateWatchArmProcessTree(2147483647, `stale-${randomUUID()}`), false);
    assert.ok(foreign.ids.every(nativeAlive), "stale ownership affected a foreign tree");
    assert.equal(mod.terminateWatchArmProcessTree(owned.child.pid, owner), true);
    await boundedWait(owned.closed, "owned native process tree");
    for (let attempt = 0; attempt < 100 && owned.ids.some(nativeAlive); attempt++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert.ok(owned.ids.every((pid) => !nativeAlive(pid)), "owned descendants survived");
    assert.ok(foreign.ids.every(nativeAlive), "owned cleanup affected a foreign tree");
  } finally {
    for (const entry of launched) {
      for (const pid of entry.ids.toReversed()) {
        if (nativeAlive(pid)) process.kill(pid, "SIGTERM");
      }
      if (entry.ids.length === 0) entry.child.kill("SIGTERM");
      await boundedWait(entry.closed, "native fixture cleanup");
    }
  }
  assert.ok(existsSync(marker));
  console.log("ok - native Windows PID translation, graceful TERM, and owned tree cleanup preserve foreign processes");
}

function nativeAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function boundedWait(promise, label) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`timeout: ${label}`)), 10000);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function readyLine(child) {
  const output = (async () => {
    let text = "";
    for await (const chunk of child.stdout) {
      text += chunk;
      if (text.includes("\n")) return text.trim();
    }
    throw new Error("fixture exited before publishing its PID");
  })();
  return boundedWait(output, "fixture PID publication");
}

// Exercise the compatibility interfaces in fresh processes so each has its own cache.
import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { fileURLToPath } from "node:url";

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
      ], { encoding: "utf8" });
      assert.equal(result.status, 0, `${url.pathname}: ${name}\n${result.stdout}${result.stderr}`);
    }
  }
  console.log("ok - both process compatibility interfaces pass isolated behavioral contracts");
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

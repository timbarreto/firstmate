// Shared process identity and watch-arm cleanup for Pi and OpenCode.
// Ancestry is cached per module instance; native liveness and cleanup are never
// authorized from that cache. No vendor or lifecycle policy is owned here.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

function nativePidAlive(pid) {
  const numericPid = Number(pid);
  if (!Number.isSafeInteger(numericPid) || numericPid < 2) return false;
  try {
    process.kill(numericPid, 0);
    return true;
  } catch {
    return false;
  }
}

const windowsPowerShell = `${
  process.env.SystemRoot || process.env.WINDIR || "C:\\Windows"
}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe`;
const windowsProcessScript = fileURLToPath(new URL("./windows-process.ps1", import.meta.url));

function windowsProcessArguments(operation) {
  if (!existsSync(windowsProcessScript)) {
    throw new Error(`Firstmate process helper is missing: ${windowsProcessScript}`);
  }
  return [
    "-NoProfile", "-NoLogo", "-NonInteractive", "-ExecutionPolicy", "Bypass",
    "-File", windowsProcessScript, operation,
  ];
}

function readWindowsProcessRows() {
  const result = spawnSync("ps", ["-W"], { encoding: "utf8" });
  if (result.status !== 0) return [];
  const rows = [];
  for (const line of result.stdout.split(/\r?\n/)) {
    const match = line.match(/^\s*([0-9]+)\s+([0-9]+)\s+[0-9]+\s+([0-9]+)\s+/);
    if (!match) continue;
    rows.push({ pid: match[1], ppid: match[2], winPid: match[3] });
  }
  return rows;
}

let cachedWindowsAncestry = null;
let cachedWindowsProcessPid = "";

function windowsAncestry(maxDepth) {
  if (cachedWindowsAncestry) return cachedWindowsAncestry;
  const identifiers = new Map();
  const rows = readWindowsProcessRows();
  const byPid = new Map(rows.map((row) => [row.pid, row]));
  let row = rows.find((candidate) => candidate.winPid === String(process.pid));
  if (!row) {
    cachedWindowsProcessPid = String(process.pid);
    identifiers.set(String(process.pid), String(process.pid));
    identifiers.set(String(process.ppid), String(process.ppid));
    cachedWindowsAncestry = identifiers;
    return identifiers;
  }
  cachedWindowsProcessPid = row.pid;
  for (let depth = 0; depth < maxDepth && row; depth += 1) {
    identifiers.set(row.pid, row.winPid);
    identifiers.set(row.winPid, row.winPid);
    if (row.ppid === "0" || row.ppid === "1") break;
    row = byPid.get(row.ppid);
  }
  cachedWindowsAncestry = identifiers;
  return identifiers;
}

function posixParentPid(pid) {
  if (pid === String(process.pid)) return String(process.ppid);
  const result = spawnSync("ps", ["-o", "ppid=", "-p", pid], { encoding: "utf8" });
  if (result.status !== 0) return "";
  const parent = result.stdout.trim();
  return /^[0-9]+$/.test(parent) ? parent : "";
}

export function isPidInCurrentAncestry(pid, maxDepth = 8) {
  if (!/^[0-9]+$/.test(pid) || pid === "0" || pid === "1") return false;
  if (process.platform === "win32") {
    const nativePid = windowsAncestry(maxDepth).get(pid);
    return nativePid !== undefined && nativePidAlive(nativePid);
  }
  let current = String(process.pid);
  for (let depth = 0; depth < maxDepth; depth += 1) {
    if (current === pid) return true;
    current = posixParentPid(current);
    if (!current || current === "0" || current === "1") break;
  }
  return false;
}

export function shellVisibleProcessPid() {
  if (process.platform !== "win32") return process.pid;
  windowsAncestry(8);
  const pid = Number(cachedWindowsProcessPid);
  return Number.isSafeInteger(pid) && pid > 1 ? pid : process.pid;
}

export function pidAlive(pid) {
  if (!/^[0-9]+$/.test(pid) || pid === "0" || pid === "1") return false;
  if (process.platform !== "win32") return nativePidAlive(pid);
  const row = readWindowsProcessRows().find((candidate) => candidate.pid === pid || candidate.winPid === pid);
  return nativePidAlive(row?.winPid ?? pid);
}

export function signalWatchArmProcess(pid, ownerToken = "") {
  if (!Number.isSafeInteger(pid) || pid < 2) return false;
  if (process.platform !== "win32") {
    try {
      process.kill(pid, "SIGTERM");
      return true;
    } catch {
      return false;
    }
  }
  const result = spawnSync(windowsPowerShell, windowsProcessArguments("find-watch-arm-roots"), {
    encoding: "utf8",
    env: {
      ...process.env,
      FM_WATCH_ARM_ROOT_PID: String(pid),
      FM_WATCH_ARM_OWNER_TOKEN: /^[A-Za-z0-9._-]+$/.test(ownerToken) ? ownerToken : "",
    },
    windowsHide: true,
  });
  if (result.status !== 0) return false;
  const nativePids = new Set(
    result.stdout.split(/\r?\n/).filter((value) => /^[0-9]+$/.test(value)),
  );
  const candidates = readWindowsProcessRows().filter((row) => nativePids.has(row.winPid));
  const managedCandidates = candidates.filter((row) => row.ppid !== "0");
  const owners = managedCandidates.length > 0 ? managedCandidates : candidates;
  const ownerPids = new Set(owners.map((row) => row.pid));
  const owner = owners.find((row) => !ownerPids.has(row.ppid)) ?? owners[0];
  if (!owner) return false;
  const signalled = spawnSync(
    "bash",
    ["-c", 'kill -TERM "$1"', "firstmate-watch-arm-signal", owner.pid],
    { stdio: "ignore", windowsHide: true },
  );
  return signalled.status === 0;
}

export function terminateWatchArmProcessTree(pid, ownerToken = "") {
  if (!Number.isSafeInteger(pid) || pid < 2) return false;
  if (process.platform === "win32") {
    const result = spawnSync(windowsPowerShell, windowsProcessArguments("stop-watch-arm-tree"), {
      env: {
        ...process.env,
        FM_WATCH_ARM_ROOT_PID: String(pid),
        FM_WATCH_ARM_OWNER_TOKEN: /^[A-Za-z0-9._-]+$/.test(ownerToken) ? ownerToken : "",
      },
      stdio: "ignore",
      windowsHide: true,
    });
    if (result.status === 0) return true;
  }
  try {
    process.kill(pid, "SIGTERM");
    return true;
  } catch {
    return false;
  }
}

// Offline partial Bash accounting, using the frozen baseline packet's algorithm.
// These are trace observations, not a kernel/native process-start census.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { gunzipSync } from "node:zlib";

const root = process.argv[2];
const tools = new Set(["awk", "jq", "sed", "cat", "head", "tail", "grep", "cut", "tr", "sort",
  "date", "uname", "perl", "git", "stat", "ps", "tasklist.exe", "powershell.exe", "node", "bash",
  "dirname", "basename", "mkdir", "rmdir", "rm", "mv", "touch", "realpath", "chmod", "find", "env",
  "wc", "readlink", "cygpath"]);
const base = value => value.replaceAll("\\", "/").split("/").at(-1);
const ordered = map => Object.fromEntries([...map].sort((a, b) => b[1] - a[1]));
const observations = [];
for (const file of fs.readdirSync(root).sort()) {
  const name = file.match(/^(.*)-(base|candidate)\.log(?:\.gz)?$/);
  assert(name, `Unexpected trace file: ${file}`);
  const bytes = fs.readFileSync(path.join(root, file));
  const text = (file.endsWith(".gz") ? gunzipSync(bytes) : bytes).toString("utf8");
  const contexts = new Map(), entries = new Map(), calls = new Map();
  let boots = 0, traceRows = 0, maxLevel = 0;
  for (const line of text.split("\n")) {
    if (line.startsWith("WFBOOT|")) {
      boots++;
      const entry = base(line.split("|")[2]);
      entries.set(entry, (entries.get(entry) ?? 0) + 1);
    }
    const match = line.match(/^W*WFTRACE\|(\d+)\|(\d+)\|([^|]*)\|(\d+)\| (.*)$/);
    if (!match) continue;
    traceRows++;
    const [, pid, level, , , command] = match;
    maxLevel = Math.max(maxLevel, Number(level));
    if (!contexts.has(pid)) contexts.set(pid, Number(level));
    const tool = base(command.replace(/^(command|exec) /, "").split(" ")[0].replaceAll("'", ""));
    if (tools.has(tool)) calls.set(tool, (calls.get(tool) ?? 0) + 1);
  }
  observations.push({ scenario: name[1], version: name[2], scope: "partial Bash observations, NOT a native process census",
    freshBashEntries: boots, observedBashContexts: contexts.size,
    additionalSubshellContexts: [...contexts.values()].filter(level => level > 0).length,
    maximumObservedSubshellDepth: maxLevel, traceRows, bytes: Buffer.byteLength(text),
    helperEntries: ordered(entries), externalCommandEvaluations: ordered(calls) });
}
console.log(JSON.stringify({ observations }, null, 2));

// Offline accounting only. Does not run Firstmate or alter any timing samples.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { gunzipSync } from "node:zlib";

const packet = process.argv[2];
const families = ["copilot", "pi", "reporting", "startup-empty", "relaunch"];
const tools = new Set(["awk", "jq", "sed", "cat", "head", "tail", "grep", "cut", "tr", "sort",
  "date", "uname", "perl", "git", "stat", "ps", "tasklist.exe", "powershell.exe", "node", "bash",
  "dirname", "basename", "mkdir", "rmdir", "rm", "mv", "touch", "realpath", "chmod", "find", "env",
  "wc", "readlink", "cygpath"]);
const ordered = map => Object.fromEntries([...map].sort((a, b) => b[1] - a[1]));
const base = value => value.replaceAll("\\", "/").split("/").at(-1);
const results = { successfulMeasuredSamples: 0, successfulWarmups: 0, timing: [], attribution: [] };
for (const family of families) {
  const summary = JSON.parse(fs.readFileSync(`${packet}/timings/${family}/summary.json`, "utf8"));
  const rows = fs.readFileSync(`${packet}/timings/${family}/samples.jsonl`, "utf8").trim().split("\n").map(JSON.parse);
  assert(!summary.traced);
  assert(rows.every(row => row.status === 0 && !row.traced));
  assert.equal(rows.length, summary.manifest.length * (summary.samples + summary.warmups));
  results.successfulMeasuredSamples += rows.filter(row => !row.warmup).length;
  results.successfulWarmups += rows.filter(row => row.warmup).length;
  results.timing.push({ family, started: summary.started, finished: summary.finished,
    codeSHA: summary.codeSHA, meanHostCpuBusyPercent: summary.meanHostCpuBusyPercent, summary: summary.summary });
  const traceRoot = `${packet}/counts/${family}/traces`;
  for (const file of fs.readdirSync(traceRoot)) {
    const bytes = fs.readFileSync(path.join(traceRoot, file));
    const text = (file.endsWith(".gz") ? gunzipSync(bytes) : bytes).toString("utf8");
    const contexts = new Map(), boots = [], sites = new Map(), calls = new Map(), helperEntries = new Map();
    let maxLevel = 0, traceRows = 0;
    for (const line of text.split("\n")) {
      if (line.startsWith("WFBOOT|")) {
        const [, pid, entry] = line.split("|");
        boots.push({ pid, entry });
        helperEntries.set(base(entry), (helperEntries.get(base(entry)) ?? 0) + 1);
      }
      const match = line.match(/^W*WFTRACE\|(\d+)\|(\d+)\|([^|]*)\|(\d+)\| (.*)$/);
      if (!match) continue;
      traceRows++;
      const [, pid, level, source, number, command] = match;
      maxLevel = Math.max(maxLevel, Number(level));
      const site = `${base(source)}:${number}`;
      if (!contexts.has(pid)) {
        contexts.set(pid, { level: Number(level), site });
        sites.set(site, (sites.get(site) ?? 0) + 1);
      }
      const name = base(command.replace(/^(command|exec) /, "").split(" ")[0].replaceAll("'", ""));
      if (tools.has(name)) calls.set(name, (calls.get(name) ?? 0) + 1);
    }
    results.attribution.push({ family, scenario: file.replace(/\.log(?:\.gz)?$/, ""),
      sampledOperations: 1, scope: "partial Bash observations, NOT a kernel process census",
      bytes: Buffer.byteLength(text), traceRows, freshBashEntries: boots.length,
      observedBashContexts: contexts.size,
      additionalSubshellContexts: [...contexts.values()].filter(context => context.level > 0).length,
      maximumObservedSubshellDepth: maxLevel, helperEntries: ordered(helperEntries),
      firstObservedContextSites: ordered(sites), externalCommandEvaluations: ordered(calls) });
  }
}
const median = values => {
  const sorted = [...values].sort((a, b) => a - b);
  return (sorted[Math.floor((sorted.length - 1) / 2)] + sorted[Math.floor(sorted.length / 2)]) / 2;
};
results.startupStages = [];
const startupRounds = JSON.parse(fs.readFileSync(`${packet}/timings/startup-empty/summary.json`, "utf8")).samples;
for (const harness of ["copilot", "pi"]) {
  const values = new Map();
  for (let round = 0; round < startupRounds; round++) {
    const file = `${packet}/timings/startup-empty/stages/${harness}-empty-${round}.tsv`;
    for (const line of fs.readFileSync(file, "utf8").trim().split("\n")) {
      const fields = line.split("\t");
      if (fields[0] !== "v1" || fields[1] !== "stage") continue;
      const durations = values.get(fields[2]) ?? [];
      durations.push(Number(fields[4]));
      values.set(fields[2], durations);
    }
  }
  results.startupStages.push({ harness, stages: [...values].map(([stage, durations]) => ({
    stage, n: durations.length, medianMs: median(durations), maxMs: Math.max(...durations),
  })) });
}
console.log(JSON.stringify(results, null, 2));

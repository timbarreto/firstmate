// Offline audit of the two retained batches, not another measurement attempt.
// Run against the original run directories, or unpack outputs.tar.gz into each.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
const root = process.argv[2];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const expectedIds = ['control-bash', 'control-powershell', 'copilot-busy', 'copilot-idle', 'pi-busy', 'pi-idle', 'pi-progress'];
const median = sorted => (sorted[9] + sorted[10]) / 2;
const audits = [];
let reference;
for (const batch of [1, 2]) {
  const dir = `${root}/batch-${batch}`;
  const summary = JSON.parse(fs.readFileSync(`${dir}/summary.json`, 'utf8'));
  const rows = fs.readFileSync(`${dir}/samples.jsonl`, 'utf8').trim().split('\n').map(line => JSON.parse(line));
  const fixed = {pins:summary.pins, driverSHA:summary.driverSHA, driverFiles:summary.driverFiles, tools:summary.tools, pathSHA256:summary.pathSHA256};
  if (reference) assert.deepEqual(fixed, reference); else reference = fixed;
  assert.equal(summary.purpose, 'qualification-batch');
  assert.equal(summary.samples, 20);
  assert.equal(summary.warmups, 3);
  assert.equal(rows.length, 322);
  assert.equal(new Set(rows.map(row => `${row.scenario}|${row.version}|${row.round}`)).size, 322);
  assert.deepEqual([...new Set(rows.map(row => row.scenario))].sort(), expectedIds);
  for (const row of rows) {
    assert.equal(row.verified, true);
    assert.equal(row.traced, false);
    assert.equal(row.status, 0);
    assert.equal(row.signal, null);
    assert.equal(row.warmup, row.round < 0);
    assert(Number.isFinite(row.ms) && row.ms > 0);
    const stdout = fs.readFileSync(`${dir}/outputs/${row.outputName}.stdout.txt`);
    const stderr = fs.readFileSync(`${dir}/outputs/${row.outputName}.stderr.txt`);
    assert.equal(stdout.length, 0);
    assert.equal(stderr.length, 0);
    assert.equal(hash(stdout), row.stdoutSHA256);
    assert.equal(stdout.length, row.stdoutBytes);
    assert.equal(stderr.length, row.stderrBytes);
    JSON.parse(fs.readFileSync(`${dir}/outputs/${row.outputName}.state.json`, 'utf8'));
  }
  for (const id of expectedIds) {
    const item = summary.summary.find(item => item.scenario === id);
    let faster = 0;
    for (let round = -3; round < 20; round++) {
      const pair = rows.filter(row => row.scenario === id && row.round === round);
      assert.deepEqual(pair.map(row => row.version), (round + 3) % 2 ? ['candidate', 'base'] : ['base', 'candidate']);
      if (round >= 0 && pair.find(row => row.version === 'candidate').ms < pair.find(row => row.version === 'base').ms) faster++;
    }
    assert.equal(item.fasterPairs, faster);
    for (const version of ['base', 'candidate']) {
      const values = rows.filter(row => row.scenario === id && row.version === version && !row.warmup).map(row => row.ms).sort((a, b) => a - b);
      assert.equal(values.length, 20);
      assert.equal(item[version].medianMs, median(values));
      assert.equal(item[version].p95Ms, values[18]);
      assert.equal(item[version].maxMs, values[19]);
    }
    const reduction = item.base.medianMs - item.candidate.medianMs;
    const tail = item.candidate.p95Ms <= item.base.p95Ms;
    const accepted = !item.control && tail && (!item.primary || (reduction >= 100 && reduction / item.base.medianMs >= 0.1 && faster >= 15));
    assert.equal(item.accepted, accepted);
  }
  assert.equal(summary.accepted, summary.summary.filter(item => !item.control).every(item => item.accepted));
  audits.push({batch,fixtureOperations:rows.length,measuredOperations:rows.filter(row=>!row.warmup).length,
    warmupOperations:rows.filter(row=>row.warmup).length,outputDigestsVerified:true,statisticsVerified:true,accepted:summary.accepted,
    copilotFixtureCompletionsOverConfigured10Seconds:rows.filter(row=>!row.warmup && row.scenario.startsWith('copilot-') && row.ms > 10000)
      .map(row=>({scenario:row.scenario,version:row.version,round:row.round,ms:row.ms}))});
}
console.log(JSON.stringify({reference,audits}, null, 2));

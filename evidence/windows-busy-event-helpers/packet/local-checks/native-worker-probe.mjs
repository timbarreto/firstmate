// Task-owned fixture diagnostic. No vendor session or private fleet access.
import cp from 'node:child_process';
import fs from 'node:fs';
const root = 'C:/src/.fm-perf-runs/busy-event-helpers/checks/native-worker-probe';
const ps = `${process.env.SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe`;
for (const version of ['base', 'perf']) {
  const code = `C:/src/firstmate-${version}-busy-event-helpers`;
  const home = `${root}/${version}`;
  fs.mkdirSync(`${home}/state`, {recursive:true});
  fs.writeFileSync(`${home}/state/task.busy-gen`, 'g.fixture\n');
  fs.writeFileSync(`${home}/state/task.busy-state`, 'v1 gen=g.fixture seq=1 state=busy source=fm-spawn event=launch-brief ts=1\n');
  const env = {...process.env};
  for (const key of Object.keys(env)) if (/^(FM_|TASKS_AXI_|COPILOT_|BASH_ENV$)/i.test(key)) delete env[key];
  Object.assign(env, {COPILOT_CLI:'1', FM_HOME:home, HOME:home, USERPROFILE:home, FM_LIVE:'0'});
  const args = ['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',`${code}/bin/fm-ghcp-hook.ps1`,
    'worker-event',`${home}/state`,'task','g.fixture','busy','user-prompt-submitted','-'];
  const result = cp.spawnSync(ps,args,{env,input:'',encoding:'utf8',windowsHide:true});
  fs.writeFileSync(`${home}/stdout.txt`, result.stdout ?? '');
  fs.writeFileSync(`${home}/stderr.txt`, result.stderr ?? '');
  fs.writeFileSync(`${home}/result.json`, JSON.stringify({version,status:result.status,signal:result.signal,args},null,2));
  console.log(JSON.stringify({version,status:result.status,stdout:result.stdout,stderr:result.stderr,
    record:fs.readFileSync(`${home}/state/task.busy-state`,'utf8'),files:fs.readdirSync(`${home}/state`)}));
}

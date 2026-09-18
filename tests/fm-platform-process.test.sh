#!/usr/bin/env bash
# Process compatibility contracts through the existing Pi/OpenCode and Bash interfaces.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/process-helpers.sh
. "$ROOT/tests/process-helpers.sh"

TMP_ROOT=$(fm_test_tmproot fm-platform-process)

test_process_compatibility_contracts() {
  local node_root=$TMP_ROOT
  case "${OS:-}" in
    Windows_NT) node_root=$(cygpath -w "$TMP_ROOT") || fail "could not convert native fixture root" ;;
  esac
  FM_PROCESS_TEST_ROOT="$node_root" node "$ROOT/tests/fm-platform-process.test.mjs" \
    || fail "process compatibility contracts"
  pass "Pi and OpenCode preserve process exports, PID semantics, ownership, and call counts"
}

test_process_facts_preserve_proc_and_ps() {
  local proc="$TMP_ROOT/proc" output
  mkdir -p "$proc/731"
  printf 'Name:\tfixture-name\nPPid:\t730\n' > "$proc/731/status"
  printf 'fixture\0two words\0' > "$proc/731/cmdline"
  output=$(FM_PROC_ROOT_OVERRIDE="$proc" bash -c '
    . "$1" || exit 1
    ps() { echo "unexpected ps" >&2; return 9; }
    fm_session_process_comm 731
    fm_session_process_args 731
    printf "\n"
    fm_session_process_ppid 731
  ' _ "$ROOT/bin/fm-session-lock-lib.sh") || fail "proc facts queried ps"
  [ "$output" = "$(printf 'fixture-name\nfixture two words \n730')" ] \
    || fail "proc process facts changed: $output"
  output=$(FM_PROC_ROOT_OVERRIDE="$proc/absent" bash -c '
    . "$1" || exit 1
    ps() {
      case "$*" in
        "-o comm= -p 731") printf "fallback-name\n" ;;
        "-o args= -p 731") printf "fallback two words\n" ;;
        "-o ppid= -p 731") printf " 730 \n" ;;
        *) return 9 ;;
      esac
    }
    fm_session_process_comm 731
    fm_session_process_args 731
    fm_session_process_ppid 731
  ' _ "$ROOT/bin/fm-session-lock-lib.sh") || fail "ps fallback failed"
  [ "$output" = "$(printf 'fallback-name\nfallback two words\n730')" ] \
    || fail "ps fallback facts changed: $output"
  (cd "$ROOT/bin" && bash -c '
    . fm-session-lock-lib.sh || exit 1
    declare -F fm_platform_process_comm >/dev/null
  ') || fail "bare-name session library load lost its process dependency"
  pass "process facts preserve proc overrides and POSIX fallback formatting"
}

test_transport_preserves_literal_data() {
  local value command
  value=$(printf "C:\\\\Crew O'Brien [x]; \044env:PATH\nsecond line")
  command=$(bash -c '
    . "$1" || exit 1
    fm_backend_herdr_windows_set_environment_command FM_TRANSPORT "$2"
  ' _ "$ROOT/bin/backends/herdr.sh" "$value") || fail "transport rendering failed"
  [ "$command" = "$(printf "\044env:FM_TRANSPORT = 'C:\\\\Crew O''Brien [x]; \044env:PATH\nsecond line'")" ] \
    || fail "transport changed literal metacharacters or newlines: $command"
  pass "Windows transport preserves quotes, metacharacters, and multiline data"
}

# shellcheck disable=SC2016 # PowerShell variables expand in the generated script.
test_native_transport_round_trip() {
  case "${OS:-}" in Windows_NT) ;; *) return 0 ;; esac
  local dir script native_dir native_bash native_script value
  dir="$TMP_ROOT/Crew O'Brien [literal]; \$value"
  mkdir -p "$dir"
  script="$dir/round-trip.ps1"
  native_dir=$(cygpath -w "$dir") || fail "could not convert fixture directory"
  native_bash=$(cygpath -w "$(command -v bash)") || fail "could not resolve fixture Bash"
  native_script=$(cygpath -w "$script") || fail "could not convert fixture script"
  value=$(printf "value ' [x]; \044env:PATH\nsecond line")
  printf '#!/usr/bin/env bash\nprintf "bash round trip\\n"\n' > "$dir/launch.sh"
  (
    # shellcheck source=/dev/null
    . "$ROOT/bin/backends/herdr.sh" || exit 1
    fm_backend_herdr_windows_set_environment_command FM_TRANSPORT "$value"
    fm_backend_herdr_windows_enter_worktree_command "$native_dir"
    printf '%s\n' \
      'if ($env:FM_TRANSPORT -cne $env:FM_EXPECTED_VALUE) { throw "environment data changed" }' \
      'if ((Get-Location).Path -cne $env:FM_EXPECTED_LOCATION) { throw "literal directory changed" }'
    fm_backend_herdr_windows_bash_script_command "$dir/launch.sh" "$native_bash"
    printf '%s\n' 'exit $LASTEXITCODE'
  ) > "$script" || fail "could not render native transport"
  FM_EXPECTED_VALUE="$value" FM_EXPECTED_LOCATION="$native_dir" \
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$native_script" \
    || fail "native PowerShell/Bash transport round trip"
  pass "native PowerShell executes literal environment, directory, and Bash launch commands"
}

test_missing_process_dependencies_refuse() {
  local fixture="$TMP_ROOT/missing-helper" out rc=0
  mkdir -p "$fixture/bin"
  cp "$ROOT/bin/fm-session-lock-lib.sh" "$ROOT/bin/fm-cursor-lib.sh" "$fixture/bin/"
  out=$(bash -c '. "$1"' _ "$fixture/bin/fm-session-lock-lib.sh" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "missing Bash process helper was accepted"
  assert_contains "$out" fm-platform-process-lib.sh "missing Bash helper diagnostic"
  fm_test_install_process_module "$fixture" || fail "could not install missing-helper fixture"
  rm "$fixture/bin/platform/windows-process.ps1"
  PROCESS_MODULE="$fixture/bin/platform/process.mjs" node --input-type=module <<'JS' \
    || fail "missing native helper used a legacy fallback"
import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { pathToFileURL } from "node:url";
Object.defineProperty(process, "platform", { value: "win32" });
let calls = 0;
childProcess.spawnSync = () => { calls++; throw new Error("native call without helper"); };
process.kill = () => { calls++; throw new Error("signal without helper"); };
syncBuiltinESMExports();
const mod = await import(pathToFileURL(process.env.PROCESS_MODULE));
for (const operation of [mod.signalWatchArmProcess, mod.terminateWatchArmProcessTree]) {
  assert.throws(() => operation(713, "owned"), /process helper is missing: .*windows-process\.ps1/);
}
assert.equal(calls, 0);
JS
  pass "missing platform dependencies refuse before native calls or termination fallbacks"
}

test_native_image_lookup_keeps_cache_and_query_counts() {
  local log="$TMP_ROOT/image-calls"
  LOG="$log" bash -c '
    . "$1" || exit 1
    tasklist.exe() {
      printf "tasklist\n" >> "$LOG"
      case "$*" in
        *"PID eq 713"*) printf "\"copilot.exe\",\"713\"\n" ;;
        *"PID eq 714"*) printf "\"foreign.exe\",\"714\"\n" ;;
        *) printf "INFO: no task\n" ;;
      esac
    }
    ps() {
      [ "$*" = "-W" ] || exit 9
      printf "ps\n" >> "$LOG"
      printf "PID PPID PGID WINPID COMMAND\n715 1 715 715 C:\\\\Tools\\\\copilot.exe\n"
    }
    fm_copilot_windows_pid_matches 713 || exit 1
    fm_copilot_windows_pid_matches 713 || exit 1
    ! fm_copilot_windows_pid_matches 714 || exit 1
    ! fm_copilot_windows_pid_matches 714 || exit 1
    fm_copilot_windows_pid_matches 715 || exit 1
    fm_copilot_windows_pid_matches 715 || exit 1
    ! fm_copilot_windows_pid_matches "713; exit" || exit 1
  ' _ "$ROOT/bin/fm-session-lock-lib.sh" || fail "native image lookup behavior changed"
  [ "$(cat "$log")" = "$(printf 'tasklist\ntasklist\ntasklist\nps')" ] \
    || fail "native image lookup introduced extra calls: $(cat "$log")"
  pass "Copilot preserves per-process single-PID caching and only scans after a missing tasklist row"
}

test_tracked_process_dependency_layouts() {
  local seed="$TMP_ROOT/seed" layout git_root node_layout
  fm_git_identity
  fm_git_init_commit "$seed" || fail "could not initialize process layout fixture"
  fm_test_install_process_module "$seed" || fail "could not install process layout dependencies"
  mkdir -p "$seed/.pi/extensions/lib" "$seed/.opencode/plugins/lib"
  cp "$ROOT/.pi/extensions/lib/fm-process-ancestry.ts" "$seed/.pi/extensions/lib/"
  cp "$ROOT/.opencode/plugins/lib/fm-process-ancestry.js" "$seed/.opencode/plugins/lib/"
  cp "$ROOT/.opencode/plugins/package.json" "$seed/.opencode/plugins/"
  cp "$ROOT/.gitattributes" "$seed/"
  git -C "$seed" add .gitattributes || fail "could not stage process layout attributes"
  git -C "$seed" add bin .pi .opencode || fail "could not stage process layout"
  git -C "$seed" commit -qm 'process fixture' || fail "could not commit process layout"
  git_root=$TMP_ROOT
  case "${OS:-}" in
    Windows_NT) git_root=$(cygpath -m "$TMP_ROOT") || fail "could not convert Git fixture path" ;;
  esac
  git clone -q "$seed" "$git_root/clone [literal] & space" || fail "could not clone process fixture"
  git -C "$seed" worktree add -q --detach "$git_root/worktree [literal] & space" \
    || fail "could not create process worktree fixture"
  for layout in "$TMP_ROOT/clone [literal] & space" "$TMP_ROOT/worktree [literal] & space"; do
    node_layout=$layout
    case "${OS:-}" in
      Windows_NT) node_layout=$(cygpath -w "$layout") || fail "could not convert native layout path" ;;
    esac
    PROCESS_LAYOUT="$node_layout" node --input-type=module <<'JS' \
      || fail "tracked process layout could not execute: $layout"
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { join } from "node:path";
const root = process.env.PROCESS_LAYOUT;
const pi = await import(pathToFileURL(join(root, ".pi/extensions/lib/fm-process-ancestry.ts")));
const opencode = await import(pathToFileURL(join(root, ".opencode/plugins/lib/fm-process-ancestry.js")));
assert.equal(pi.isPidInCurrentAncestry, opencode.isPidInCurrentAncestry);
assert.equal(pi.isPidInCurrentAncestry(String(process.pid)), true);
assert.equal(pi.pidAlive(String(process.pid)), true);
assert.equal(pi.isPidInCurrentAncestry(String(pi.shellVisibleProcessPid())), true);
if (process.platform === "win32") {
  assert.equal(opencode.signalWatchArmProcess(2147483647, `missing-${process.pid}`), false);
}
JS
    bash -c '
      . "$1/bin/fm-platform-process-lib.sh" || exit 1
      fm_platform_windows_environment_command FM_FIXTURE literal
    ' _ "$layout" >/dev/null || fail "tracked Bash transport dependency was missing"
  done
  pass "fresh clones and worktree-shaped homes execute both wrappers and tracked native dependencies"
}

# Reproduce Git-for-Windows exec replacing a native parent while MSYS retains
# the logical child. Only Herdr's transport is a fixture; processes and both
# process tables are real, and the normal recovery-grade classifier is exercised.
test_windows_exec_worker_keeps_pane_ancestry() (
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) return 0 ;;
  esac
  local dir="$TMP_ROOT/exec-ancestry" worker='' fixture_shell_native agent_pid ancestors observed
  mkdir -p "$dir"
  cp "$(type -P node)" "$dir/copilot.exe" || fail "could not prepare native process fixture"
  cat > "$dir/agent.cjs" <<'JS'
const fs = require("node:fs");
fs.writeFileSync(process.env.FM_NATIVE_TEST_PID_FILE, String(process.pid));
let remaining = 600;
setInterval(() => {
  if (fs.existsSync(process.env.FM_NATIVE_TEST_STOP_FILE) || --remaining === 0) process.exit(0);
}, 100);
JS
  cat > "$dir/launch.sh" <<'SH'
#!/usr/bin/env bash
# Keep the pane shell resident, just as PowerShell's Bash child remains in a
# real spawn. The env execs still replace intermediate native process IDs.
env -u FM_UNUSED_PARENT env -u FM_UNUSED_AGENT "$FM_NATIVE_TEST_AGENT" "$(printf '%s' "$FM_NATIVE_TEST_SCRIPT")"
exit "$?"
SH
  trap 'touch "$dir/stop"; [ -z "$worker" ] || wait "$worker" || true' EXIT
  FM_NATIVE_TEST_AGENT="$(cygpath -m "$dir/copilot.exe")" \
    FM_NATIVE_TEST_SCRIPT="$(cygpath -m "$dir/agent.cjs")" \
    FM_NATIVE_TEST_PID_FILE="$(cygpath -m "$dir/pid")" \
    FM_NATIVE_TEST_STOP_FILE="$(cygpath -m "$dir/stop")" \
    bash "$dir/launch.sh" > "$dir/output" 2>&1 &
  worker=$!
  for _ in $(seq 1 100); do
    [ -s "$dir/pid" ] && break
    sleep 0.1
  done
  [ -s "$dir/pid" ] || fail "native exec worker did not start"
  fixture_shell_native=$(cat "/proc/$worker/winpid") || fail "pane shell lost its native identity"
  agent_pid=$(cat "$dir/pid")
  # shellcheck source=bin/backends/herdr.sh
  . "$ROOT/bin/backends/herdr.sh"
  ancestors=$(_fm_platform_windows_process_query parent-processes "$agent_pid") \
    || fail "could not inspect the worker's native ancestry"
  if printf '%s\n' "$ancestors" | cut -f1 | grep -qx "$fixture_shell_native"; then
    fail "fixture did not break native ancestry across env exec"
  fi
  fm_backend_herdr_cli() {
    case "$2 $3" in
      'pane get') printf '%s\n' '{"result":{"type":"pane_info","pane":{"pane_id":"w1:p1"}}}' ;;
      'agent get') printf '%s\n' '{"error":{"code":"agent_not_found"}}'; return 1 ;;
      'pane process-info')
        jq -cn --argjson pid "$fixture_shell_native" '{result:{type:"pane_process_info",process_info:{pane_id:"w1:p1",shell_pid:$pid,foreground_processes:[{pid:$pid,name:"bash.exe",argv0:"bash.exe",cmdline:"bash.exe"}]}}}' ;;
      'status --json') printf '%s\n' '{"server":{"running":true}}' ;;
      *) return 1 ;;
    esac
  }
  observed=$(fm_backend_herdr_agent_state fixture:w1:p1)
  assert_equals alive "$observed" "a live Windows exec worker must not become a dead pane"
  pass "native exec workers retain pane liveness despite broken Windows parent links"
)

# Exercise the actual PowerShell interface with a deterministic CIM provider.
# Unlike the portable Bash fixtures, this pins snapshot traversal, PID reuse,
# formatting and error distinctions inside the native implementation itself.
test_native_process_facts_validate_ancestry_and_queries() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) return 0 ;;
  esac
  local dir="$TMP_ROOT/native-facts" probe helper input log out rc before
  mkdir -p "$dir"
  cat > "$dir/probe.ps1" <<'PS'
param([string]$Helper, [string]$Operation, [string]$MsysPs = "")
function Get-CimInstance {
    param([string]$ClassName, [string]$Filter, [int]$OperationTimeoutSec)
    Add-Content -LiteralPath $env:FM_NATIVE_TEST_LOG -Value "$ClassName|$Filter|$OperationTimeoutSec"
    if ($env:FM_NATIVE_TEST_FAIL -eq '1') { throw 'simulated native query failure' }
    $rows = Get-Content -LiteralPath $env:FM_NATIVE_TEST_INPUT -Raw | ConvertFrom-Json
    foreach ($row in $rows) {
        if ($row.CreationDate) { $row.CreationDate = [datetime]$row.CreationDate }
    }
    if ($Filter) {
        if ($Filter -notmatch '^ProcessId = ([0-9]+)$') { throw 'unsafe native PID filter' }
        return @($rows | Where-Object { $_.ProcessId -eq [int]$Matches[1] })
    }
    $rows
}
& $Helper $Operation -MsysPs $MsysPs
exit $LASTEXITCODE
PS
  cat > "$dir/input.json" <<'JSON'
[
  {"ProcessId":9000,"ParentProcessId":8100,"Name":"bash.exe","ExecutablePath":"C:\\Git\\bash.exe","CommandLine":"bash.exe","CreationDate":"2026-01-03T00:00:00Z"},
  {"ProcessId":8100,"ParentProcessId":8000,"Name":"claude.exe","ExecutablePath":"C:\\Tools\\claude.exe","CommandLine":"claude.exe --note a\tb\n123\tforged.exe","CreationDate":"2026-01-02T00:00:00Z"},
  {"ProcessId":8000,"ParentProcessId":1,"Name":"powershell.exe","ExecutablePath":null,"CommandLine":"powershell.exe","CreationDate":"2026-01-01T00:00:00Z"}
]
JSON
  cp "$dir/input.json" "$dir/original.json"
  probe=$(cygpath -w "$dir/probe.ps1")
  helper=$(cygpath -w "$ROOT/bin/platform/windows-process.ps1")
  input=$(cygpath -w "$dir/input.json")
  log=$(cygpath -w "$dir/queries")
  native_facts_query() {
    FM_NATIVE_TEST_INPUT="$input" FM_NATIVE_TEST_LOG="$log" FM_PROCESS_NATIVE_PID="$2" \
      powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$probe" "$helper" "$1" "${3:-}"
  }

  out=$(native_facts_query parent-processes 9000) || fail "native parent snapshot failed"
  out=${out//$'\r'/}
  [ "$out" = "$(printf '8100\tC:/Tools/claude.exe\tclaude.exe --note a b 123 forged.exe\n8000\tpowershell.exe\tpowershell.exe')" ] \
    || fail "native rows lost parent order or allowed command-line row injection: $out"
  [ "$(wc -l < "$dir/queries" | tr -d ' ')" = 1 ] || fail "native ancestry queried once per hop"
  out=$(native_facts_query process-info 8100) || fail "native single-PID lookup failed"
  out=${out//$'\r'/}
  [ "$out" = "$(printf '8100\tC:/Tools/claude.exe\tclaude.exe --note a b 123 forged.exe')" ] \
    || fail "native single-PID lookup changed identity fields"

  rc=0
  out=$(native_facts_query process-info 7777) || rc=$?
  expect_code 3 "$rc" "missing native PID must be distinguished from query failure"
  [ -z "$out" ] || fail "absent native PID printed process facts"
  rc=0
  out=$(FM_NATIVE_TEST_FAIL=1 native_facts_query process-info 8100) || rc=$?
  expect_code 2 "$rc" "failed native query must be uncertainty, not death"
  [ -z "$out" ] || fail "failed native query printed process facts"
  before=$(wc -l < "$dir/queries" | tr -d ' ')
  rc=0
  out=$(native_facts_query process-info '8100; exit 0') || rc=$?
  expect_code 2 "$rc" "invalid native PID must be rejected before querying"
  [ "$(wc -l < "$dir/queries" | tr -d ' ')" = "$before" ] || fail "invalid PID reached the native query"

  jq '.[1].CreationDate = "2026-01-04T00:00:00Z"' "$dir/original.json" > "$dir/input.json"
  out=$(native_facts_query parent-processes 9000) || fail "reused-parent detection failed"
  [ -z "$out" ] || fail "a reused parent PID was included in native ancestry"
  jq 'map(select(.ProcessId != 8100))' "$dir/original.json" > "$dir/input.json"
  out=$(native_facts_query parent-processes 9000) || fail "orphaned native root was not handled"
  [ -z "$out" ] || fail "a missing parent was replaced by an unrelated native process"
  jq '.[1].ParentProcessId = 9000' "$dir/original.json" > "$dir/input.json"
  rc=0
  out=$(native_facts_query parent-processes 9000) || rc=$?
  expect_code 2 "$rc" "a cyclic native snapshot must refuse"
  [ -z "$out" ] || fail "cyclic snapshot leaked partial trusted ancestry"
  rc=0
  out=$(native_facts_query parent-processes 7777) || rc=$?
  expect_code 2 "$rc" "an absent native root is not a successful empty ancestry"

  jq -n '[range(0;20) | {ProcessId:(1000+.),ParentProcessId:(1001+.),Name:"bash.exe",ExecutablePath:null,CommandLine:"bash.exe",CreationDate:"2026-01-01T00:00:00Z"}]' > "$dir/input.json"
  out=$(native_facts_query parent-processes 1000) || fail "bounded native ancestry failed"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 16 ] || fail "native ancestry exceeded its depth bound"
  cp "$dir/original.json" "$dir/input.json"
  before=$(wc -l < "$dir/queries" | tr -d ' ')
  out=$(native_facts_query descendant-processes 8000) || fail "native descendant snapshot failed"
  out=${out//$'\r'/}
  [ "$(printf '%s\n' "$out" | cut -f1)" = $'8000\n8100\n9000' ] || fail "native descendant traversal lost the owned chain"
  printf '%s\n' "$out" | awk -F '\t' 'NF < 4 || $2 !~ /^[0-9]+$/ {bad=1} END {exit bad ? 1 : 0}' \
    || fail "native descendants did not carry birth identity and sanitized fields"
  [ "$(wc -l < "$dir/queries" | tr -d ' ')" -eq "$((before + 1))" ] || fail "native descendants queried per process"
  jq '.[1].CreationDate = "2026-01-04T00:00:00Z"' "$dir/original.json" > "$dir/input.json"
  out=$(native_facts_query descendant-processes 8100) || fail "reused descendant-parent proof failed"
  [ "$(printf '%s\n' "$out" | cut -f1)" = 8100 ] || fail "an old child was attached to a reused native parent"
  jq '.[0].CreationDate = null' "$dir/original.json" > "$dir/input.json"
  rc=0
  out=$(native_facts_query descendant-processes 8000) || rc=$?
  expect_code 2 "$rc" "missing descendant birth identity must be uncertainty"
  [ -z "$out" ] || fail "incomplete descendant proof leaked partial rows"
  jq -n '[range(0;4100) | {ProcessId:(10000+.),ParentProcessId:(if . == 0 then 1 else 10000 end),Name:"bash.exe",ExecutablePath:null,CommandLine:"bash.exe",CreationDate:"2026-01-01T00:00:00Z"}]' > "$dir/input.json"
  rc=0
  out=$(native_facts_query descendant-processes 10000) || rc=$?
  expect_code 2 "$rc" "a truncated descendant set cannot prove absence"
  [ -z "$out" ] || fail "bounded descendant failure leaked a successful prefix"
  pass "native process facts use one bounded snapshot, sanitize rows, reject reused parents, and distinguish missing PIDs from query errors"

  cat > "$dir/msys.ps1" <<'PS'
if ($args.Count -ne 2 -or $args[0] -cne '-e' -or $args[1] -cne '-l') { exit 9 }
Get-Content -LiteralPath $env:FM_NATIVE_TEST_MSYS
if ($env:FM_NATIVE_TEST_MSYS_FAIL -eq '1') { exit 1 }
exit 0
PS
  cat > "$dir/msys.txt" <<'ROWS'
      PID    PPID    PGID     WINPID   TTY         UID    STIME COMMAND
       81       1      81       8100  cons0       4096 00:00:00 /usr/bin/bash
       90      81      81       9000  cons0       4096 00:00:00 /tools/copilot
     8000       1    8000       9100  cons0       4096 00:00:00 /usr/bin/bash
       94    8000    8000       9400  cons0       4096 00:00:00 /tools/copilot
ROWS
  cat > "$dir/input.json" <<'JSON'
[
  {"ProcessId":8000,"ParentProcessId":1,"Name":"powershell.exe","CreationDate":"2026-01-01T00:00:00Z"},
  {"ProcessId":8100,"ParentProcessId":8000,"Name":"bash.exe","CreationDate":"2026-01-02T00:00:00Z"},
  {"ProcessId":8200,"ParentProcessId":8300,"Name":"env.exe","CreationDate":"2026-01-03T00:00:00Z"},
  {"ProcessId":9000,"ParentProcessId":8200,"Name":"copilot.exe","CreationDate":"2026-01-04T00:00:00Z"},
  {"ProcessId":9200,"ParentProcessId":9000,"Name":"node.exe","CreationDate":"2026-01-05T00:00:00Z"},
  {"ProcessId":9100,"ParentProcessId":1,"Name":"bash.exe","CreationDate":"2026-01-02T00:00:00Z"},
  {"ProcessId":9400,"ParentProcessId":9100,"Name":"copilot.exe","CreationDate":"2026-01-04T00:00:00Z"}
]
JSON
  cp "$dir/input.json" "$dir/exec.json"
  export FM_NATIVE_TEST_MSYS
  FM_NATIVE_TEST_MSYS=$(cygpath -w "$dir/msys.txt")
  local msys_probe
  msys_probe=$(cygpath -w "$dir/msys.ps1")
  out=$(native_facts_query descendant-processes 8000) || fail "native-only counterfactual failed"
  [ "$(printf '%s\n' "$out" | cut -f1)" = $'8000\n8100' ] || fail "native-only fixture did not lose the exec worker"
  before=$(wc -l < "$dir/queries" | tr -d ' ')
  out=$(native_facts_query descendant-processes 8000 "$msys_probe") || fail "MSYS exec bridge failed"
  [ "$(printf '%s\n' "$out" | cut -f1 | sort -n)" = $'8000\n8100\n9000\n9200' ] \
    || fail "exec bridge lost the worker or borrowed a foreign process with a colliding logical PID: $out"
  [ "$(wc -l < "$dir/queries" | tr -d ' ')" -eq "$((before + 1))" ] || fail "exec bridge queried CIM per process"

  jq '.[3].ParentProcessId = 8100' "$dir/exec.json" > "$dir/input.json"
  out=$(native_facts_query descendant-processes 8000 "$msys_probe") || fail "agreeing native and MSYS edges failed"
  [ "$(printf '%s\n' "$out" | cut -f1 | sort -n)" = $'8000\n8100\n9000\n9200' ] \
    || fail "the same process was counted twice through native and logical parents"
  jq '.[1].CreationDate = "2026-01-06T00:00:00Z"' "$dir/exec.json" > "$dir/input.json"
  out=$(native_facts_query descendant-processes 8000 "$msys_probe") || fail "MSYS reused-parent check failed"
  [ "$(printf '%s\n' "$out" | cut -f1)" = $'8000\n8100' ] || fail "an old MSYS child attached to a reused native parent"
  jq '.[3].CreationDate = "2100-01-01T00:00:00Z"' "$dir/exec.json" > "$dir/input.json"
  rc=0
  out=$(native_facts_query descendant-processes 8000 "$msys_probe") || rc=$?
  expect_code 2 "$rc" "a native PID born after the MSYS observation cannot authenticate that mapping"
  [ -z "$out" ] || fail "racing PID mapping leaked partial absence evidence"
  jq '.[3].CreationDate = null' "$dir/exec.json" > "$dir/input.json"
  rc=0
  out=$(native_facts_query descendant-processes 8000 "$msys_probe") || rc=$?
  expect_code 2 "$rc" "an MSYS edge needs the child's native creation identity"
  [ -z "$out" ] || fail "missing MSYS child identity leaked partial rows"
  jq 'map(select(.ProcessId != 9000))' "$dir/exec.json" > "$dir/input.json"
  rc=0
  out=$(native_facts_query descendant-processes 8000 "$msys_probe") || rc=$?
  expect_code 2 "$rc" "a reachable MSYS child missing from CIM may be mid-exec, not absent"
  [ -z "$out" ] || fail "missing MSYS child leaked partial absence evidence"
  cp "$dir/exec.json" "$dir/input.json"
  rc=0
  out=$(FM_NATIVE_TEST_MSYS_FAIL=1 native_facts_query descendant-processes 8000 "$msys_probe") || rc=$?
  expect_code 2 "$rc" "a failed MSYS query is not native-only proof of absence"
  [ -z "$out" ] || fail "failed MSYS query leaked a successful prefix"
  for malformed in \
    'PID PPID PGID' \
    $'PID PPID PGID WINPID\n81 1 81 8100 ?\n81 1 81 9000 ?' \
    $'PID PPID PGID WINPID\n81 1 81 8100 ?\n90 81 81 8100 ?'; do
    printf '%s\n' "$malformed" > "$dir/msys.txt"
    rc=0
    out=$(native_facts_query descendant-processes 8000 "$msys_probe") || rc=$?
    expect_code 2 "$rc" "malformed or ambiguous MSYS identity must refuse"
    [ -z "$out" ] || fail "malformed MSYS identity leaked partial rows"
  done
  printf 'PID PPID PGID WINPID\n81 90 81 8100 ?\n90 81 81 9000 ?\n' > "$dir/msys.txt"
  jq '.[1].CreationDate = "2026-01-04T00:00:00Z"' "$dir/exec.json" > "$dir/input.json"
  rc=0
  out=$(native_facts_query descendant-processes 8000 "$msys_probe") || rc=$?
  expect_code 2 "$rc" "cyclic logical ancestry cannot authenticate ownership"
  [ -z "$out" ] || fail "cyclic MSYS identity leaked partial rows"
  unset FM_NATIVE_TEST_MSYS
  pass "MSYS exec ancestry uses exact live native identities, deduplicates paths, and rejects foreign, reused, racing, cyclic, or unreadable evidence"
}

# A native argv recorder models the exact MSYS -> herdr.exe boundary. A Bash
# fake alone cannot expose rewriting of /exit and other slash-prefixed input.
test_herdr_windows_preserves_literal_agent_input() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) return 0 ;;
  esac
  local dir="$TMP_ROOT/native-herdr-input" recorder log native_dir
  mkdir -p "$dir"
  recorder=$(cygpath -w "$dir/record.cjs")
  log=$(cygpath -w "$dir/argv.jsonl")
  native_dir=$(cygpath -w "$dir")
  cat > "$dir/record.cjs" <<'JS'
if (process.argv[2] === "status") {
  console.log(JSON.stringify({ server: { running: true } }));
} else {
  require("node:fs").appendFileSync(process.env.FM_NATIVE_ARGV_LOG, JSON.stringify(process.argv.slice(2)) + "\n");
}
JS
  # shellcheck disable=SC2016 # Expansion belongs to the fixture's Bash process.
  env -u MSYS_NO_PATHCONV -u MSYS2_ARG_CONV_EXCL FM_NATIVE_RECORDER="$recorder" \
    FM_NATIVE_ARGV_LOG="$log" bash -c '
    . "$1/bin/backends/herdr.sh" || exit 1
    herdr() { node "$FM_NATIVE_RECORDER" "$@"; }
    fm_backend_herdr_send_literal "fixture:w1:p1" /exit || exit 1
    fm_backend_herdr_send_text_line "fixture:w1:p1" /bearings || exit 1
    fm_backend_herdr_cli fixture agent prompt w1:p1 /skill || exit 1
    fm_backend_herdr_cli fixture workspace create --cwd "$2" --no-focus || exit 1
  ' _ "$ROOT" "$dir" || fail "native Herdr argument transport failed"
  FM_NATIVE_ARGV_LOG="$log" FM_NATIVE_EXPECTED_DIR="$native_dir" node <<'JS' \
    || fail "MSYS rewrote agent input or lost normal cwd conversion"
const assert = require("node:assert/strict");
const rows = require("node:fs").readFileSync(process.env.FM_NATIVE_ARGV_LOG, "utf8").trim().split(/\r?\n/).map(JSON.parse);
assert.deepEqual(rows[0], ["pane", "send-text", "w1:p1", "/exit", "--session", "fixture"]);
assert.deepEqual(rows[1], ["pane", "run", "w1:p1", "/bearings", "--session", "fixture"]);
assert.deepEqual(rows[2], ["agent", "prompt", "w1:p1", "/skill", "--session", "fixture"]);
const cwd = rows[3][rows[3].indexOf("--cwd") + 1];
assert.equal(cwd.replaceAll("\\", "/").toLowerCase(), process.env.FM_NATIVE_EXPECTED_DIR.replaceAll("\\", "/").toLowerCase());
JS
  pass "Herdr Windows transport preserves slash commands while retaining cwd path conversion"
}

fm_test_run_cases \
  test_windows_exec_worker_keeps_pane_ancestry \
  test_herdr_windows_preserves_literal_agent_input \
  test_native_process_facts_validate_ancestry_and_queries \
  test_process_compatibility_contracts \
  test_process_facts_preserve_proc_and_ps \
  test_transport_preserves_literal_data \
  test_native_transport_round_trip \
  test_missing_process_dependencies_refuse \
  test_native_image_lookup_keeps_cache_and_query_counts \
  test_tracked_process_dependency_layouts

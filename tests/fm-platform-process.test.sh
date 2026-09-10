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

fm_test_run_cases \
  test_process_compatibility_contracts \
  test_process_facts_preserve_proc_and_ps \
  test_transport_preserves_literal_data \
  test_native_transport_round_trip \
  test_missing_process_dependencies_refuse \
  test_native_image_lookup_keeps_cache_and_query_counts \
  test_tracked_process_dependency_layouts

#!/usr/bin/env bash
# Characterize the existing pilot consumers before moving their implementation.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/harness-helpers.sh
. "$ROOT/tests/harness-helpers.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-control-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-session-lock-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-harness-contract)

test_pilot_control_and_busy_contracts() {
  local harness key exit_command source
  while IFS='|' read -r harness key exit_command source; do
    fm_control_harness_supported "$harness" || fail "$harness control support"
    fm_control_harness_supports_kind "$harness" secondmate || fail "$harness secondmate support"
    assert_equals "$key" "$(fm_control_interrupt_key "$harness")" "$harness interrupt"
    assert_equals 1 "$(fm_control_interrupt_repeat "$harness")" "$harness interrupt count"
    assert_equals '' "$(fm_control_interrupt_clear_key "$harness")" "$harness composer clear"
    assert_equals none "$(fm_control_interrupt_ack_source "$harness")" "$harness acknowledgement"
    assert_equals "$exit_command" "$(fm_control_exit_command "$harness")" "$harness exit"
    assert_equals "$source fm-spawn fm-interrupt fm-recovery" \
      "$(fm_busy_sources_for_harness "$harness")" "$harness trusted busy sources"
  done <<'EOF'
copilot|C-c|/exit|copilot-hook
pi|Escape|/quit|pi-ext
claude|Escape|/exit|claude-hook
pi-signed|Escape|/quit|pi-ext
omp|Escape|/quit|omp-ext
EOF
  ! fm_control_harness_supports_kind gemini secondmate || fail "Gemini gained secondmate support"
  ! fm_control_harness_supported unknown || fail "unknown control support"
  ! fm_control_verb_allowed resume || fail "resume gained a control contract"
  pass "pilot and nonpilot control mechanics and busy sources retain their contracts"
}

test_recorded_names_and_owned_wiring() {
  local wt="$TMP_ROOT/worktree ' [x]" state="$TMP_ROOT/state ' [x]" expected
  assert_equals copilot "$(fm_control_harness_family copilot-custom)" "raw Copilot family"
  assert_equals pi-signed "$(fm_control_harness_family pi-signed)" "signed Pi family"
  ! fm_control_harness_family pi-extra >/dev/null || fail "Pi claimed a prefix"
  ! fm_control_harness_family omp-extra >/dev/null || fail "OMP claimed a prefix"
  expected=$(printf '%s\n' "$wt/.github/hooks/zz-firstmate-task.json" "$state/task.copilot-prompt-submitted")
  assert_equals "$expected" "$(fm_control_harness_wiring_paths copilot "$wt" "$state" task)" "Copilot owned paths"
  assert_equals "$state/task.pi-ext.ts" "$(fm_control_harness_wiring_paths pi "$wt" "$state" task)" "Pi owned path"
  assert_equals "$state/task.pi-ext.ts" "$(fm_control_harness_wiring_paths pi-signed "$wt" "$state" task)" "signed Pi legacy path"
  assert_equals "$state/task.omp-ext.ts" "$(fm_control_harness_wiring_paths omp "$wt" "$state" task)" "OMP legacy path"
  assert_equals claude "$(fm_harness_path_name /claude/copilot/version)" "mixed path evidence precedence"
  pass "recorded raw names and literal owned artifacts preserve pilot and legacy distinctions"
}

test_primary_supervision_and_override_contracts() {
  local fakebin="$TMP_ROOT/supervision/bin" harness model result
  mkdir -p "$fakebin"
  fm_test_install_harness_modules "$TMP_ROOT/supervision" || fail "supervision module dependencies"
  # shellcheck disable=SC2016 # The fixture reads its subprocess environment.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$FM_TEST_HARNESS"\n' > "$fakebin/fm-harness.sh"
  chmod +x "$fakebin/fm-harness.sh"
  while IFS='|' read -r harness model; do
    result=$(FM_HOME="$TMP_ROOT/supervision/home" FM_STATE_OVERRIDE="$TMP_ROOT/supervision/home/state" \
      FM_ROOT_OVERRIDE="$ROOT" FM_SUPERVISION_MODEL='' FM_TEST_HARNESS="$harness" \
      bash -c '. "$1" || exit 1; FM_WAKE_LIB_DIR=$2; fm_supervision_model' \
      _ "$ROOT/bin/fm-wake-lib.sh" "$fakebin") || fail "$harness supervision query"
    assert_equals "$model" "$result" "$harness primary supervision"
  done <<'EOF'
copilot|autoarm
pi|extension
claude|autoarm
pi-signed|extension
omp|extension
codex|persistent
unknown|persistent
EOF
  result=$(FM_HOME="$TMP_ROOT/supervision/home" FM_STATE_OVERRIDE="$TMP_ROOT/supervision/home/state" \
    FM_ROOT_OVERRIDE="$ROOT" FM_SUPERVISION_MODEL=persistent FM_TEST_HARNESS=pi \
    bash -c '. "$1" || exit 1; FM_WAKE_LIB_DIR=$2; fm_supervision_model' \
    _ "$ROOT/bin/fm-wake-lib.sh" "$fakebin") || fail "supervision override"
  assert_equals persistent "$result" "explicit supervision override remains authoritative"
  pass "primary supervision retains the pilot, legacy, unknown, and explicit-override behavior"
}

test_closed_interface_and_identity_stages() {
  local harness result rc
  for harness in copilot pi; do
    fm_harness_registered "$harness" || fail "$harness is not registered"
    assert_equals "$(fm_control_interrupt_key "$harness")" \
      "$(fm_harness_describe "$harness" interrupt-key)" "$harness control uses the same interface"
  done
  for harness in claude pi-signed omp copilot-custom pi-extra ../copilot; do
    ! fm_harness_registered "$harness" || fail "$harness entered the pilot registry"
  done
  assert_equals pi "$(PI_CODING_AGENT=true FM_PI_HARNESS=pi fm_harness_identify pi marker)" "Pi marker"
  ! PI_CODING_AGENT=true FM_PI_HARNESS=pi-signed fm_harness_identify pi marker \
    || fail "Pi adapter claimed signed Pi"
  ! fm_harness_identify pi command pi-signed || fail "Pi command stage claimed signed Pi"
  assert_equals copilot "$(fm_harness_identify copilot command copilot.exe)" "native Copilot command"
  ! fm_harness_identify copilot command copilot-extra || fail "Copilot identity claimed a prefix"
  rc=0
  result=$(fm_harness_describe ../copilot supervision 2>&1) || rc=$?
  assert_equals 2 "$rc" "invalid adapter must fail explicitly"
  assert_contains "$result" 'not registered' "invalid adapter diagnostic"
  pass "the closed interface preserves exact registration and staged identity"
}

test_shared_backend_process_identity_keeps_pilot_boundaries() {
  local name
  # shellcheck source=bin/fm-agent-process-lib.sh
  . "$ROOT/bin/fm-agent-process-lib.sh" || fail "shared backend classifier dependencies"
  for name in copilot copilot.exe pi pi-signed omp; do
    assert_equals agent "$(fm_agent_process_classify "$name" "$name" "$name")" "$name backend identity"
  done
  for name in copilot-helper mycopilot comp; do
    assert_equals other "$(fm_agent_process_classify "$name" "$name" "$name")" "$name must not become an agent"
  done
  assert_equals shell "$(fm_agent_process_classify bash -bash -bash)" "bare shell remains agent-free"
  pass "shared backend identity preserves native Copilot, Pi, legacy names, and exact-match refusals"
}

test_preparation_keeps_executable_and_probe_contracts() {
  local fakebin="$TMP_ROOT/launch ' [x]/bin" result option rc=0
  mkdir -p "$fakebin"
  printf '#!/usr/bin/env bash\nprintf "Options: --help --tui-mode <mode>\\n"\n' > "$fakebin/pi"
  printf '#!/usr/bin/env bash\nexit 9\n' > "$fakebin/copilot"
  chmod +x "$fakebin/pi" "$fakebin/copilot"
  PATH="$fakebin:$PATH" fm_harness_prepare_launch pi ship '__PIBIN____PITUIMODE__ __MODELFLAG__' \
    || fail "Pi executable preparation"
  assert_equals "$fakebin/pi" "$FM_HARNESS_EXECUTABLE" "literal selected Pi executable"
  assert_equals 'FM_PI_HARNESS=pi __PIBIN__ --tui-mode regular __MODELFLAG__' \
    "$FM_HARNESS_LAUNCH" "Pi regular TUI and marker preparation"
  PATH="$fakebin:$PATH" fm_harness_prepare_launch copilot secondmate 'copilot --raw' \
    || fail "Copilot should resolve without invoking the CLI"
  assert_equals 'copilot --raw' "$FM_HARNESS_LAUNCH" "raw Copilot launch"
  assert_equals "$fakebin/copilot" "$FM_HARNESS_EXECUTABLE" "selected Copilot executable"
  option=$(fm_harness_describe pi effort-option codex-native/model ultra) || fail "native Pi effort"
  assert_equals --codex-effort "$option" "native Pi effort flag"
  option=$(fm_harness_describe pi effort-option other/model max) || fail "ordinary Pi effort"
  assert_equals --thinking "$option" "ordinary Pi effort flag"
  ! fm_harness_describe pi effort-option other/model ultra >/dev/null 2>&1 \
    || fail "Pi accepted native effort for a different provider"
  result=$(fm_harness_owned_wiring copilot parent-environment "state ' [x]" task generation) \
    || fail "parent wiring rendering"
  assert_equals "FM_COPILOT_PARENT_STATE='state '\\'' [x]' FM_COPILOT_PARENT_TASK_ID='task' FM_COPILOT_PARENT_BUSY_GEN='generation'" \
    "$result" "literal parent bindings"
  PATH="$TMP_ROOT/absent-executables" fm_harness_prepare_launch pi ship '__PIBIN__' \
    >"$TMP_ROOT/absent-executable.log" 2>&1 || rc=$?
  assert_equals 1 "$rc" "missing executable refusal"
  assert_equals '' "$FM_HARNESS_LAUNCH$FM_HARNESS_EXECUTABLE$FM_HARNESS_EXECUTABLE_TOKEN" \
    "failed preparation must not expose a previous launch"
  pass "launch preparation preserves raw commands, literal executables, native effort, and parent bindings"
}

test_missing_or_broken_adapter_refuses() {
  local fixture="$TMP_ROOT/missing-adapter" out rc
  fm_test_install_harness_modules "$fixture" || fail "missing-adapter fixture installation"
  rm "$fixture/bin/harnesses/copilot.sh"
  rc=0
  out=$(bash -c '. "$1" || exit $?; fm_harness_describe copilot supervision' \
    _ "$fixture/bin/fm-harness-lib.sh" 2>&1) || rc=$?
  assert_equals 2 "$rc" "missing adapter refuses instead of taking a legacy path"
  assert_contains "$out" 'copilot.sh' "missing adapter diagnostic"
  printf '#!/usr/bin/env bash\nfm_harness_copilot_describe() { printf fake; }\n' \
    > "$fixture/bin/harnesses/copilot.sh"
  rc=0
  out=$(bash -c '. "$1" || exit $?; fm_harness_describe copilot supervision' \
    _ "$fixture/bin/fm-harness-lib.sh" 2>&1) || rc=$?
  assert_equals 2 "$rc" "incomplete adapter refuses"
  assert_contains "$out" 'missing identify' "incomplete adapter diagnostic"
  rc=0
  out=$(bash -c '. "$1" || exit $?; . "$2"' \
    _ "$ROOT/bin/fm-harness-lib.sh" "$fixture/bin/fm-harness-lib.sh" 2>&1) || rc=$?
  assert_equals 2 "$rc" "another root must not inherit previously loaded adapter functions"
  assert_contains "$out" 'missing identify' "alternate-root adapter diagnostic"
  cp "$ROOT/bin/fm-harness.sh" "$ROOT/bin/fm-session-lock-lib.sh" \
    "$ROOT/bin/fm-cursor-lib.sh" "$ROOT/bin/fm-gemini-lib.sh" "$fixture/bin/"
  rc=0
  out=$(CLAUDECODE=1 bash "$fixture/bin/fm-harness.sh" 2>&1) || rc=$?
  assert_equals 2 "$rc" "the real detector must not bypass a broken adapter via a legacy marker"
  assert_contains "$out" 'missing identify' "real detector load failure"
  cp "$ROOT/bin/fm-agent-process-lib.sh" "$fixture/bin/"
  rc=0
  out=$(bash -c '. "$1" || exit $?; fm_agent_process_classify_name copilot' \
    _ "$fixture/bin/fm-agent-process-lib.sh" 2>&1) || rc=$?
  assert_equals 2 "$rc" "backend identity must not hide an adapter load failure"
  assert_contains "$out" 'missing identify' "shared classifier load failure"
  pass "missing and incomplete registered adapters fail explicitly before dispatch"
}

test_invalid_interface_calls_are_explicit() {
  local operation out rc
  for operation in describe identify prepare_launch owned_wiring; do
    rc=0
    out=$("fm_harness_$operation" 2>&1) || rc=$?
    assert_equals 2 "$rc" "$operation missing adapter"
    assert_contains "$out" 'error: harness adapter' "$operation diagnostic"
    rc=0
    out=$("fm_harness_$operation" pi 2>&1) || rc=$?
    assert_equals 2 "$rc" "$operation missing context"
    assert_contains "$out" 'error: harness adapter' "$operation context diagnostic"
  done
  for operation in 'copilot render' 'pi render' 'copilot parent-environment'; do
    rc=0
    out=$(fm_harness_owned_wiring "${operation%% *}" "${operation#* }" 2>&1) || rc=$?
    assert_equals 2 "$rc" "$operation missing wiring arguments"
    assert_contains "$out" 'requires' "$operation argument diagnostic"
  done
  fm_harness_describe copilot remote-supported launch || fail "Copilot remote launch"
  ! fm_harness_describe copilot remote-supported relaunch || fail "Copilot remote relaunch was broadened"
  fm_harness_describe pi remote-supported launch || fail "Pi remote launch"
  fm_harness_describe pi remote-supported relaunch || fail "Pi remote relaunch"
  pass "malformed calls diagnose instead of shell errors, and operation-specific support stays distinct"
}

test_supervision_does_not_hide_adapter_load_errors() {
  local fixture="$TMP_ROOT/supervision-error" out rc=0
  mkdir -p "$fixture/bin"
  cp "$ROOT/bin/fm-wake-lib.sh" "$fixture/bin/"
  printf '#!/usr/bin/env bash\nexit 2\n' > "$fixture/bin/fm-harness.sh"
  chmod +x "$fixture/bin/fm-harness.sh"
  out=$(FM_SUPERVISION_MODEL='' bash -c '. "$1"; fm_supervision_model' \
    _ "$fixture/bin/fm-wake-lib.sh" 2>&1) || rc=$?
  assert_equals 2 "$rc" "supervision must not reinterpret a broken adapter as unknown"
  assert_contains "$out" 'could not load the primary harness adapter' "supervision failure diagnostic"
  out=$(FM_SUPERVISION_MODEL=extension bash -c '. "$1"; fm_supervision_model' \
    _ "$fixture/bin/fm-wake-lib.sh") || fail "explicit supervision override"
  assert_equals extension "$out" "override remains authoritative before detection"
  pass "supervision preserves explicit overrides without hiding adapter-load failures"
}

test_pi_rendered_wiring_preserves_literal_arguments() {
  local ext="$TMP_ROOT/literal-pi.ts" native_ext root state turnend context
  root=$'root " \' [x] \\\\ \001 line\nnext'
  state=$'state " \' [x] \\\\ line\nnext'
  turnend=$'notification " \' [x] \\\\ line\nnext'
  fm_harness_owned_wiring pi render "$root" "$state" task generation "$turnend" > "$ext" \
    || fail "literal Pi extension rendering"
  native_ext=$ext
  if command -v cygpath >/dev/null 2>&1; then native_ext=$(cygpath -w "$ext"); fi
  context=$(jq -nc --arg root "$root" --arg state "$state" --arg turnend "$turnend" \
    '{root:$root,state:$state,turnend:$turnend}')
  EXT_PATH="$native_ext" EXPECTED_CONTEXT="$context" node --input-type=module <<'JS' \
    || fail "rendered Pi wiring changed literal arguments or event semantics"
import assert from "node:assert/strict";
import cp from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { pathToFileURL } from "node:url";
const context = JSON.parse(process.env.EXPECTED_CONTEXT);
const calls = [];
Date.now = () => 2000;
cp.execFile = (file, args, callback) => {
  calls.push({ file, args });
  callback?.(null, "", "");
};
syncBuiltinESMExports();
const handlers = {};
const register = (name, fn) => { handlers[name] = fn; };
const extension = await import(pathToFileURL(process.env.EXT_PATH).href);
extension.default({ on: register, events: { on: register } });
const eventArgs = (state, event) => [
  `${context.root}/bin/fm-busy-event.sh`, "apply", context.state, "task",
  state, "--gen", "generation", "--source", "pi-ext", "--event", event,
];
await handlers.agent_start();
await handlers.agent_settled({}, { isIdle: () => false });
assert.equal(calls.length, 1, "continuing settlement must not emit idle");
await handlers.agent_settled({}, { isIdle: () => true });
handlers.turn_end();
handlers["codex-native:progress"]();
handlers["codex-native:progress"]();
assert.deepEqual(calls, [
  { file: "bash", args: eventArgs("busy", "agent-start") },
  { file: "bash", args: eventArgs("idle", "agent-settled") },
  { file: "touch", args: [context.turnend] },
  { file: "bash",
    args: [`${context.root}/bin/fm-busy-event.sh`, "progress", context.state, "task", "--gen", "generation"] },
]);
JS
  pass "the executable Pi artifact preserves literal paths, settlement, notifications, and throttled generation-bound progress"
}

test_tracked_clone_and_worktree_dependency_closure() {
  local seed="$TMP_ROOT/tracked-seed" clone="$TMP_ROOT/tracked-clone"
  local linked="$TMP_ROOT/tracked-worktree" layout out
  git -C "$ROOT" ls-files --error-unmatch bin/fm-harness-lib.sh \
    bin/harnesses/copilot.sh bin/harnesses/pi.sh >/dev/null \
    || fail "harness modules must be tracked for clone/update distribution"
  fm_test_install_harness_modules "$seed" || fail "tracked harness fixture dependencies"
  git -C "$seed" init -q || fail "tracked fixture initialization"
  git -C "$seed" add bin || fail "tracked fixture index"
  git -C "$seed" -c user.name=Tests -c user.email=tests@example.invalid \
    commit -qm 'tracked harness fixture' || fail "tracked fixture commit"
  git clone -q --no-hardlinks "$seed" "$clone" || fail "fresh fixture clone"
  git -C "$seed" worktree add -q -b linked "$linked" || fail "linked fixture worktree"
  for layout in "$clone" "$linked"; do
    out=$(bash -c '
      . "$1/bin/fm-harness-lib.sh" || exit $?
      fm_harness_describe copilot supervision
      fm_harness_describe pi supervision
      fm_harness_owned_wiring pi primary-watch "$1"
    ' _ "$layout") || fail "tracked layout could not execute the interface"
    assert_equals "$(printf 'autoarm\nextension\n%s/.pi/extensions/fm-primary-pi-watch.ts' "$layout")" \
      "$out" "tracked layout adapter execution"
  done
  pass "fresh tracked clones and linked worktrees execute the complete adapter dependency closure"
}

fm_test_run_cases \
  test_pilot_control_and_busy_contracts \
  test_recorded_names_and_owned_wiring \
  test_primary_supervision_and_override_contracts \
  test_closed_interface_and_identity_stages \
  test_shared_backend_process_identity_keeps_pilot_boundaries \
  test_preparation_keeps_executable_and_probe_contracts \
  test_missing_or_broken_adapter_refuses \
  test_invalid_interface_calls_are_explicit \
  test_supervision_does_not_hide_adapter_load_errors \
  test_pi_rendered_wiring_preserves_literal_arguments \
  test_tracked_clone_and_worktree_dependency_closure

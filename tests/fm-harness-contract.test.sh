#!/usr/bin/env bash
# Characterize the existing pilot consumers before moving their implementation.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
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
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$FM_TEST_HARNESS"\n' > "$fakebin/fm-harness.sh"
  chmod +x "$fakebin/fm-harness.sh"
  while IFS='|' read -r harness model; do
    result=$(FM_HOME="$TMP_ROOT/supervision/home" FM_STATE_OVERRIDE="$TMP_ROOT/supervision/home/state" \
      FM_ROOT_OVERRIDE="$ROOT" FM_SUPERVISION_MODEL= FM_TEST_HARNESS="$harness" \
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

fm_test_run_cases \
  test_pilot_control_and_busy_contracts \
  test_recorded_names_and_owned_wiring \
  test_primary_supervision_and_override_contracts

#!/usr/bin/env bash
# The public control CLI owns inspection, approval binding, record publication,
# journaling, and relaunch. Backend/native/pool facts and launch delivery are
# isolated ports here; no real agent, lease, endpoint, or project is modified.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-control-recovery)
CODE="$TMP_ROOT/code"
mkdir -p "$CODE"
cp -R "$ROOT/bin" "$CODE/bin"
cat > "$CODE/bin/backends/herdr.sh" <<'SH'
# Real name classification, with fixture-only backend/native facts.
. "$FM_TEST_REAL_ROOT/bin/fm-agent-process-lib.sh"
fm_platform_windows_process_supported() { return 0; }
fm_platform_windows_descendant_processes() {
  local count=0
  [ ! -f "$FM_TEST_CASE/reads" ] || read -r count < "$FM_TEST_CASE/reads"
  count=$((count + 1))
  printf '%s\n' "$count" > "$FM_TEST_CASE/reads"
  if [ "${FM_TEST_RECOVERY_DRIFT:-0}" = 1 ] && [ "$count" -ge 3 ]; then
    printf '101\t1000\tpowershell.exe\tpowershell.exe\n102\t9000\tcopilot.exe\tcopilot.exe\n'
  else
    cat "$FM_TEST_CASE/instances"
  fi
}
fm_backend_herdr_parse_target() {
  FM_BACKEND_HERDR_SESSION=${1%%:*}
  FM_BACKEND_HERDR_PANE=${1#*:}
  [ "$FM_BACKEND_HERDR_SESSION" = fixture ]
}
fm_backend_herdr_agent_state() {
  case "$1" in
    fixture:w3:p3) cat "$FM_TEST_CASE/agent" ;;
    fixture:w2:p2) printf '%s' "${FM_TEST_CURRENT_STATE:-missing}" ;;
    fixture:w1:p1)
      if [ -f "$FM_TEST_CASE/launch-observed" ]; then
        printf 'probe\n' >> "$FM_TEST_CASE/probes"
        if [ -n "${FM_TEST_REPORT_DURING_PROBE:-}" ]; then
          printf '%s\n' "$FM_TEST_REPORT_DURING_PROBE" >> "$FM_STATE_OVERRIDE/task-a.status"
        fi
        if [ "${FM_TEST_PROBE_MODE:-}" = stuck ]; then
          # This function is already inside the real query subshell. Avoid
          # spending the fixture deadline loading another Bash executable.
          trap '' TERM
          local probe_pid child
          fm_current_pid probe_pid
          printf '%s\n' "$probe_pid" > "$FM_TEST_CASE/probe-pid"
          printf alive
          /bin/sleep 12 &
          child=$!
          printf '%s\n' "$child" > "$FM_TEST_CASE/probe-child"
          wait "$child"
          : > "$FM_TEST_CASE/probe-escaped"
          return 0
        fi
        if [ "${FM_TEST_PROBE_MODE:-}" = native-stuck ]; then
          FM_TEST_NATIVE_RECORD=$(cygpath -m "$FM_TEST_CASE/native-process.json") \
            powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
              -File "$(cygpath -w "$FM_TEST_CASE/native-probe.ps1")"
          return $?
        fi
        /bin/sleep "${FM_TEST_PROBE_DELAY:-0}"
        printf 'complete\n' >> "$FM_TEST_CASE/completed-probes"
      fi
      cat "$FM_TEST_CASE/agent"
      ;;
    *) printf unreadable ;;
  esac
}
fm_backend_herdr_server_ensure() {
  [ -z "${FM_TEST_RESTORE_STATE:-}" ] || printf '%s' "$FM_TEST_RESTORE_STATE" > "$FM_TEST_CASE/agent"
}
fm_backend_herdr_endpoint_absence_recheck() {
  fm_backend_herdr_server_ensure fixture || return 1
  fm_backend_herdr_agent_state "$1"
}
fm_backend_herdr_presentation_session_lock_path() { printf '%s/session.lock\n' "$FM_TEST_CASE"; }
fm_backend_herdr_projection_create_task() {
  [ "$HERDR_SESSION" = fixture ] && [ "$1" = "$FM_TEST_CASE/original" ] || return 1
  printf 'create\n' >> "$FM_TEST_CASE/actions"
  [ "${FM_TEST_CREATE_FAIL:-0}" != 1 ] || return 1
  FM_BACKEND_HERDR_PROJECTION_WORKSPACE_ID=w3
  FM_BACKEND_HERDR_PROJECTION_TAB_ID=w3:t3
  FM_BACKEND_HERDR_PROJECTION_PANE_ID=w3:p3
  printf dead > "$FM_TEST_CASE/agent"
}
fm_backend_herdr_current_path() { printf '%s\n' "$FM_TEST_CASE/original"; }
fm_backend_herdr_cli() {
  case "$2 $3" in
    'pane get') printf '%s\n' '{"result":{"type":"pane_info","pane":{"pane_id":"w1:p1"}}}' ;;
    'pane process-info') printf '%s\n' '{"result":{"type":"pane_process_info","process_info":{"pane_id":"w1:p1","shell_pid":101}}}' ;;
    *) return 1 ;;
  esac
}
fm_backend_herdr_composer_state() { printf '%s' "${FM_TEST_COMPOSER:-empty}"; }
fm_backend_herdr_send_key() { printf 'key %s\n' "$2" >> "$FM_TEST_CASE/actions"; }
fm_backend_herdr_send_text_submit() {
  [ "$2" = /exit ] || return 1
  printf 'exit\n' >> "$FM_TEST_CASE/actions"
  printf dead > "$FM_TEST_CASE/agent"
  printf empty
}
SH
cat > "$CODE/bin/fm-spawn.sh" <<'SH'
#!/usr/bin/env bash
set -eu
[ "$1" = task-a ] && [ "$2" = --relaunch ] || exit 2
printf 'launch\n' >> "$FM_TEST_CASE/actions"
[ "${FM_TEST_SPAWN_FAIL:-0}" != 1 ] || exit 1
. "$FM_TEST_REAL_ROOT/bin/fm-classify-lib.sh"
boundary=$(status_launch_boundary "$FM_STATE_OVERRIDE/task-a.status" new-generation)
if [ "${FM_TEST_PROBE_MODE:-}" = ready ]; then
  printf alive > "$FM_TEST_CASE/agent"
  : > "$FM_TEST_CASE/launch-observed"
elif [ -n "${FM_TEST_PROBE_DELAY:-}${FM_TEST_PROBE_MODE:-}" ]; then
  printf dead > "$FM_TEST_CASE/agent"
  : > "$FM_TEST_CASE/launch-observed"
else
  printf alive > "$FM_TEST_CASE/agent"
fi
awk '$0 !~ /^(spawn_gen|launch_status|control_relaunch_tx)=/' "$FM_STATE_OVERRIDE/task-a.meta" > "$FM_STATE_OVERRIDE/next.meta"
printf 'spawn_gen=new-generation\nlaunch_status=%s\ncontrol_relaunch_tx=%s\n' \
  "$boundary" "$FM_CONTROL_RELAUNCH_TX" >> "$FM_STATE_OVERRIDE/next.meta"
mv "$FM_STATE_OVERRIDE/next.meta" "$FM_STATE_OVERRIDE/task-a.meta"
[ -z "${FM_TEST_LAUNCH_REPORT:-}" ] || printf '%s\n' "$FM_TEST_LAUNCH_REPORT" >> "$FM_STATE_OVERRIDE/task-a.status"
SH
chmod +x "$CODE/bin/fm-spawn.sh"

make_case() {
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/home/state" "$dir/home/data/task-a" "$dir/fakebin"
  fm_git_init_commit "$dir/project"
  git -C "$dir/project" worktree add -qb fm/task-a "$dir/original"
  git -C "$dir/project" worktree add -qb abandoned-replacement "$dir/replacement"
  printf 'unfinished original work\n' > "$dir/original/preserved.txt"
  printf 'unfinished replacement work\n' > "$dir/replacement/also-preserved.txt"
  printf '# Task\nContinue the original task.\n' > "$dir/home/data/task-a/brief.md"
  for which in original replacement; do
    pane=w1:p1; workspace=w1; tab=w1:t1
    [ "$which" != replacement ] || { pane=w2:p2; workspace=w2; tab=w2:t2; }
    file="$dir/home/data/task-a/$which.meta"
    printf 'window=fixture:%s\nendpoint_task_id=task-a\nworktree=%s\nproject=%s\nharness=copilot\nkind=ship\nmode=direct-PR\nyolo=off\nbackend=herdr\nherdr_session=fixture\nherdr_workspace_id=%s\nherdr_tab_id=%s\nherdr_pane_id=%s\nbusy_gen=%s-busy\nspawn_gen=%s-generation\n' \
      "$pane" "$dir/$which" "$dir/project" "$workspace" "$tab" "$pane" "$which" "$which" > "$file"
  done
  cp "$dir/home/data/task-a/replacement.meta" "$dir/home/state/task-a.meta"
  printf 'pr=https://github.com/example/repo/pull/42\npr_head=0123456789abcdef0123456789abcdef01234567\n' >> "$dir/home/state/task-a.meta"
  jq -n --arg original "$dir/original" --arg replacement "$dir/replacement" \
    '[{path:$original,status:"leased",lease_id:"original-lease",lease_holder:"task-a",processes:[{pid:102}]},
      {path:$replacement,status:"leased",lease_id:"replacement-lease",lease_holder:"task-a",processes:[]}]' > "$dir/pool.json"
  cat > "$dir/fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
[ "$*" = 'status --json' ] || { printf 'unexpected-pool-mutation\n' >> "$FM_TEST_CASE/actions"; exit 2; }
cat "$FM_TEST_CASE/pool.json"
SH
  chmod +x "$dir/fakebin/treehouse"
  printf alive > "$dir/agent"
  printf '101\t1000\tpowershell.exe\tpowershell.exe\n102\t1001\tcopilot.exe\tcopilot.exe\n' > "$dir/instances"
  : > "$dir/actions"
  printf '%s\n' "$dir"
}
control_cli() {
  local dir=$1; shift
  env FM_TEST_REAL_ROOT="$ROOT" FM_TEST_CASE="$dir" FM_HOME="$dir/home" \
    FM_ROOT_OVERRIDE="$CODE" FM_STATE_OVERRIDE="$dir/home/state" FM_DATA_OVERRIDE="$dir/home/data" \
    FM_CONTROL_POLL="${FM_TEST_CONTROL_POLL:-0.01}" FM_CONTROL_EXIT_WAIT=10 \
    FM_CONTROL_LAUNCH_WAIT="${FM_TEST_CONTROL_LAUNCH_WAIT:-10}" \
    PATH="$dir/fakebin:$PATH" "$CODE/bin/fm-control.sh" "$@"
}
control() {
  local dir=$1; shift
  control_cli "$dir" task-a "$@"
}
plan() { control "$1" inspect --recover-from "$1/home/data/task-a/original.meta"; }
recover() {
  control "$1" relaunch --recover-from "$1/home/data/task-a/original.meta" \
    --approve-recovery "$2" --note 'Approved original-worker recovery; preserve both copies.'
}

test_relaunch_missing_endpoint_preserves_copy() {
  local dir out
  dir=$(make_case missing-endpoint)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf 'pr=https://github.com/example/repo/pull/42\n' >> "$dir/home/state/task-a.meta"
  jq '.[0].processes=[]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json"
  printf missing > "$dir/agent"
  out=$(control "$dir" relaunch --note 'Continue the preserved task after its terminal disappeared.' 2>&1) \
    || fail "a missing terminal prevented recovery of the preserved copy: $out"
  assert_contains "$out" 'relaunched task-a' "missing-endpoint recovery did not complete"
  [ "$(cat "$dir/actions")" = $'create\nlaunch' ] || fail "missing-endpoint recovery sent exit input or duplicated launch"
  assert_grep 'window=fixture:w3:p3' "$dir/home/state/task-a.meta" "recovery did not bind the new terminal"
  assert_grep 'pr=https://github.com/example/repo/pull/42' "$dir/home/state/task-a.meta" "recovery lost PR tracking"
  assert_grep 'endpoint=fixture:w3:p3' "$dir/home/state/task-a.control-relaunch" "confirmation used the missing terminal"
  assert_grep 'phase=complete' "$dir/home/state/task-a.control-relaunch" "missing-endpoint recovery was not committed"
  assert_grep 'unfinished original work' "$dir/original/preserved.txt" "recovery discarded the original work"
  assert_grep 'unfinished replacement work' "$dir/replacement/also-preserved.txt" "recovery changed the other copy"
  pass "a missing terminal is recreated around the same dirty task-held copy without exit input"
}

test_missing_endpoint_recovery_refuses_unsafe_claims() {
  local dir variant out
  for variant in occupied foreign duplicate branch project other unreadable; do
    dir=$(make_case "missing-$variant")
    cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
    jq '.[0].processes=[]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json"
    printf missing > "$dir/agent"
    case "$variant" in
      occupied) jq '.[0].processes=[{pid:123}]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json" ;;
      foreign) jq '.[0].lease_holder="other"' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json" ;;
      duplicate) jq '. + [.[0]]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json" ;;
      branch) git -C "$dir/original" checkout -qb other-task ;;
      project) fm_git_init_commit "$dir/foreign"; sed "s|^project=.*|project=$dir/foreign|" "$dir/home/state/task-a.meta" > "$dir/next"; mv "$dir/next" "$dir/home/state/task-a.meta" ;;
      other) cp "$dir/home/state/task-a.meta" "$dir/home/state/other.meta" ;;
      unreadable) printf unreadable > "$dir/agent" ;;
    esac
    cp "$dir/home/state/task-a.meta" "$dir/before.meta"
    if out=$(control "$dir" relaunch --note 'Preserve every copy.' 2>&1); then
      fail "unsafe $variant recovery succeeded: $out"
    fi
    cmp -s "$dir/before.meta" "$dir/home/state/task-a.meta" || fail "$variant recovery changed its record"
    [ ! -s "$dir/actions" ] || fail "$variant recovery created or controlled an endpoint"
  done
  pass "missing-endpoint recovery refuses occupied, foreign, duplicate, divergent, competing and unreadable evidence"
}

test_missing_endpoint_creation_failure_is_not_replayed() {
  local dir out
  dir=$(make_case missing-create-failure)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  jq '.[0].processes=[]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json"
  printf missing > "$dir/agent"
  if out=$(FM_TEST_CREATE_FAIL=1 control "$dir" relaunch --note 'Preserve this recovery.' 2>&1); then
    fail "ambiguous endpoint creation succeeded"
  fi
  assert_grep 'phase=failed:recreating' "$dir/home/state/task-a.control-relaunch" "failed creation has no durable receipt"
  if out=$(control "$dir" relaunch --note 'Retry must not duplicate the terminal.' 2>&1); then
    fail "ambiguous endpoint creation was replayed"
  fi
  assert_contains "$out" 'prior endpoint creation is unconfirmed' "retry did not explain its retained uncertainty"
  [ "$(cat "$dir/actions")" = create ] || fail "retry created another terminal"
  assert_grep 'unfinished original work' "$dir/original/preserved.txt" "failed creation lost work"
  pass "uncertain terminal creation is retained for inspection rather than repeated"
}

test_missing_endpoint_restored_by_server_is_reused() {
  local dir out
  dir=$(make_case missing-restored)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf missing > "$dir/agent"
  out=$(FM_TEST_RESTORE_STATE=dead control "$dir" relaunch --note 'Reuse a safely restored terminal.' 2>&1) \
    || fail "restored shell recovery failed: $out"
  [ "$(cat "$dir/actions")" = launch ] || fail "a restored terminal was replaced"
  assert_grep 'window=fixture:w1:p1' "$dir/home/state/task-a.meta" "restored terminal identity changed"
  pass "restoring the original shell avoids creating another terminal"
}

test_missing_endpoint_restored_unsafe_state_refuses() {
  local dir state out
  for state in alive unreadable; do
    dir=$(make_case "restored-$state")
    cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
    cp "$dir/home/state/task-a.meta" "$dir/before.meta"
    cp "$dir/home/data/task-a/brief.md" "$dir/before.brief"
    printf missing > "$dir/agent"
    if out=$(FM_TEST_RESTORE_STATE="$state" control "$dir" relaunch --note 'Do not duplicate a restored worker.' 2>&1); then
      fail "a restored $state endpoint was relaunched: $out"
    fi
    assert_contains "$out" 'no longer proven missing or agent-free' "restored $state refusal was unexplained"
    cmp -s "$dir/before.meta" "$dir/home/state/task-a.meta" || fail "restored $state changed its record"
    cmp -s "$dir/before.brief" "$dir/home/data/task-a/brief.md" || fail "restored $state changed its brief"
    [ ! -s "$dir/actions" ] || fail "restored $state created or controlled an endpoint"
  done
  pass "a live or unreadable restored endpoint refuses recovery without lifecycle input"
}

test_missing_endpoint_launch_failure_reuses_published_binding() {
  local dir out
  dir=$(make_case missing-launch-failure)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  jq '.[0].processes=[]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json"
  printf missing > "$dir/agent"
  if out=$(FM_TEST_SPAWN_FAIL=1 control "$dir" relaunch --note 'Keep the replacement terminal for retry.' 2>&1); then
    fail "failed worker launch reported success: $out"
  fi
  assert_grep 'window=fixture:w3:p3' "$dir/home/state/task-a.meta" "failed launch lost its published endpoint"
  assert_grep 'phase=failed:launching' "$dir/home/state/task-a.control-relaunch" "failed launch lost its journal"
  out=$(control "$dir" relaunch --note 'Retry in the already-published terminal.' 2>&1) \
    || fail "retry after endpoint publication failed: $out"
  [ "$(cat "$dir/actions")" = $'create\nlaunch\nlaunch' ] || fail "retry duplicated or stopped an endpoint"
  assert_grep 'window=fixture:w3:p3' "$dir/home/state/task-a.meta" "retry changed the published endpoint"
  assert_grep 'unfinished original work' "$dir/original/preserved.txt" "retry lost preserved work"
  pass "a launch failure retains the new endpoint and retry never creates another"
}

test_relaunch_slow_probe_consumes_deadline() {
  local dir out rc=0 count
  dir=$(make_case slow-probe)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  out=$(FM_TEST_PROBE_DELAY=4 FM_TEST_CONTROL_POLL=2 FM_TEST_CONTROL_LAUNCH_WAIT=2 \
    control "$dir" relaunch --note 'A failed replacement must not multiply its wait by query cost.' 2>&1) || rc=$?
  expect_code 3 "$rc" "unreadable confirmation must retain launch uncertainty: $out"
  [ -f "$dir/launch-observed" ] && [ -s "$dir/probes" ] || fail "slow probe did not run after launch"
  count=$(wc -l < "$dir/probes")
  [ "$count" -eq 1 ] || fail "a two-second wait made $count queries despite each taking at least four seconds"
  [ ! -s "$dir/completed-probes" ] || fail "the status query outlived the shared deadline"
  assert_contains "$out" 'relaunch-unconfirmed' "timeout must distinguish uncertainty from failure"
  assert_grep 'phase=launch-unconfirmed' "$dir/home/state/task-a.control-relaunch" "unconfirmed launch phase missing"
  assert_grep 'delivery=accepted' "$dir/home/state/task-a.control-relaunch" "accepted delivery evidence was lost"
  assert_grep 'spawn_gen=new-generation' "$dir/home/state/task-a.meta" "timed-out replacement reverted its record"
  assert_grep 'unfinished original work' "$dir/original/preserved.txt" "timeout discarded the original work"
  [ ! -e "$dir/home/state/.control-task-a.lock" ] && [ ! -L "$dir/home/state/.control-task-a.lock" ] \
    || fail "timed-out recovery retained lifecycle authority"
  pass "relaunch charges slow observations to one deadline and preserves unconfirmed replacement state"
}

test_relaunch_stuck_probe_is_bounded_and_reaped() {
  local dir out rc=0 pid i stat
  dir=$(make_case stuck-probe)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  # Partial alive output followed by a TERM-resistant query and descendant
  # must not become launch confirmation, even when their output pipe stays open.
  out=$(FM_TEST_PROBE_MODE=stuck FM_TEST_CONTROL_POLL=2 FM_TEST_CONTROL_LAUNCH_WAIT=4 \
    control "$dir" relaunch --note 'An unfinished observation must not confirm the replacement.' 2>&1) || rc=$?
  expect_code 3 "$rc" "a stuck observation must leave recovery unconfirmed: $out"
  [ -s "$dir/probe-pid" ] && [ -s "$dir/probe-child" ] || fail "TERM-resistant probe did not reach its child"
  [ ! -e "$dir/probe-escaped" ] || fail "stuck probe completed outside the configured deadline"
  assert_contains "$out" 'endpoint_state=unreadable' "partial alive output was accepted as a completed observation"
  assert_grep 'phase=launch-unconfirmed' "$dir/home/state/task-a.control-relaunch" "stuck query lost unconfirmed phase"
  assert_grep 'delivery=accepted' "$dir/home/state/task-a.control-relaunch" "stuck query lost its delivery evidence"
  for pid in "$(cat "$dir/probe-pid")" "$(cat "$dir/probe-child")"; do
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 30 ]; do
      # A terminated, not-yet-reaped child is not a running escaped observer.
      stat=
      if [ -r "/proc/$pid/stat" ]; then
        IFS= read -r stat < "/proc/$pid/stat" || true
        case "${stat##*)}" in ' Z '*) break ;; esac
      else
        stat=$(ps -p "$pid" -o stat= 2>/dev/null || true)
        case "$stat" in Z*) break ;; esac
      fi
      /bin/sleep 0.1
      i=$((i + 1))
    done
    [ "$i" -lt 30 ] || fail "owned observation process $pid escaped timeout cleanup"
  done
  [ ! -e "$dir/home/state/.control-task-a.lock" ] && [ ! -L "$dir/home/state/.control-task-a.lock" ] \
    || fail "stuck recovery retained lifecycle authority"
  pass "relaunch kills its TERM-resistant observation group and rejects partial alive output"
}

test_relaunch_completed_probe_keeps_parent_transaction() {
  local dir out
  dir=$(make_case completed-probe)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  out=$(FM_TEST_PROBE_MODE=ready control "$dir" relaunch --note 'A completed observation confirms this replacement.' 2>&1) \
    || fail "completed observation failed recovery: $out"
  assert_contains "$out" 'relaunched task-a' "completed observation lost its success result"
  [ "$(wc -l < "$dir/probes")" -eq 1 ] || fail "completed observation was polled again"
  assert_grep 'phase=complete' "$dir/home/state/task-a.control-relaunch" "observer ran the parent's rollback"
  assert_grep 'spawn_gen=new-generation' "$dir/home/state/task-a.meta" "successful observer reverted replacement state"
  [ ! -e "$dir/home/state/.control-task-a.lock" ] && [ ! -L "$dir/home/state/.control-task-a.lock" ] \
    || fail "completed recovery retained lifecycle authority"
  pass "a complete pre-deadline observation confirms launch without inheriting parent rollback"
}

test_relaunch_report_during_unfinished_observation() {
  local dir out
  dir=$(make_case terminal-during-probe)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  printf 'done: previous incarnation\n' > "$dir/home/state/task-a.status"
  out=$(FM_TEST_PROBE_MODE=stuck FM_TEST_CONTROL_LAUNCH_WAIT=4 \
    FM_TEST_REPORT_DURING_PROBE='done: replacement completed the requested change' \
    control "$dir" relaunch --note 'Report the real outcome even when confirmation cannot finish.' 2>&1) \
    || fail "terminal report during a stuck query was lost: $out"
  assert_contains "$out" 'outcome=reported-done' "task completion was not distinguished from live-agent proof"
  assert_contains "$out" 'replacement completed the requested change' "replacement outcome was not returned"
  assert_grep 'phase=complete' "$dir/home/state/task-a.control-relaunch" "terminal replacement kept a failed transaction"
  assert_grep 'launch_outcome=reported-done' "$dir/home/state/task-a.control-relaunch" "report outcome was not persisted"
  [ ! -e "$dir/probe-escaped" ] || fail "terminal evidence disabled observation cleanup"
  [ "$(cat "$dir/actions")" = launch ] || fail "terminal reconciliation launched another worker"
  pass "a generation-bound terminal report survives an unfinished backend observation"
}

test_unconfirmed_relaunch_reconciles_without_duplicate() {
  local dir out rc=0
  dir=$(make_case late-terminal)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  out=$(FM_TEST_PROBE_MODE=stuck FM_TEST_CONTROL_LAUNCH_WAIT=4 \
    control "$dir" relaunch --note 'Continue exactly once.' 2>&1) || rc=$?
  expect_code 3 "$rc" "accepted but unreadable launch must remain unconfirmed: $out"
  cp "$dir/home/state/task-a.meta" "$dir/accepted.meta"
  cp "$dir/home/data/task-a/brief.md" "$dir/accepted.brief"
  sed 's/^spawn_gen=.*/spawn_gen=foreign-generation/' "$dir/accepted.meta" > "$dir/home/state/task-a.meta"
  if out=$(control "$dir" relaunch --note 'Must not reach another incarnation.' 2>&1); then
    fail "an unconfirmed transaction adopted a different replacement"
  fi
  assert_contains "$out" 'unconfirmed launch binding changed' "generation drift did not refuse specifically"
  cp "$dir/accepted.meta" "$dir/home/state/task-a.meta"
  printf 'done: late replacement report\n' >> "$dir/home/state/task-a.status"
  out=$(control "$dir" inspect) || fail "late report could not be inspected"
  printf '%s' "$out" | jq -e '.transaction_phase == "launch-unconfirmed" and .launch_report == "done: late replacement report"' \
    >/dev/null || fail "inspection hid the outcome arriving after confirmation"
  out=$(control "$dir" relaunch --note 'This new note must not be delivered while reconciling.' 2>&1) \
    || fail "late completion was not reconciled: $out"
  assert_contains "$out" 'relaunch-reconciled' "repeat did not identify reconciliation"
  assert_contains "$out" 'outcome=reported-done' "late completion did not settle launch"
  [ "$(cat "$dir/actions")" = launch ] || fail "repeat launched or stopped another worker"
  cmp -s "$dir/accepted.brief" "$dir/home/data/task-a/brief.md" || fail "repeat appended an undelivered note"
  assert_grep 'new_note_delivered=false' "$dir/home/state/task-a.control-relaunch" "reconciliation claimed another delivery"
  assert_grep 'phase=complete' "$dir/home/state/task-a.control-relaunch" "late result did not settle the journal"
  pass "unconfirmed launch keeps its exact identity and late completion settles without another worker"
}

test_relaunch_reported_failure_is_not_launch_failure() {
  local dir out
  dir=$(make_case reported-failure)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  out=$(FM_TEST_PROBE_MODE=early-exit FM_TEST_LAUNCH_REPORT='failed: requested operation refused' \
    control "$dir" relaunch --note 'Return the actual task failure.' 2>&1) \
    || fail "a worker-reported failure was mistaken for failed launch: $out"
  assert_contains "$out" 'outcome=reported-failed' "task failure was reported as success or as live-agent proof"
  assert_contains "$out" 'failed: requested operation refused' "task failure detail disappeared"
  assert_grep 'phase=complete' "$dir/home/state/task-a.control-relaunch" "a verified report retained a failed launch"
  pass "a launched worker's failed outcome is preserved without inventing a launch failure"
}

test_relaunch_early_exit_without_report_is_failure() {
  local dir out rc=0
  dir=$(make_case no-report)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  printf 'done: stale predecessor result\n' > "$dir/home/state/task-a.status"
  out=$(FM_TEST_PROBE_MODE=early-exit FM_TEST_CONTROL_LAUNCH_WAIT=8 FM_TEST_CONTROL_POLL=30 \
    control "$dir" relaunch --note 'An old terminal event must not bless a failed replacement.' 2>&1) || rc=$?
  expect_code 1 "$rc" "positive exit without a fresh report must fail: $out"
  assert_contains "$out" 'exited without a current terminal report' "early exit had no actionable explanation"
  assert_grep 'phase=failed:launching' "$dir/home/state/task-a.control-relaunch" "a genuine failure was hidden"
  assert_grep 'launch_outcome=exited-without-report' "$dir/home/state/task-a.control-relaunch" "early exit evidence was not retained"
  assert_grep 'unfinished original work' "$dir/original/preserved.txt" "failed replacement discarded existing work"
  pass "positive early exit without a new report remains a genuine launch failure"
}

test_windows_relaunch_query_deadline_reaps_native_process() {
  local dir out rc=0 native_record
  case "${OS:-}" in Windows_NT) ;; *) return 0 ;; esac
  command -v powershell.exe >/dev/null 2>&1 || fail "PowerShell is required for the native query deadline case"
  dir=$(make_case native-query)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  cat > "$dir/native-probe.ps1" <<'PS'
$process = Get-Process -Id $PID
@{ pid=$PID; birth=$process.StartTime.ToUniversalTime().Ticks.ToString() } |
  ConvertTo-Json -Compress | Set-Content -LiteralPath $env:FM_TEST_NATIVE_RECORD
[Console]::Write('alive')
Start-Sleep -Seconds 30
Set-Content -LiteralPath ($env:FM_TEST_NATIVE_RECORD + '.escaped') -Value 'escaped'
PS
  out=$(FM_TEST_PROBE_MODE=native-stuck FM_TEST_CONTROL_LAUNCH_WAIT=8 \
    control "$dir" relaunch --note 'Bound the native status query, not the worker it observes.' 2>&1) || rc=$?
  expect_code 3 "$rc" "unfinished native observation must not confirm recovery: $out"
  [ -f "$dir/native-process.json" ] || fail "native process did not start inside the fixture's query window"
  [ ! -e "$dir/native-process.json.escaped" ] || fail "native query escaped its deadline"
  assert_contains "$out" 'endpoint_state=unreadable' "native partial output became a liveness verdict"
  native_record=$(cygpath -m "$dir/native-process.json")
  # Read only the exact PID/birth tuple created by this fixture; never signal
  # the worker or scan another process tree to compensate for failed cleanup.
  # shellcheck disable=SC2016 # PowerShell expands its own process/identity variables.
  FM_TEST_NATIVE_RECORD="$native_record" powershell.exe -NoProfile -NonInteractive -Command '
    $record = Get-Content -Raw -LiteralPath $env:FM_TEST_NATIVE_RECORD | ConvertFrom-Json
    $process = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
    if ($process -and -not $process.HasExited -and $process.StartTime.ToUniversalTime().Ticks.ToString() -eq $record.birth) {
      Write-Output ("owned native query still running: pid=" + $record.pid + " observed=" + [DateTime]::UtcNow.ToString("o"))
      exit 1
    }
    exit 0
  ' || fail "the native query process survived the observation deadline"
  assert_grep 'phase=launch-unconfirmed' "$dir/home/state/task-a.control-relaunch" "native query timeout lost unconfirmed phase"
  assert_grep 'delivery=accepted' "$dir/home/state/task-a.control-relaunch" "native query timeout lost delivery evidence"
  pass "Windows recovery bounds and reaps its native observation without claiming partial alive output"
}

test_control_inspect_accepts_windows_path_context() {
  local dir form home code state data out
  case "${OS:-}" in Windows_NT) ;; *) return 0 ;; esac
  dir=$(make_case "path context café '[x] &")
  for form in posix mixed native; do
    home="$dir/home" code="$CODE" state="$dir/home/state" data="$dir/home/data"
    case "$form" in
      mixed)
        home=$(cygpath -m "$home"); code=$(cygpath -m "$code")
        state=$(cygpath -m "$state"); data=$(cygpath -m "$data")
        ;;
      native)
        home=$(cygpath -w "$home"); code=$(cygpath -w "$code")
        state=$(cygpath -w "$state"); data=$(cygpath -w "$data")
        ;;
    esac
    # shellcheck disable=SC2016 # PowerShell receives code paths as data.
    out=$(FM_TEST_REAL_ROOT="$ROOT" FM_TEST_CASE="$dir" FM_HOME="$home" FM_ROOT_OVERRIDE="$code" \
      FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" PATH="$dir/fakebin:$PATH" \
      FM_TEST_CODE_NATIVE="$(cygpath -w "$CODE")" powershell.exe -NoProfile -NonInteractive -Command '
        & (Join-Path $env:FM_TEST_CODE_NATIVE "bin/fm-windows-git-bash.ps1") (Join-Path $env:FM_TEST_CODE_NATIVE "bin/fm-control.sh") task-a inspect
        exit $LASTEXITCODE
      ') || fail "$form context inspection failed through the native launcher"
    printf '%s' "$out" | jq -e '.schema == "fm-control-inspection.v1" and .agent_state == "missing" and .action_in_progress == false' \
      >/dev/null || fail "$form context inspection changed its observation"
    [ ! -s "$dir/actions" ] || fail "$form inspection delivered a lifecycle action"
  done
  pass "read-only control inspection accepts equivalent Windows and POSIX context paths"
}

test_recovery_receipt_home_aliases_remain_readable() {
  local dir token receipt home form out
  case "${OS:-}" in Windows_NT) ;; *) return 0 ;; esac
  dir=$(make_case receipt-path-alias)
  token=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  receipt="$dir/home/state/task-a.control-recovery/$token/receipt.json"
  mkdir -p "${receipt%/*}" "$dir/foreign-home"
  printf 'control_recovery_token=%s\n' "$token" >> "$dir/home/state/task-a.meta"
  for form in native mixed posix; do
    home="$dir/home"
    case "$form" in native) home=$(cygpath -w "$home");; mixed) home=$(cygpath -m "$home");; esac
    jq -cn --arg token "$token" --arg home "$home" \
      '{schema:"fm-control-recovery-plan.v1",approval:$token,bindings:{task:"task-a",home:$home},phase:"complete"}' > "$receipt"
    cp "$receipt" "$dir/before-receipt"
    out=$(control "$dir" inspect 2>&1) || fail "$form legacy receipt was unreadable through the equivalent home: $out"
    printf '%s' "$out" | jq -e '.recovery.phase == "complete"' >/dev/null || fail "$form receipt lost its completed phase"
    cmp -s "$dir/before-receipt" "$receipt" || fail "inspection rewrote a bound receipt"
  done
  jq --arg home "$dir/foreign-home" '.bindings.home=$home' "$receipt" > "$dir/foreign-receipt"
  mv "$dir/foreign-receipt" "$receipt"
  if control "$dir" inspect >/dev/null 2>&1; then fail "a receipt from another physical home was accepted"; fi
  [ ! -s "$dir/actions" ] || fail "receipt inspection performed a lifecycle action"
  pass "completed receipts retain their bytes across home spellings and refuse a different directory identity"
}

test_recovery_approved_and_idempotent() {
local dir before out token inspected
dir=$(make_case approved)
before=$(git -C "$dir/original" rev-parse HEAD)
out=$(plan "$dir") || fail "could not inspect the original-worker recovery plan"
token=$(printf '%s' "$out" | jq -er '.recovery.approval')
[ ! -s "$dir/actions" ] || fail "inspection delivered lifecycle input"
[ ! -e "$dir/home/state/task-a.control-recovery" ] || fail "inspection wrote a recovery receipt"
recover "$dir" "$token" > "$dir/result" || fail "approved recovery failed"
[ "$(git -C "$dir/original" rev-parse HEAD)" = "$before" ] || fail "recovery reset the original branch"
assert_grep 'unfinished original work' "$dir/original/preserved.txt" "original edits were discarded"
assert_grep 'unfinished replacement work' "$dir/replacement/also-preserved.txt" "replacement edits were discarded"
assert_grep "worktree=$dir/original" "$dir/home/state/task-a.meta" "the original copy was not restored"
assert_grep 'pr=https://github.com/example/repo/pull/42' "$dir/home/state/task-a.meta" "current PR tracking was lost"
grep -Fxq 'phase=complete' "$dir/home/state/task-a.control-relaunch" || fail "relaunch transaction did not finish"
[ "$(grep -c '^launch$' "$dir/actions")" -eq 1 ] || fail "recovery did not launch exactly once"
recover "$dir" "$token" > "$dir/replay" || fail "completed recovery did not replay idempotently"
assert_grep recovery-already-complete "$dir/replay" "replay did not identify completed recovery"
[ "$(grep -c '^launch$' "$dir/actions")" -eq 1 ] || fail "replayed approval restarted another agent"
inspected=$(control "$dir" inspect) || fail "completed recovery could not be inspected"
printf '%s' "$inspected" | jq -e '.recovery.phase == "complete" and .recovery.preserves_other_copy == true' >/dev/null \
  || fail "inspection lost the completed recovery's preservation receipt"
pass "approved recovery preserves both copies, current task records, and exactly one relaunch"
}

test_recovery_stale_approval() {
local dir out token
dir=$(make_case changed)
out=$(plan "$dir") || fail "could not inspect stale-plan fixture"
token=$(printf '%s' "$out" | jq -er '.recovery.approval')
printf '\nchanged: evidence\n' >> "$dir/home/data/task-a/original.meta"
cp "$dir/home/state/task-a.meta" "$dir/before.meta"
if recover "$dir" "$token" > "$dir/out" 2>&1; then fail "stale approval was accepted"; fi
cmp -s "$dir/before.meta" "$dir/home/state/task-a.meta" || fail "stale approval changed the record"
[ ! -s "$dir/actions" ] || fail "stale approval delivered lifecycle input"
pass "changed records invalidate approval before record or process mutation"
}

test_recovery_live_and_foreign_refusals() {
local dir
dir=$(make_case live-record)
if FM_TEST_CURRENT_STATE=alive plan "$dir" > "$dir/out" 2>&1; then fail "a live recorded endpoint was displaced"; fi
[ ! -s "$dir/actions" ] || fail "live-record refusal delivered lifecycle input"
jq '.[0].lease_holder="another-task"' "$dir/pool.json" > "$dir/next.json"
mv "$dir/next.json" "$dir/pool.json"
if plan "$dir" > "$dir/lease.out" 2>&1; then fail "another task's lease was adopted"; fi
pass "live replacements and foreign lease ownership refuse recovery"
}

test_recovery_pid_drift_and_partial_replay() {
local dir out token
dir=$(make_case pid-reused)
printf 'launch_status=v1|original-generation|0|-|-\n' >> "$dir/home/data/task-a/original.meta"
printf 'launch_status=v1|replacement-generation|0|-|-\n' >> "$dir/home/state/task-a.meta"
out=$(plan "$dir") || fail "could not inspect PID-reuse fixture"
token=$(printf '%s' "$out" | jq -er '.recovery.approval')
if FM_TEST_RECOVERY_DRIFT=1 recover "$dir" "$token" > "$dir/out" 2>&1; then fail "PID birth drift was accepted at exit"; fi
[ ! -s "$dir/actions" ] || fail "PID reuse delivered input to a replacement process"
assert_grep 'approved native process instances changed' "$dir/out" "PID drift refusal was not explicit"
assert_grep "worktree=$dir/original" "$dir/home/state/task-a.meta" "proven binding was lost after process drift"
assert_grep 'launch_status=v1|original-generation|0|-|-' "$dir/home/state/task-a.meta" \
  "record recovery mixed one generation with another generation's report boundary"
if recover "$dir" "$token" > "$dir/replay" 2>&1; then fail "partial recovery silently launched on retry"; fi
out=$(control "$dir" inspect) || fail "partial recovery could not be inspected"
printf '%s' "$out" | jq -e '.recovery.phase == "bound"' >/dev/null || fail "partial receipt was not returned by inspection"
pass "immediate native identity revalidation and partial receipts prevent duplicate recovery"
}

test_recovery_ambiguous_evidence_refuses() {
  local dir variant candidate
  for variant in outside profile generation duplicate-lease used-copy branch linked; do
    dir=$(make_case "$variant")
    candidate="$dir/home/data/task-a/original.meta"
    cp "$dir/home/state/task-a.meta" "$dir/before.meta"
    case "$variant" in
      outside) cp "$candidate" "$dir/foreign.meta"; candidate="$dir/foreign.meta" ;;
      profile) printf 'harness=pi\n' >> "$candidate" ;;
      generation) printf 'busy_gen=duplicate\n' >> "$candidate" ;;
      duplicate-lease) jq '. + [.[0]]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json" ;;
      used-copy) jq '.[1].processes=[{pid:700}]' "$dir/pool.json" > "$dir/next"; mv "$dir/next" "$dir/pool.json" ;;
      branch) git -C "$dir/original" checkout -qb another-task ;;
      linked) ln "$candidate" "$dir/second-link" ;;
    esac
    if control "$dir" inspect --recover-from "$candidate" > "$dir/refusal" 2>&1; then
      fail "ambiguous $variant evidence produced an actionable plan"
    fi
    cmp -s "$dir/before.meta" "$dir/home/state/task-a.meta" || fail "$variant inspection changed the record"
    [ ! -s "$dir/actions" ] || fail "$variant inspection delivered lifecycle input"
  done
  pass "recovery refuses foreign records, ambiguous generations/leases, occupied copies, wrong branches, and linked evidence"
}

test_recovery_other_claim_refuses_publication() {
  local dir out token
  dir=$(make_case other-claim)
  out=$(plan "$dir") || fail "could not inspect competing-claim fixture"
  token=$(printf '%s' "$out" | jq -er '.recovery.approval')
  printf 'window=fixture:w1:p1\nworktree=%s\n' "$dir/original" > "$dir/home/state/other.meta"
  cp "$dir/home/state/task-a.meta" "$dir/before.meta"
  if recover "$dir" "$token" > "$dir/out" 2>&1; then fail "another task's claim was overwritten"; fi
  cmp -s "$dir/before.meta" "$dir/home/state/task-a.meta" || fail "competing claim changed the record"
  [ ! -s "$dir/actions" ] || fail "competing claim delivered lifecycle input"
  pass "recovery rechecks competing home-local claims under publication serialization"
}

test_batch_relaunch_continues_after_a_refused_target() {
  local dir out rc=0
  dir=$(make_case batch-after-refusal)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  out=$(control_cli "$dir" --batch-relaunch missing-task task-a --note 'Continue each authorized task independently.' 2>&1) || rc=$?
  expect_code 1 "$rc" "a partial batch must retain its failure: $out"
  assert_contains "$out" 'batch-relaunch: missing-task result=failed exit=1' 'the refused target was not accounted for'
  assert_contains "$out" 'batch-relaunch: task-a result=confirmed exit=0' 'one refusal stranded the valid later target'
  assert_grep 'phase=complete' "$dir/home/state/task-a.control-relaunch" 'the later transaction did not complete'
  [ "$(cat "$dir/actions")" = launch ] || fail 'the later task was skipped or launched more than once'
  assert_grep 'unfinished original work' "$dir/original/preserved.txt" 'batch recovery lost existing work'
  pass 'a refused recovery does not prevent another selected task from completing its own transaction'
}

test_batch_relaunch_success_preserves_literal_shared_note() {
  local dir out note rc=0
  dir=$(make_case batch-confirmed)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  printf '%s\n' '--continue the already-authorized task' 'Keep this second line and its "quoted text" literal.' > "$dir/shared-note"
  note=$(cat "$dir/shared-note")
  out=$(control_cli "$dir" --batch-relaunch task-a --note-file "$dir/shared-note" 2>&1) || rc=$?
  expect_code 0 "$rc" "a fully confirmed batch must succeed: $out"
  assert_contains "$out" 'batch-relaunch: task-a result=confirmed exit=0' 'confirmed result was lost'
  assert_contains "$(cat "$dir/home/data/task-a/brief.md")" "$note" 'batch changed the literal multiline note'
  assert_grep 'harness=copilot' "$dir/home/state/task-a.meta" 'batch silently changed the recorded profile'
  [ "$(cat "$dir/actions")" = launch ] || fail 'confirmed batch did not launch exactly once'
  pass 'a confirmed batch preserves the literal shared note and existing profile and returns success'
}

test_batch_relaunch_keeps_unconfirmed_outcomes_and_continues() {
  local dir out rc=0
  dir=$(make_case batch-unconfirmed)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  out=$(FM_TEST_PROBE_MODE=stuck FM_TEST_CONTROL_LAUNCH_WAIT=4 \
    control_cli "$dir" --batch-relaunch task-a missing-later --note 'Resume each task without hiding uncertainty.' 2>&1) || rc=$?
  expect_code 1 "$rc" "the later refusal must remain an aggregate failure: $out"
  assert_contains "$out" 'batch-relaunch: task-a result=unconfirmed exit=3' 'accepted but unconfirmed delivery was relabeled'
  assert_contains "$out" 'batch-relaunch: missing-later result=failed exit=1' 'unconfirmed delivery prevented the later target from being checked'
  assert_grep 'phase=launch-unconfirmed' "$dir/home/state/task-a.control-relaunch" 'batch rewrote the single-task transaction'
  [ "$(cat "$dir/actions")" = launch ] || fail 'batch retried an unconfirmed worker'
  pass 'batch recovery retains uncertainty, attempts later targets, and never retries an unconfirmed launch'
}

test_batch_relaunch_only_unconfirmed_returns_three() {
  local dir out rc=0
  dir=$(make_case batch-only-unconfirmed)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  printf dead > "$dir/agent"
  out=$(FM_TEST_PROBE_MODE=stuck FM_TEST_CONTROL_LAUNCH_WAIT=4 \
    control_cli "$dir" --batch-relaunch task-a --note 'Keep accepted delivery distinct from failure.' 2>&1) || rc=$?
  expect_code 3 "$rc" "a batch with only unconfirmed outcomes must return 3: $out"
  assert_contains "$out" 'batch-relaunch: task-a result=unconfirmed exit=3' 'the per-task outcome disappeared'
  [ "$(cat "$dir/actions")" = launch ] || fail 'unconfirmed-only batch repeated launch'
  pass 'an unconfirmed-only batch reports uncertainty rather than success or failure'
}

test_batch_relaunch_rejects_duplicate_or_unsafe_selection_before_actions() {
  local dir out rc
  dir=$(make_case batch-invalid)
  cp "$dir/home/data/task-a/original.meta" "$dir/home/state/task-a.meta"
  cp "$dir/home/state/task-a.meta" "$dir/before.meta"
  cp "$dir/home/data/task-a/brief.md" "$dir/before.brief"
  rc=0
  out=$(control_cli "$dir" --batch-relaunch task-a task-a --note 'Do not repeat a lifecycle action.' 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail 'duplicate batch targets were accepted'
  assert_contains "$out" 'duplicate batch task' 'duplicate targets were not rejected specifically'
  rc=0
  out=$(control_cli "$dir" --batch-relaunch task-a '../foreign' --note 'Stay in this home.' 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail 'an unsafe batch target was accepted'
  assert_contains "$out" 'not a valid task id' 'unsafe target was not rejected specifically'
  rc=0
  out=$(control_cli "$dir" --batch-relaunch task-a --recover-from "$dir/home/data/task-a/original.meta" \
    --approve-recovery 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
    --note 'Approval belongs to one exact task.' 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail 'a per-task recovery approval was accepted for batch reuse'
  assert_contains "$out" 'record recovery is single-task only' 'batch did not retain the per-task approval boundary'
  [ ! -s "$dir/actions" ] || fail 'batch validation acted on an earlier task before finding invalid input'
  cmp -s "$dir/before.meta" "$dir/home/state/task-a.meta" || fail 'invalid batch changed metadata'
  cmp -s "$dir/before.brief" "$dir/home/data/task-a/brief.md" || fail 'invalid batch changed instructions'
  pass 'batch recovery validates all exact targets and refuses duplicate actions or shared approval before mutation'
}

fm_test_run_cases \
  test_relaunch_missing_endpoint_preserves_copy \
  test_missing_endpoint_recovery_refuses_unsafe_claims \
  test_missing_endpoint_creation_failure_is_not_replayed \
  test_missing_endpoint_restored_by_server_is_reused \
  test_missing_endpoint_restored_unsafe_state_refuses \
  test_missing_endpoint_launch_failure_reuses_published_binding \
  test_recovery_approved_and_idempotent \
  test_recovery_stale_approval \
  test_recovery_live_and_foreign_refusals \
  test_recovery_pid_drift_and_partial_replay \
  test_recovery_ambiguous_evidence_refuses \
  test_recovery_other_claim_refuses_publication \
  test_relaunch_slow_probe_consumes_deadline \
  test_relaunch_stuck_probe_is_bounded_and_reaped \
  test_relaunch_completed_probe_keeps_parent_transaction \
  test_relaunch_report_during_unfinished_observation \
  test_unconfirmed_relaunch_reconciles_without_duplicate \
  test_relaunch_reported_failure_is_not_launch_failure \
  test_relaunch_early_exit_without_report_is_failure \
  test_windows_relaunch_query_deadline_reaps_native_process \
  test_control_inspect_accepts_windows_path_context \
  test_recovery_receipt_home_aliases_remain_readable \
  test_batch_relaunch_continues_after_a_refused_target \
  test_batch_relaunch_success_preserves_literal_shared_note \
  test_batch_relaunch_keeps_unconfirmed_outcomes_and_continues \
  test_batch_relaunch_only_unconfirmed_returns_three \
  test_batch_relaunch_rejects_duplicate_or_unsafe_selection_before_actions

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
    fixture:w2:p2) printf '%s' "${FM_TEST_CURRENT_STATE:-missing}" ;;
    fixture:w1:p1) cat "$FM_TEST_CASE/agent" ;;
    *) printf unreadable ;;
  esac
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
printf alive > "$FM_TEST_CASE/agent"
awk '$0 ~ /^spawn_gen=/ {$0="spawn_gen=new-generation"} {print}' "$FM_STATE_OVERRIDE/task-a.meta" > "$FM_STATE_OVERRIDE/next.meta"
mv "$FM_STATE_OVERRIDE/next.meta" "$FM_STATE_OVERRIDE/task-a.meta"
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
control() {
  local dir=$1; shift
  env FM_TEST_REAL_ROOT="$ROOT" FM_TEST_CASE="$dir" FM_HOME="$dir/home" \
    FM_ROOT_OVERRIDE="$CODE" FM_STATE_OVERRIDE="$dir/home/state" FM_DATA_OVERRIDE="$dir/home/data" \
    FM_CONTROL_POLL=0.01 FM_CONTROL_EXIT_WAIT=0.05 FM_CONTROL_LAUNCH_WAIT=0.05 \
    PATH="$dir/fakebin:$PATH" "$CODE/bin/fm-control.sh" task-a "$@"
}
plan() { control "$1" inspect --recover-from "$1/home/data/task-a/original.meta"; }
recover() {
  control "$1" relaunch --recover-from "$1/home/data/task-a/original.meta" \
    --approve-recovery "$2" --note 'Approved original-worker recovery; preserve both copies.'
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
out=$(plan "$dir") || fail "could not inspect PID-reuse fixture"
token=$(printf '%s' "$out" | jq -er '.recovery.approval')
if FM_TEST_RECOVERY_DRIFT=1 recover "$dir" "$token" > "$dir/out" 2>&1; then fail "PID birth drift was accepted at exit"; fi
[ ! -s "$dir/actions" ] || fail "PID reuse delivered input to a replacement process"
assert_grep 'approved native process instances changed' "$dir/out" "PID drift refusal was not explicit"
assert_grep "worktree=$dir/original" "$dir/home/state/task-a.meta" "proven binding was lost after process drift"
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

fm_test_run_cases \
  test_recovery_approved_and_idempotent \
  test_recovery_stale_approval \
  test_recovery_live_and_foreign_refusals \
  test_recovery_pid_drift_and_partial_replay \
  test_recovery_ambiguous_evidence_refuses \
  test_recovery_other_claim_refuses_publication

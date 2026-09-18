#!/usr/bin/env bash
# Fresh-start queue integration through the real spawn command, with private Git
# worktrees and fixture-only tmux/Treehouse transports. Kept separate from the
# parser-only spawn-batch suite so its old parallel admission does not silently
# admit these process/lock interleavings. No real endpoint or vendor is started.
set -u
# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-queue)

QUEUE_TEST_PIDS=()
QUEUE_TEST_RELEASES=()
queue_test_cleanup() {
  local file pid
  for file in "${QUEUE_TEST_RELEASES[@]+"${QUEUE_TEST_RELEASES[@]}"}"; do
    [ ! -d "${file%/*}" ] || : > "$file"
  done
  # Every child is owned by this fixture and its barrier has been released.
  # Waiting lets the real owners clean their locks before the temp root goes.
  for pid in "${QUEUE_TEST_PIDS[@]+"${QUEUE_TEST_PIDS[@]}"}"; do wait "$pid" 2>/dev/null || true; done
  fm_test_cleanup
}
trap queue_test_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

make_queue_world() {
  local dir="$TMP_ROOT/$1" project fakebin
  fm_test_spawn_home "$dir/home" codex
  for project in alpha bravo; do
    fm_git_worktree "$dir/$project" "$dir/$project-wt" "slot-$project"
    fm_test_spawn_brief "$dir/home" "$project" "Publish $project in this isolated fixture."
  done
  fakebin=$(fm_test_make_spawn_fakebin "$dir/fake" codex)
  mv "$fakebin/tmux" "$fakebin/tmux-default"
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = new-window ]; then
  printf '%s\n' "$FM_QUEUE_TASK" >> "$FM_QUEUE_DIR/created"
  if [ "${FM_QUEUE_HOLD:-0}" = 1 ]; then
    : > "$FM_QUEUE_DIR/ready"
    i=0
    while [ ! -e "$FM_QUEUE_DIR/release" ] && [ "$i" -lt 1200 ]; do
      /bin/sleep 0.1
      i=$((i + 1))
    done
    [ -e "$FM_QUEUE_DIR/release" ] || exit 1
    [ "${FM_QUEUE_ABORT:-0}" != 1 ] || exit 1
  fi
fi
exec "${BASH_SOURCE[0]%/*}/tmux-default" "$@"
SH
  chmod +x "$fakebin/tmux"
  printf '%s\n' "$dir"
}

start_queue_spawn() {  # <world> <task> <hold> [abort]
  local dir=$1 id=$2 hold=$3 abort=${4:-0}
  QUEUE_TEST_RELEASES+=("$dir/release")
  (
    rc=0
    FM_QUEUE_DIR="$dir" FM_QUEUE_TASK="$id" FM_QUEUE_HOLD="$hold" FM_QUEUE_ABORT="$abort" \
      FM_SPAWN_QUEUE_WAIT="${FM_TEST_QUEUE_WAIT:-120}" FM_FAKE_LAUNCH_LOG="$dir/$id.launch" \
      fm_test_run_spawn "$dir/home" "$dir/$id-wt" "$dir/fake/fakebin" \
        "$id=$dir/$id" --backend tmux --mode direct-PR --yolo off > "$dir/$id.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$dir/$id.exit"
    exit "$rc"
  ) &
  QUEUE_TEST_PIDS+=("$!")
}

wait_queue_marker() {  # <marker> <failure-output>
  local i=0
  while [ ! -e "$1" ] && [ "$i" -lt 600 ]; do
    /bin/sleep 0.1
    i=$((i + 1))
  done
  [ -e "$1" ] || fail "fixture did not reach $1: $(cat "$2" 2>/dev/null)"
}

wait_for_queued_spawn() {
  local dir=$1 id=$2 i=0
  while ! grep -F 'spawn-queued:' "$dir/$id.out" >/dev/null 2>&1 \
      && [ ! -e "$dir/$id.exit" ] && [ "$i" -lt 600 ]; do
    /bin/sleep 0.1
    i=$((i + 1))
  done
  assert_grep 'spawn-queued:' "$dir/$id.out" \
    "a sibling batch was rejected instead of queued: $(cat "$dir/$id.out")"
  assert_absent "$dir/$id.exit" 'the queued spawn completed before the prior publisher released'
}

finish_queue_spawns() {
  local pid
  for pid in "${QUEUE_TEST_PIDS[@]+"${QUEUE_TEST_PIDS[@]}"}"; do wait "$pid" 2>/dev/null || true; done
  QUEUE_TEST_PIDS=()
}

test_concurrent_batches_queue_until_publication() {
  local dir
  dir=$(make_queue_world concurrent-batches)
  start_queue_spawn "$dir" alpha 1
  wait_queue_marker "$dir/ready" "$dir/alpha.out"
  start_queue_spawn "$dir" bravo 0
  wait_for_queued_spawn "$dir" bravo
  assert_no_grep bravo "$dir/created" 'the second batch created an endpoint while the first publication was held'
  : > "$dir/release"
  finish_queue_spawns
  [ "$(cat "$dir/alpha.exit")" = 0 ] || fail "first batch failed: $(cat "$dir/alpha.out")"
  [ "$(cat "$dir/bravo.exit")" = 0 ] || fail "queued batch failed: $(cat "$dir/bravo.out")"
  assert_grep "worktree=$dir/alpha-wt" "$dir/home/state/alpha.meta" 'first publication was lost'
  assert_grep "worktree=$dir/bravo-wt" "$dir/home/state/bravo.meta" 'queued publication was lost'
  [ "$(grep -c '^alpha$' "$dir/created")" = 1 ] && [ "$(grep -c '^bravo$' "$dir/created")" = 1 ] \
    || fail 'queueing duplicated an endpoint creation'
  assert_absent "$dir/home/state/.spawn-queue.lock" 'successful batches retained the queue'
  assert_absent "$dir/home/state/.task-set.lock" 'successful batches retained publication authority'
  pass 'two different-project batches serialize fresh publication and both launch exactly once'
}

test_queued_batch_survives_an_earlier_spawn_failure() {
  local dir
  dir=$(make_queue_world failed-publisher)
  start_queue_spawn "$dir" alpha 1 1
  wait_queue_marker "$dir/ready" "$dir/alpha.out"
  start_queue_spawn "$dir" bravo 0
  wait_for_queued_spawn "$dir" bravo
  : > "$dir/release"
  finish_queue_spawns
  [ "$(cat "$dir/alpha.exit")" != 0 ] || fail 'the controlled earlier failure did not occur'
  [ "$(cat "$dir/bravo.exit")" = 0 ] || fail "an earlier failure stranded the queued batch: $(cat "$dir/bravo.out")"
  assert_present "$dir/home/state/bravo.meta" 'later batch did not publish its task'
  assert_absent "$dir/home/state/.spawn-queue.lock" 'failed publisher left queue authority behind'
  pass 'an aborted publication releases its queue position without dropping the next batch'
}

hold_queue_test_lock() {  # <world> <lock-basename>
  local dir=$1 name=$2
  QUEUE_TEST_RELEASES+=("$dir/release-holder")
  (
    export FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$dir/home/state"
    # shellcheck source=/dev/null
    . "$ROOT/bin/fm-wake-lib.sh"
    lock="$dir/home/state/$name"
    fm_lock_try_acquire "$lock" || exit 1
    trap 'fm_lock_release "$lock"' EXIT
    : > "$dir/holder-ready"
    while [ ! -e "$dir/release-holder" ]; do /bin/sleep 0.1; done
  ) > "$dir/holder.out" 2>&1 &
  QUEUE_TEST_PIDS+=("$!")
  wait_queue_marker "$dir/holder-ready" "$dir/holder.out"
}

test_queue_does_not_wait_past_a_teardown_publication_lock() {
  local dir
  dir=$(make_queue_world teardown-owner)
  hold_queue_test_lock "$dir" .task-set.lock
  start_queue_spawn "$dir" alpha 0
  wait_queue_marker "$dir/alpha.exit" "$dir/alpha.out"
  [ "$(cat "$dir/alpha.exit")" != 0 ] || fail 'spawn bypassed an independently held task-set lock'
  assert_grep 'task set is locked' "$dir/alpha.out" 'the existing teardown refusal was lost'
  assert_absent "$dir/created" 'teardown contention created an endpoint'
  assert_absent "$dir/home/state/alpha.meta" 'teardown contention published a task'
  assert_present "$dir/home/state/.task-set.lock" "spawn removed the other operation's lock"
  : > "$dir/release-holder"
  finish_queue_spawns
  assert_absent "$dir/home/state/.spawn-queue.lock" 'a refused spawn retained the queue'
  pass 'queueing fresh starts preserves the immediate refusal of independently owned teardown authority'
}

test_queue_timeout_defers_without_partial_launch() {
  local dir
  dir=$(make_queue_world bounded-queue)
  hold_queue_test_lock "$dir" .spawn-queue.lock
  FM_TEST_QUEUE_WAIT=1 start_queue_spawn "$dir" alpha 0
  wait_queue_marker "$dir/alpha.exit" "$dir/alpha.out"
  [ "$(cat "$dir/alpha.exit")" = 75 ] || fail "queue timeout was not reported as deferred: $(cat "$dir/alpha.out")"
  assert_grep 'spawn-deferred:' "$dir/alpha.out" 'queue timeout did not retain an actionable task identity'
  assert_grep 'batch: DEFERRED alpha' "$dir/alpha.out" 'batch mislabeled deferred work as an attempted launch failure'
  assert_absent "$dir/created" 'a queue timeout created an endpoint'
  assert_absent "$dir/home/state/alpha.meta" 'a queue timeout published task metadata'
  assert_present "$dir/home/state/.spawn-queue.lock" "queue timeout removed another owner's lock"
  : > "$dir/release-holder"
  finish_queue_spawns
  pass 'bounded queue waits report deferred targets without launching or removing another owner'
}

test_queued_spawn_refuses_replaced_state_directory() {
  local dir
  dir=$(make_queue_world replaced-state)
  hold_queue_test_lock "$dir" .spawn-queue.lock
  start_queue_spawn "$dir" alpha 0
  wait_for_queued_spawn "$dir" alpha
  mv "$dir/home/state" "$dir/prior-state"
  mkdir "$dir/home/state"
  : > "$dir/release-holder"
  finish_queue_spawns
  [ "$(cat "$dir/alpha.exit")" != 0 ] || fail 'a queued request adopted a replacement home state'
  assert_grep 'state directory changed while queued' "$dir/alpha.out" 'the replaced state was not identified'
  assert_absent "$dir/created" 'a stale queued request created an endpoint'
  assert_absent "$dir/home/state/alpha.meta" 'a stale queued request published into a new state directory'
  pass 'queued publication revalidates the original state directory before any endpoint mutation'
}

fm_test_run_cases \
  test_concurrent_batches_queue_until_publication \
  test_queued_batch_survives_an_earlier_spawn_failure \
  test_queue_does_not_wait_past_a_teardown_publication_lock \
  test_queue_timeout_defers_without_partial_launch \
  test_queued_spawn_refuses_replaced_state_directory

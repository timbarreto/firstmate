#!/usr/bin/env bash
# Bounded shutdown waits for isolated remote-job test children.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/remote-job-helpers.sh
. "$ROOT/tests/remote-job-helpers.sh"

FIXTURE_PID=
cleanup_wait_fixture() {
  if [ -n "$FIXTURE_PID" ]; then
    kill -KILL "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  fm_test_cleanup
}
trap cleanup_wait_fixture EXIT

test_stubborn_child_is_bounded_and_diagnosed() {
  local tmp started elapsed rc
  tmp=$(fm_test_tmproot fm-remote-wait)
  bash -c 'trap "" TERM; echo ready; echo "fixture shutdown diagnostic" >&2; exec sleep 10' \
    >"$tmp/stdout" 2>"$tmp/stderr" &
  FIXTURE_PID=$!
  started=$SECONDS
  while ! grep -q ready "$tmp/stdout"; do
    [ "$((SECONDS - started))" -lt 5 ] || fail "fixture did not become ready"
    sleep 0.05
  done
  kill -TERM "$FIXTURE_PID"
  started=$SECONDS
  fm_remote_job_wait_fixture_child "$FIXTURE_PID" 1 replacement "$tmp/stdout" "$tmp/stderr" \
    >"$tmp/wait.out" 2>"$tmp/wait.err" && rc=0 || rc=$?
  elapsed=$((SECONDS - started))
  [ "$rc" -ne 0 ] || fail "a child ignoring shutdown was reported as stopped"
  # Include diagnostic-command startup on Git for Windows, not just the wait.
  [ "$elapsed" -le 8 ] || fail "the bounded shutdown and diagnostics took ${elapsed}s"
  assert_grep 'replacement' "$tmp/wait.err" "timeout must identify the shutdown phase"
  assert_grep 'fixture shutdown diagnostic' "$tmp/wait.err" "timeout must retain child diagnostics"
  if kill -0 "$FIXTURE_PID" 2>/dev/null; then fail "timed-out fixture child survived cleanup"; fi
  FIXTURE_PID=
  pass "an unresponsive child fails promptly with phase and worker diagnostics"
}

test_completed_child_retains_wait_semantics() {
  local tmp
  tmp=$(fm_test_tmproot fm-remote-wait-complete)
  bash -c 'exit 7' >"$tmp/stdout" 2>"$tmp/stderr" &
  FIXTURE_PID=$!
  fm_remote_job_wait_fixture_child "$FIXTURE_PID" 3 completed "$tmp/stdout" "$tmp/stderr" \
    || fail "waiting for termination must not reinterpret the child exit status"
  FIXTURE_PID=
  pass "a completed child retains the existing wait-only semantics"
}

fm_test_run_cases \
  test_stubborn_child_is_bounded_and_diagnosed \
  test_completed_child_retains_wait_semantics

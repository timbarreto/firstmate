#!/usr/bin/env bash
# Coalesced summary requests exercise the writer's public interface with an
# isolated producer; no watcher, fleet, network, or model is started.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-home-summary-request)
CODE="$TMP_ROOT/code"
TEST_HOME="$TMP_ROOT/home"
mkdir -p "$CODE/bin" "$TEST_HOME/state"
for file in fm-home-summary-refresh.sh fm-timeout-lib.sh fm-wake-lib.sh fm-path-lib.sh; do
  cp "$ROOT/bin/$file" "$CODE/bin/$file"
done
cat > "$CODE/bin/fm-fleet-snapshot.sh" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'sample\n' >> "$FM_HOME/samples"
if [ "${FM_TEST_REQUEST_DURING_SAMPLE:-0}" = 1 ]; then
  "$FM_ROOT_OVERRIDE/bin/fm-home-summary-refresh.sh" --request
fi
[ "${FM_TEST_FAIL_SAMPLE:-0}" = 0 ] || exit 7
jq -n --arg home "$FM_HOME" '{schema:"fm-secondmate-home-summary.v1",
  hold_classifier_schema:"fm-captain-hold-buckets.v1",home:$home,
  generated:"2026-09-16T00:00:00Z",generated_epoch:1789516800,
  valid:true,state:"no_active_work",invalidity:{},active_children:[],
  decisions_open:[],holds:[],queued:[],landed:[],endpoints:[],counts:{},omitted:[]}'
SH
chmod +x "$CODE/bin/"*.sh
writer() {
  FM_ROOT_OVERRIDE="$CODE" FM_HOME="$TEST_HOME" FM_STATE_OVERRIDE="$TEST_HOME/state" \
    "$CODE/bin/fm-home-summary-refresh.sh" "$@"
}

writer --request
writer --request
[ -d "$TEST_HOME/state/.home-summary-refresh.request" ] || fail "request was not durable"
[ ! -e "$TEST_HOME/samples" ] || fail "request computed a summary"
writer --pending || fail "coalesced requests were not visible"
pass "summary requests coalesce without running a producer"

FM_TEST_REQUEST_DURING_SAMPLE=1 writer
[ -f "$TEST_HOME/state/home-summary.json" ] || fail "writer did not publish"
writer --pending || fail "publication erased the request arriving during its sample"
[ ! -e "$TEST_HOME/state/.home-summary-refresh.inflight" ] || fail "completed cohort was not retired"
writer
if writer --pending; then fail "settled requests still appeared pending"; fi
[ "$(wc -l < "$TEST_HOME/samples")" -eq 2 ] || fail "requests caused duplicate publications"
pass "publication leaves a later request for the next cohort"

cp "$TEST_HOME/state/home-summary.json" "$TMP_ROOT/prior.json"
writer --request
if FM_TEST_FAIL_SAMPLE=1 writer 2> "$TMP_ROOT/failure.err"; then fail "failed producer reported success"; fi
cmp -s "$TMP_ROOT/prior.json" "$TEST_HOME/state/home-summary.json" || fail "failure replaced the prior ledger"
writer --pending || fail "failed publication lost its request"
[ -d "$TEST_HOME/state/.home-summary-refresh.inflight" ] || fail "failed cohort was not retryable"
writer
if writer --pending; then fail "retry did not retire the failed cohort"; fi
pass "failed publication preserves both prior data and retryable work"

printf 'not a request directory\n' > "$TEST_HOME/state/.home-summary-refresh.request"
if writer --request 2> "$TMP_ROOT/request.err"; then fail "ordinary file was accepted as a request"; fi
if writer 2> "$TMP_ROOT/unsafe.err"; then fail "unsafe request was consumed"; fi
[ -f "$TEST_HOME/state/.home-summary-refresh.request" ] || fail "unsafe request was removed"
pass "unexpected request artifacts refuse without removing evidence"

# Pending-only refreshes and --service use fresh homes, so a detached servicer
# started by one case can never serve a request that a later case files.
home_writer() {  # <home> <writer args...>
  local home=$1
  shift
  FM_ROOT_OVERRIDE="$CODE" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    "$CODE/bin/fm-home-summary-refresh.sh" "$@"
}
fresh_home() {  # <name>
  mkdir -p "$TMP_ROOT/$1/state"
  printf '%s\n' "$TMP_ROOT/$1"
}
samples_in() {  # <home>
  if [ -f "$1/samples" ]; then wc -l < "$1/samples" | tr -d '[:space:]'; else printf '0\n'; fi
}
pending_in() {  # <home>
  [ -e "$1/state/.home-summary-refresh.request" ] || [ -e "$1/state/.home-summary-refresh.inflight" ]
}
settled() {  # <home> <samples>
  [ "$(samples_in "$1")" = "$2" ] && ! pending_in "$1" \
    && [ ! -e "$1/state/.home-summary-refresh.lock" ]
}
wait_until() {  # <seconds> <command...>
  local deadline=$((SECONDS + $1))
  shift
  until "$@"; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.1
  done
}
# Hold a home's refresh lock, as a publisher already running would, until
# <gate> exists; <gate>.held appears once the lock is held.
hold_lock() {  # <home> <gate>
  FM_HOME="$1" FM_STATE_OVERRIDE="$1/state" bash -c '
    . "$1"
    fm_lock_try_acquire "$2" || exit 1
    : > "$3.held"
    while [ ! -e "$3" ]; do sleep 0.1; done
    fm_lock_release "$2"
  ' _ "$CODE/bin/fm-wake-lib.sh" "$1/state/.home-summary-refresh.lock" "$2"
}

home=$(fresh_home idle-home)
FM_HOME_SUMMARY_IF_PENDING=1 home_writer "$home" || fail "an idle pending-only refresh failed"
[ "$(samples_in "$home")" = 0 ] || fail "a pending-only refresh sampled with nothing pending"
[ ! -e "$home/state/home-summary.json" ] || fail "a pending-only refresh published with nothing pending"
FM_HOME_SUMMARY_IF_PENDING=1 home_writer "$TMP_ROOT/retired-home" || fail "a pending-only refresh failed for a retired home"
[ ! -e "$TMP_ROOT/retired-home" ] || fail "a pending-only refresh recreated a retired home"
pass "a pending-only refresh does nothing when nothing is pending or the home is gone"

home_writer "$home" --request
FM_HOME_SUMMARY_IF_PENDING=1 home_writer "$home" || fail "a pending-only refresh failed"
[ "$(samples_in "$home")" = 1 ] || fail "a pending-only refresh did not publish pending work exactly once"
[ -f "$home/state/home-summary.json" ] || fail "a pending-only refresh did not publish"
! pending_in "$home" || fail "a pending-only refresh did not retire the work it published"
pass "a pending-only refresh publishes pending work once and retires it"

home=$(fresh_home served-home)
gate="$TMP_ROOT/served.gate"
home_writer "$home" --request
hold_lock "$home" "$gate" &
holder=$!
wait_until 60 test -e "$gate.held" || fail "the lock holder never took the refresh lock"
FM_HOME_SUMMARY_TIMEOUT=20 FM_HOME_SUMMARY_IF_PENDING=1 home_writer "$home" --best-effort &
servicer=$!
# The publisher ahead of the waiting refresh serves the request it was filed for.
rmdir "$home/state/.home-summary-refresh.request"
wait "$servicer" || fail "a pending-only refresh failed while waiting"
[ ! -e "$gate" ] || fail "the lock was released before the waiting refresh returned"
[ "$(samples_in "$home")" = 0 ] || fail "a pending-only refresh sampled work another publisher served"
[ ! -e "$home/state/.home-summary-refresh.log" ] \
  || fail "a pending-only refresh waited out its deadline: $(cat "$home/state/.home-summary-refresh.log")"
: > "$gate"
wait "$holder" || fail "the lock holder failed"
pass "a waiting pending-only refresh stops once the publisher ahead served its request"

home=$(fresh_home service-home)
gate="$TMP_ROOT/service.gate"
hold_lock "$home" "$gate" &
holder=$!
wait_until 60 test -e "$gate.held" || fail "the lock holder never took the refresh lock"
home_writer "$home" --request --service || fail "a serviced request failed"
home_writer "$home" --request --service || fail "a second serviced request failed"
[ "$(samples_in "$home")" = 0 ] || fail "a serviced request sampled while another publisher held the lock"
pending_in "$home" || fail "a serviced request was not durable"
: > "$gate"
wait "$holder" || fail "the lock holder failed"
wait_until 240 settled "$home" 1 \
  || fail "the background servicers did not publish the burst exactly once: samples=$(samples_in "$home")"
[ -f "$home/state/home-summary.json" ] || fail "the background servicer did not publish"
pass "--request --service returns at once and one background publication serves the burst"

home=$(fresh_home failing-home)
FM_TEST_FAIL_SAMPLE=1 home_writer "$home" --request --service || fail "a failing serviced request reported failure"
wait_until 240 test -s "$home/state/.home-summary-refresh.log" \
  || fail "a failed background publication left no diagnostic"
grep -q 'summary producer failed with exit 7' "$home/state/.home-summary-refresh.log" \
  || fail "a failed background publication logged the wrong cause: $(cat "$home/state/.home-summary-refresh.log")"
[ ! -e "$home/state/home-summary.json" ] || fail "a failed background publication wrote a ledger"
pending_in "$home" || fail "a failed background publication dropped its pending work"
pass "a failed background publication is logged and stays retryable"

rc=0
home_writer "$home" --service >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--service without --request was accepted (exit $rc)"
pass "--service is only accepted with --request"

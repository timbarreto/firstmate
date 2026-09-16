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
for file in fm-home-summary-refresh.sh fm-timeout-lib.sh fm-wake-lib.sh; do
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

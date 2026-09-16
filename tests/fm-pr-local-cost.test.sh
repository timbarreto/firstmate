#!/usr/bin/env bash
# Local PR costs through public helpers: pure URL parsing may be reused, but
# file identities and remote PR observations must remain fresh.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-pr-local-cost)
mkdir -p "$TMP_ROOT"
FM_TEST_REAL_PERL=$(command -v perl)
FM_TEST_CODEC_CALLS="$TMP_ROOT/codec-calls"
export FM_TEST_REAL_PERL FM_TEST_CODEC_CALLS
perl() {
  printf 'codec\n' >> "$FM_TEST_CODEC_CALLS"
  "$FM_TEST_REAL_PERL" "$@"
}
export -f perl
# shellcheck source=bin/fm-pr-lib.sh
. "$ROOT/bin/fm-pr-lib.sh"
URL='https://dev.azure.com/example-org/Example%20Project/_git/example-repo/pullrequest/42'
for iteration in 1 2 3 4 5 6 7 8; do
  fm_pr_url_parse "$URL" || fail "valid Azure identity refused on repetition $iteration"
  [ "$FM_PR_URL" = "$URL" ] || fail "cached identity changed the canonical URL"
done
[ "$(wc -l < "$FM_TEST_CODEC_CALLS")" -eq 1 ] || fail "identical pure Azure parsing repeatedly launched the codec"
fm_pr_url_parse "${URL%42}43" || fail "different valid identity refused"
[ "$FM_PR_NUMBER" = 43 ] || fail "a different URL borrowed the prior identity"
if fm_pr_url_parse "${URL}/extra"; then fail "invalid URL borrowed a valid identity"; fi
pass "pure Azure parsing is bounded without borrowing another input's identity"

# shellcheck source=tests/azure-pr-helpers.sh
. "$ROOT/tests/azure-pr-helpers.sh"
fm_test_azure_pr "$TMP_ROOT/azure"
export PATH="$TMP_ROOT/azure/fakebin:$PATH"
fm_pr_azure_record_read --azure-read "$URL" || fail "first Azure read failed"
[ "$FM_PR_AZURE_STATE" = active ] || fail "first observation was not active"
jq '.status="completed"' "$TMP_ROOT/azure/azure.json" > "$TMP_ROOT/azure/next.json"
mv "$TMP_ROOT/azure/next.json" "$TMP_ROOT/azure/azure.json"
fm_pr_azure_record_read --azure-read "$URL" || fail "second Azure read failed"
[ "$FM_PR_AZURE_STATE" = completed ] || fail "remote observation was incorrectly cached"
[ "$(wc -l < "$TMP_ROOT/azure/azure.log")" -eq 2 ] || fail "remote observation did not make two real fixture reads"
fm_pr_url_parse "$URL" || fail "identity parsing failed after observation"
[ -z "$FM_PR_AZURE_STATE$FM_PR_AZURE_HEAD" ] || fail "pure parsing retained an observation as authority"
pass "remote PR state is reread even when its canonical URL is unchanged"

printf 'original\n' > "$TMP_ROOT/record"
identity=$(fm_pr_file_identity "$TMP_ROOT/record") || fail "first identity failed"
printf 'replacement\n' > "$TMP_ROOT/replacement"
mv "$TMP_ROOT/replacement" "$TMP_ROOT/record"
replacement=$(fm_pr_file_identity "$TMP_ROOT/record") || fail "replacement identity failed"
[ "$identity" != "$replacement" ] || fail "file identity was cached across replacement"
pass "file identity remains fresh across path replacement"

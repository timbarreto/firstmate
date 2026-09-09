#!/usr/bin/env bash
# Strict catalog and runner integration contracts, using isolated metadata.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-test-catalog-lib.sh
. "$ROOT/bin/fm-test-catalog-lib.sh"

catalog_fixture() {
  local repo=$1 name
  mkdir -p "$repo/bin" "$repo/tests/catalog"
  cp "$ROOT/bin/fm-test-run.sh" "$ROOT/bin/fm-test-catalog-lib.sh" "$repo/bin/"
  for name in fm-brief fm-calm-pi-extension fm-new; do
    printf '#!/usr/bin/env bash\necho "ok - catalog fixture"\n' >"$repo/tests/$name.test.sh"
  done
  printf '%s\n' \
    $'version\t1' \
    $'family\tpure-contract-unit\tnone' \
    $'family\tunclassified\tnone' \
    $'test\ttests/fm-brief.test.sh\tpure-contract-unit' \
    $'test\ttests/fm-calm-pi-extension.test.sh\tpure-contract-unit' \
    $'duration\ttests/fm-brief.test.sh\t10' \
    $'map\towned\t10\tbin/owned.*\t__script__:fm-brief.test.sh' \
    $'map\tbroad\t20\tbin/*\tpure-contract-unit' >"$repo/tests/catalog/core.tsv"
  printf 'version\t1\n' >"$repo/tests/catalog/fork.tsv"
  cat >"$repo/bin/fm-test-isolation-proof.sh" <<'SH'
#!/usr/bin/env bash
[ -z "${CATALOG_PROOF_LOG:-}" ] || printf '%s\n' "$1" >>"$CATALOG_PROOF_LOG"
case "$1" in
  --list) printf '%s\n' tests/fm-brief.test.sh ;;
  --list-family-admissions) printf 'pure-contract-unit\ttests/fm-calm-pi-extension.test.sh\n' ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$repo/bin/"*.sh
}

expect_bad_catalog() {
  local repo=$1 expected=$2 out rc
  out=$(fm_test_catalog_load "$repo" 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 2 ] || fail "invalid catalog must refuse with exit 2: $out"
  assert_contains "$out" "$expected" "catalog refusal must be actionable"
}

test_catalog_overrides_and_ordering() {
  local tmp repo selected
  tmp=$(fm_test_tmproot fm-catalog-order)
  repo="$tmp/repo"
  catalog_fixture "$repo"
  printf '%s\n' \
    $'override-test\ttests/fm-brief.test.sh\tpure-contract-unit\tunclassified' \
    $'override-duration\ttests/fm-brief.test.sh\t10\t40' \
    $'override-map\towned\t10\tbin/owned.*\t__script__:fm-brief.test.sh\t5\tbin/owned.*\t__script__:fm-calm-pi-extension.test.sh' \
    >>"$repo/tests/catalog/fork.tsv"
  fm_test_catalog_load "$repo" || fail "valid overrides must load"
  fm_test_catalog_get test tests/fm-brief.test.sh || fail "registered test missing"
  [ "$FM_TEST_CATALOG_VALUE" = unclassified ] || fail "test override not applied"
  fm_test_catalog_get duration tests/fm-brief.test.sh || fail "duration missing"
  [ "$FM_TEST_CATALOG_VALUE" = 40 ] || fail "duration override not applied"
  selected=$(fm_test_catalog_maps bin/owned.sh) || fail "owned path is unmapped"
  [ "$selected" = __script__:fm-calm-pi-extension.test.sh ] || fail "ordered override lost to broad map"
  [ "$(fm_test_catalog_maps bin/other.sh)" = pure-contract-unit ] || fail "broad fallback lost"
  if fm_test_catalog_get test tests/missing.test.sh; then fail "absent metadata must not invent a value"; fi
  printf 'invalid\n' >"$repo/tests/catalog/fork.tsv"
  fm_test_catalog_get duration tests/fm-brief.test.sh || fail "in-memory metadata disappeared"
  [ "$FM_TEST_CATALOG_VALUE" = 40 ] || fail "lookup reread mutated disk metadata"
  expect_bad_catalog "$repo" 'expected version'
  pass "exact overrides, first-match ordering and invocation-scoped metadata"
}

test_catalog_rejects_invalid_records() {
  local tmp repo row expected
  tmp=$(fm_test_tmproot fm-catalog-invalid)
  repo="$tmp/repo"
  catalog_fixture "$repo"
  while IFS='~' read -r expected row; do
    printf 'version\t1\n%s\n' "$row" >"$repo/tests/catalog/fork.tsv"
    expect_bad_catalog "$repo" "$expected"
  done <<'ROWS'
unknown record kind~command	run	echo
wrong field count~duration	tests/fm-brief.test.sh	5	extra
duplicate key~test	tests/fm-brief.test.sh	pure-contract-unit
unknown family~test	tests/fm-new.test.sh	missing-family
missing or not a root-level test~test	tests/absent.test.sh	pure-contract-unit
duration references missing test~duration	tests/absent.test.sh	20
invalid duration~duration	tests/fm-new.test.sh	0
invalid duration~duration	tests/fm-new.test.sh	-1
invalid duration~duration	tests/fm-new.test.sh	1e3
invalid duration~duration	tests/fm-new.test.sh	2147483648
unknown gate~family	demo	unsafe
stale override~override-duration	tests/fm-brief.test.sh	11	20
no existing key~override-duration	tests/fm-new.test.sh	10	20
invalid map order~map	bad	0	bin/*	pure-contract-unit
duplicate map order~map	bad	10	bin/other	pure-contract-unit
unknown map family~map	bad	30	bin/other	no-such-family
map references missing test~map	bad	30	bin/other	__script__:absent.test.sh
invalid repository-relative map glob~map	bad	30	../escape	pure-contract-unit
invalid repository-relative map glob~map	bad	30	bin/$(touch-owned)	pure-contract-unit
invalid repository-relative map glob~map	bad	30	bin/*|	pure-contract-unit
invalid map target~map	bad	30	bin/other	pure-contract-unit,
ROWS
  printf '%s\n' $'version\t1' \
    $'override-duration\ttests/fm-brief.test.sh\t10\t20' \
    $'override-duration\ttests/fm-brief.test.sh\t20\t30' >"$repo/tests/catalog/fork.tsv"
  expect_bad_catalog "$repo" 'duplicate override'
  printf 'version\t1\n' >"$repo/tests/catalog/fork.tsv"
  printf 'override-duration\ttests/fm-brief.test.sh\t10\t20\n' >>"$repo/tests/catalog/core.tsv"
  expect_bad_catalog "$repo" 'overrides belong in fork.tsv'
  pass "malformed metadata, stale overrides, missing tests and shell syntax are refused"
}

test_catalog_missing_dependencies_refuse() {
  local tmp repo out rc
  tmp=$(fm_test_tmproot fm-catalog-missing)
  repo="$tmp/repo"
  catalog_fixture "$repo"
  rm "$repo/tests/catalog/fork.tsv"
  out=$("$repo/bin/fm-test-run.sh" --list --all 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 2 ] || fail "missing fork catalog must stop selection"
  assert_contains "$out" 'required catalog is missing' "missing catalog diagnostic"
  printf 'version\t1\n' >"$repo/tests/catalog/fork.tsv"
  rm "$repo/bin/fm-test-isolation-proof.sh"
  out=$("$repo/bin/fm-test-run.sh" --list --all 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 2 ] || fail "missing proof owner must stop selection"
  assert_contains "$out" 'required isolation proof owner is missing' "missing proof diagnostic"
  rm "$repo/bin/fm-test-catalog-lib.sh"
  out=$("$repo/bin/fm-test-run.sh" --list --all 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 2 ] || fail "missing loader must stop selection"
  assert_contains "$out" 'required test catalog loader is missing' "missing loader diagnostic"
  pass "missing dependencies stop the public runner without legacy fallbacks"
}

test_catalog_cannot_grant_concurrency() {
  local tmp repo out rc
  tmp=$(fm_test_tmproot fm-catalog-admission)
  repo="$tmp/repo"
  catalog_fixture "$repo"
  printf 'test\ttests/fm-new.test.sh\tpure-contract-unit\n' >>"$repo/tests/catalog/fork.tsv"
  out=$("$repo/bin/fm-test-run.sh" --jobs 2 tests/fm-new.test.sh 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 2 ] || fail "catalog classification must not grant family concurrency: $out"
  assert_contains "$out" 'not in the proven-isolated set' "proof refusal"
  out=$("$repo/bin/fm-test-run.sh" tests/fm-new.test.sh 2>&1) \
    || fail "classified but unproven test must remain runnable serially: $out"
  assert_contains "$out" 'FM_TEST_SUMMARY total=1 failed=0' "new test serial result"
  out=$("$repo/bin/fm-test-run.sh" --jobs 5 tests/fm-calm-pi-extension.test.sh 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 2 ] || fail "metadata must not raise the family cap"
  printf 'override-test\ttests/fm-calm-pi-extension.test.sh\tpure-contract-unit\tunclassified\n' \
    >>"$repo/tests/catalog/fork.tsv"
  out=$("$repo/bin/fm-test-run.sh" --jobs 2 tests/fm-calm-pi-extension.test.sh 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 2 ] || fail "reclassification must not reuse a different family proof"
  pass "new registrations and family changes cannot manufacture concurrency proof"
}

test_catalog_list_has_no_new_dependencies_or_row_processes() {
  local tmp repo fakebin tool out real_awk
  tmp=$(fm_test_tmproot fm-catalog-lightweight)
  repo="$tmp/repo"
  fakebin="$tmp/fakebin"
  catalog_fixture "$repo"
  mkdir -p "$fakebin"
  for tool in node jq python3; do
    printf '#!/usr/bin/env bash\necho forbidden >>"$CATALOG_FORBIDDEN"\nexit 99\n' >"$fakebin/$tool"
  done
  cat >"$fakebin/awk" <<'SH'
#!/usr/bin/env bash
echo awk >>"$CATALOG_AWK_LOG"
exec "$CATALOG_REAL_AWK" "$@"
SH
  chmod +x "$fakebin/"*
  real_awk=$(command -v awk)
  out=$(PATH="$fakebin:$PATH" CATALOG_REAL_AWK="$real_awk" \
    CATALOG_AWK_LOG="$tmp/awk-log" CATALOG_FORBIDDEN="$tmp/forbidden" \
    CATALOG_PROOF_LOG="$tmp/proof-log" "$repo/bin/fm-test-run.sh" --list --all) \
    || fail "lightweight listing acquired a new dependency"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 3 ] || fail "flat inventory changed"
  [ ! -e "$tmp/forbidden" ] || fail "list mode invoked Node, jq or Python"
  [ "$(wc -l <"$tmp/awk-log" | tr -d ' ')" = 1 ] || fail "metadata must use one bulk parser"
  [ "$(grep -c '^--list$' "$tmp/proof-log")" = 1 ] || fail "portable proof must be read once"
  [ "$(grep -c '^--list-family-admissions$' "$tmp/proof-log")" = 1 ] || fail "family proof must be read once"
  pass "list mode validates metadata once with Bash/awk and cached proof results"
}

fm_test_run_cases \
  test_catalog_overrides_and_ordering \
  test_catalog_rejects_invalid_records \
  test_catalog_missing_dependencies_refuse \
  test_catalog_cannot_grant_concurrency \
  test_catalog_list_has_no_new_dependencies_or_row_processes

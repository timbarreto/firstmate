#!/usr/bin/env bash
# Strict catalog and runner integration contracts, using isolated metadata.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-test-catalog-lib.sh
. "$ROOT/bin/fm-test-catalog-lib.sh"
# shellcheck source=tests/private-path-helpers.sh
. "$ROOT/tests/private-path-helpers.sh"

catalog_fixture() {
  local repo=$1 name
  mkdir -p "$repo/bin" "$repo/tests/catalog"
  fm_test_install_private_paths "$repo" || fail "could not install private-path fixture dependencies"
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
    $'parallel-duration\ttests/fm-brief.test.sh\t100' \
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

test_catalog_preserves_existing_gate_classes() {
  local family expected
  fm_test_catalog_load "$ROOT" || fail "real catalogs must load"
  while IFS= read -r family; do
    [ -n "$family" ] || continue
    case "$family" in
      real-herdr-gated) expected=herdr ;;
      live-harness-optin) expected=live-capability ;;
      cmux|zellij|orca|snapshot-bearings) expected=optional-binary ;;
      *) expected=none ;;
    esac
    fm_test_catalog_get family "$family" || fail "family gate missing: $family"
    assert_equals "$expected" "$FM_TEST_CATALOG_VALUE" "existing gate class changed for $family"
  done <<<"$FM_TEST_CATALOG_FAMILIES"
  fm_test_catalog_get test tests/fm-herdr-pi-stale-registration-live-e2e.test.sh \
    || fail "stale-registration live guard is unclassified"
  assert_equals live-harness-optin "$FM_TEST_CATALOG_VALUE" "live guard lost its capability gate"
  assert_equals "$(printf 'backend-dispatch\nreal-herdr-gated\npure-contract-unit\norca\nlive-harness-optin\n__script__:fm-backend-herdr-treehouse.test.sh')" \
    "$(fm_test_catalog_maps bin/fm-agent-process-lib.sh)" "shared classifier must select both backend consumers"
  assert_equals "$(printf 'real-herdr-gated\nbackend-dispatch\npure-contract-unit')" \
    "$(fm_test_catalog_maps tests/herdr-client-pair-fixture.sh)" "Herdr fixture must select its backend consumers"
  pass "every existing family retains its pre-extraction gate class"
}

test_catalog_lookup_cost_is_bounded() {
  local started elapsed iteration
  fm_test_catalog_load "$ROOT" || fail "real catalogs must load"
  started=$SECONDS
  for ((iteration=0; iteration<100; iteration++)); do
    fm_test_catalog_get test tests/fm-x-mode.test.sh || fail "registered test missing"
    assert_equals pr-forge "$FM_TEST_CATALOG_VALUE" "lookup changed classification"
  done
  elapsed=$((SECONDS - started))
  [ "$elapsed" -lt 5 ] || fail "100 cached lookups took ${elapsed}s; expected under 5s"
  pass "cached lookups stay below a generous hot-path time bound"
}

test_catalog_cache_keys_and_reload() {
  local tmp repo name weight=10
  tmp=$(fm_test_tmproot fm-catalog-cache)
  repo="$tmp/repo"
  catalog_fixture "$repo"
  for name in cache-key cache_key cache.key cache_hkey; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/tests/$name.test.sh"
    printf 'duration\ttests/%s.test.sh\t%s\n' "$name" "$weight" >>"$repo/tests/catalog/fork.tsv"
    weight=$((weight + 10))
  done
  fm_test_catalog_load "$ROOT" || fail "real catalogs must load"
  fm_test_catalog_get test tests/fm-x-mode.test.sh || fail "real registration missing"
  fm_test_catalog_load "$repo" || fail "fixture catalogs must load"
  if fm_test_catalog_get test tests/fm-x-mode.test.sh; then fail "reload retained a stale registration"; fi
  if fm_test_catalog_get parallel-duration tests/fm-x-mode.test.sh; then fail "reload retained a stale parallel hint"; fi
  assert_equals $'tests/fm-brief.test.sh 100\n' "$FM_TEST_CATALOG_PARALLEL_WEIGHTS" "parallel hint cache was not replaced"
  weight=10
  for name in cache-key cache_key cache.key cache_hkey; do
    fm_test_catalog_get duration "tests/$name.test.sh" || fail "duration missing for $name"
    assert_equals "$weight" "$FM_TEST_CATALOG_VALUE" "distinct keys collided"
    weight=$((weight + 10))
  done
  fm_test_catalog_get map owned || fail "map lookup missing"
  assert_equals $'10\tbin/owned.*\t__script__:fm-brief.test.sh' "$FM_TEST_CATALOG_VALUE" "map record changed"
  if fm_test_catalog_get test 'tests/invalid[0].test.sh'; then fail "invalid key acquired a value"; fi
  pass "cache keys remain distinct and reloads replace prior registrations"
}

test_catalog_overrides_and_ordering() {
  local tmp repo selected
  tmp=$(fm_test_tmproot fm-catalog-order)
  repo="$tmp/repo"
  catalog_fixture "$repo"
  printf '%s\n' \
    $'override-test\ttests/fm-brief.test.sh\tpure-contract-unit\tunclassified' \
    $'override-duration\ttests/fm-brief.test.sh\t10\t40' \
    $'override-parallel-duration\ttests/fm-brief.test.sh\t100\t2' \
    $'override-map\towned\t10\tbin/owned.*\t__script__:fm-brief.test.sh\t5\tbin/owned.*\t__script__:fm-calm-pi-extension.test.sh' \
    >>"$repo/tests/catalog/fork.tsv"
  fm_test_catalog_load "$repo" || fail "valid overrides must load"
  fm_test_catalog_get test tests/fm-brief.test.sh || fail "registered test missing"
  [ "$FM_TEST_CATALOG_VALUE" = unclassified ] || fail "test override not applied"
  fm_test_catalog_get duration tests/fm-brief.test.sh || fail "duration missing"
  [ "$FM_TEST_CATALOG_VALUE" = 40 ] || fail "duration override not applied"
  fm_test_catalog_get parallel-duration tests/fm-brief.test.sh || fail "parallel duration missing"
  [ "$FM_TEST_CATALOG_VALUE" = 2 ] || fail "parallel duration override not applied independently"
  assert_equals $'tests/fm-brief.test.sh 40\n' "$FM_TEST_CATALOG_WEIGHTS" "parallel override changed serial weights"
  assert_equals $'tests/fm-brief.test.sh 2\n' "$FM_TEST_CATALOG_PARALLEL_WEIGHTS" "parallel override missing from bulk weights"
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
duration references missing test~parallel-duration	tests/absent.test.sh	20
invalid duration~parallel-duration	tests/fm-new.test.sh	0
invalid duration~parallel-duration	tests/fm-new.test.sh	1e3
stale override~override-parallel-duration	tests/fm-brief.test.sh	101	20
duplicate key~parallel-duration	tests/fm-brief.test.sh	20
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
    # shellcheck disable=SC2016 # The generated shim reads the invocation environment.
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

test_catalog_module_reference_and_lint_membership() {
  local tmp repo path index=0 selected full changed
  local -a modules=(bin/harnesses/pilot.sh bin/platform/native.sh
    bin/platform/process.mjs bin/platform/process.d.mts bin/platform/native.ps1)
  tmp=$(fm_test_tmproot fm-catalog-modules)
  repo="$tmp/repo"
  catalog_fixture "$repo"
  cp "$ROOT/bin/fm-lint.sh" "$repo/bin/"
  mkdir -p "$repo/bin/backends"
  printf '#!/usr/bin/env bash\n' >"$repo/bin/backends/stub.sh"
  full=$(CI=true "$repo/bin/fm-lint.sh" --list-files) || fail "full lint listing failed"
  while IFS= read -r path; do
    [ -f "$repo/$path" ] || fail "full lint listed a nonexistent input: $path"
  done <<<"$full"
  mkdir -p "$repo/bin/harnesses" "$repo/bin/platform"
  printf '%s\n' \
    $'override-map\tbroad\t20\tbin/*\tpure-contract-unit\t20\tlegacy/*\tpure-contract-unit' \
    >>"$repo/tests/catalog/fork.tsv"
  for path in "${modules[@]}"; do
    index=$((index + 1))
    printf '# dependency-%s.sh\n' "$index" >"$repo/$path"
    printf '# dependency\n' >"$repo/bin/dependency-$index.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/tests/module-$index.test.sh"
    printf 'map\tmodule-%s\t%s\t%s\t__script__:module-%s.test.sh\n' \
      "$index" "$((20 + index))" "$path" "$index" >>"$repo/tests/catalog/fork.tsv"
  done
  git -C "$repo" init -q
  git -C "$repo" add .
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm baseline
  git -C "$repo" branch -M main
  git -C "$repo" checkout -qb catalog-change
  for index in 1 2 3 4 5; do
    printf '# changed dependency\n' >>"$repo/bin/dependency-$index.sh"
  done
  selected=$("$repo/bin/fm-test-run.sh" --list --changed --base main) \
    || fail "module consumers must resolve changed dependencies"
  for index in 1 2 3 4 5; do
    assert_contains "$selected" "tests/module-$index.test.sh" "every module kind must select its consumer"
  done
  [ "$(printf '%s\n' "$selected" | wc -l | tr -d ' ')" = 5 ] \
    || fail "module references must not select unrelated tests"
  full=$(CI=true "$repo/bin/fm-lint.sh" --list-files) || fail "full lint listing failed"
  for path in bin/harnesses/pilot.sh bin/platform/native.sh; do
    printf '# changed module\n' >>"$repo/$path"
  done
  changed=$(CI=false GITHUB_ACTIONS=false "$repo/bin/fm-lint.sh" --list-files) \
    || fail "changed lint listing failed"
  for path in bin/harnesses/pilot.sh bin/platform/native.sh; do
    assert_contains "$full" "$path" "full lint must include new shell directories"
    assert_contains "$changed" "$path" "changed lint must include new shell directories"
  done
  pass "shell, module, declaration and native consumers retain reference routing and lint coverage"
}

fm_test_run_cases \
  test_catalog_preserves_existing_gate_classes \
  test_catalog_lookup_cost_is_bounded \
  test_catalog_cache_keys_and_reload \
  test_catalog_overrides_and_ordering \
  test_catalog_rejects_invalid_records \
  test_catalog_missing_dependencies_refuse \
  test_catalog_cannot_grant_concurrency \
  test_catalog_list_has_no_new_dependencies_or_row_processes \
  test_catalog_module_reference_and_lint_membership

#!/usr/bin/env bash
# Test-only dependency installation for isolated runner fixtures.
# Call fm_test_install_catalog <fixture-root> after creating/changing its tests.
# Installs the real loader, minimal valid metadata and a fixture proof owner.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_test_install_catalog() {
  local repo=$1 records proof admissions path
  local -a inventory=()
  mkdir -p "$repo/bin" "$repo/tests/catalog"
  cp "$ROOT/bin/fm-test-catalog-lib.sh" "$repo/bin/fm-test-catalog-lib.sh"
  # shellcheck source=bin/fm-test-catalog-lib.sh
  . "$ROOT/bin/fm-test-catalog-lib.sh"
  fm_test_catalog_load "$ROOT" || fail "could not load real catalog for fixture"
  records=$FM_TEST_CATALOG_RECORDS
  for path in "$repo"/tests/*.test.sh; do
    [ -f "$path" ] || continue
    inventory+=("tests/${path##*/}")
  done
  awk -F '\t' '
    NR == FNR { if ($0 != "") present[$0] = 1; next }
    BEGIN { OFS = "\t" }
    $1 == "family" { print; next }
    $1 == "test" || $1 == "duration" { if ($2 in present) print; next }
    $1 == "map" {
      count = split($5, targets, ",")
      selected = ""
      for (i = 1; i <= count; i++) {
        path = targets[i]
        if (sub(/^__script__:/, "tests/", path) && !(path in present)) continue
        selected = selected (selected == "" ? "" : ",") targets[i]
      }
      if (selected != "") print $1, $2, $3, $4, selected
    }
  ' <(printf '%s\n' "${inventory[@]+"${inventory[@]}"}") <(printf '%s' "$records") >"$repo/tests/catalog/records"
  {
    printf 'version\t1\n'
    cat "$repo/tests/catalog/records"
  } >"$repo/tests/catalog/core.tsv"
  rm "$repo/tests/catalog/records"
  printf 'version\t1\n' >"$repo/tests/catalog/fork.tsv"
  proof=$("$ROOT/bin/fm-test-isolation-proof.sh" --list) || fail "could not read portable proof"
  admissions=$("$ROOT/bin/fm-test-isolation-proof.sh" --list-family-admissions) \
    || fail "could not read family admissions"
  {
    # shellcheck disable=SC2016 # The selector is evaluated by the generated fixture.
    printf '#!/usr/bin/env bash\ncase "${1:-}" in\n  --list)\n    cat <<'"'"'EOF'"'"'\n'
    for path in $proof; do
      [ ! -f "$repo/$path" ] || printf '%s\n' "$path"
    done
    printf 'EOF\n    ;;\n  --list-family-admissions)\n    cat <<'"'"'EOF'"'"'\n'
    awk -F '\t' 'NR == FNR { present[$0] = 1; next } $2 in present' \
      <(printf '%s\n' "${inventory[@]+"${inventory[@]}"}") <(printf '%s\n' "$admissions")
    printf 'EOF\n    ;;\n  *) exit 2 ;;\nesac\n'
  } >"$repo/bin/fm-test-isolation-proof.sh"
  chmod +x "$repo/bin/fm-test-isolation-proof.sh"
}

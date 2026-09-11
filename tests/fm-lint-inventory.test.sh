#!/usr/bin/env bash
# Full-inventory audit of the local no-external-sources exclusion list.
# Kept outside the fast lint contracts so the serial CI lanes own this sweep.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LINT="$ROOT/bin/fm-lint.sh"
REQUIRED=$("$LINT" --required-version)

fm_lint_nox_one_root() {
  local index=$1 path=$2 outdir=$3
  shellcheck --norc --format gcc -- "$path" > "$outdir/$index" || true
}

test_local_exclusion_list_covers_every_no_external_sources_code() {
  if ! command -v shellcheck >/dev/null 2>&1 \
    || [ "$(shellcheck --version | awk '/^version:/ {print $2; exit}')" != "$REQUIRED" ]; then
    pass "SKIP (ShellCheck $REQUIRED not resolved): local exclusion completeness"
    return
  fi
  local tmp files_file out unexpected code path found i batch
  local -a files
  tmp=$(fm_test_tmproot fm-lint-nox-complete)
  files_file="$tmp/files"
  CI=true "$LINT" --list-files > "$files_file"
  [ -s "$files_file" ] || fail "CI --list-files returned no canonical lint roots"
  files=()
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    files+=("$path")
  done < "$files_file"
  [ "${#files[@]}" -gt 0 ] || fail "CI --list-files returned no readable lint roots"
  mkdir -p "$tmp/gcc"
  i=0
  batch=0
  for path in "${files[@]}"; do
    i=$((i + 1))
    fm_lint_nox_one_root "$i" "$path" "$tmp/gcc" &
    batch=$((batch + 1))
    if [ "$batch" -eq 4 ]; then
      wait
      batch=0
    fi
  done
  wait
  found=$(find "$tmp/gcc" -type f | wc -l | tr -d '[:space:]')
  [ "$found" = "${#files[@]}" ] \
    || fail "completeness sweep linted $found roots, expected ${#files[@]}"
  out=$(cat "$tmp/gcc"/* 2>/dev/null || true)
  unexpected=
  while IFS= read -r code; do
    [ -n "$code" ] || continue
    case "$code" in
      SC1091|SC2034|SC2153|SC2329) ;;
      *) unexpected="${unexpected}${unexpected:+ }$code" ;;
    esac
  done < <(printf '%s\n' "$out" | sed -n 's/.*\[\(SC[0-9][0-9]*\)\].*/\1/p' | LC_ALL=C sort -u)
  [ -z "$unexpected" ] \
    || fail "no-external-sources pass emitted codes outside the local exclusion list: $unexpected"
  pass "local exclusion list covers every no-external-sources ShellCheck code"
}

fm_test_run_cases test_local_exclusion_list_covers_every_no_external_sources_code

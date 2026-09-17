#!/usr/bin/env bash
# Public spelling/context contracts; path conversion never grants access.
# Platform overrides are intentionally confined to the individual test subshell.
# shellcheck disable=SC2030,SC2031
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-path-lib.sh
. "$ROOT/bin/fm-path-lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-path)

test_path_absolute_preserves_literal_and_caller_state() (
  # shellcheck disable=SC2016 # The path must retain shell-shaped data literally.
  local value='relative café '\'' [x] & $(not-executed); two  spaces' result expected before
  local present='unchanged'
  cd "$TMP_ROOT" || fail "path fixture missing"
  set -f
  set -- 'first argument' 'second *'
  IFS=':|'
  before=$-
  expected="$PWD/$value"
  fm_path_absolute "$value" result > "$TMP_ROOT/stdout" || fail "relative literal conversion failed"
  assert_equals "$expected" "$result" "relative path was evaluated or changed"
  [ ! -s "$TMP_ROOT/stdout" ] || fail "destination interface printed output"
  [ "$#" = 2 ] && [ "$1" = 'first argument' ] && [ "$2" = 'second *' ] || fail "path conversion changed arguments"
  [ "$IFS" = ':|' ] && [ "$-" = "$before" ] && [ "$PWD" = "$TMP_ROOT" ] || fail "path conversion changed caller state"
  fm_path_absolute '/abs/./literal/../path' result || fail "absolute spelling conversion failed"
  assert_equals '/abs/./literal/../path' "$result" "path spelling performed unauthorized canonicalization"
  fm_path_absolute './not-created' result || fail "uncreated path spelling was rejected"
  assert_equals "$PWD/./not-created" "$result" "uncreated path spelling changed"
  [ ! -e "$result" ] || fail "path spelling created a directory"
  fm_path_absolute '/literal' > "$TMP_ROOT/actual"
  printf '/literal' > "$TMP_ROOT/expected"
  cmp -s "$TMP_ROOT/expected" "$TMP_ROOT/actual" || fail "stdout interface added bytes"
  if fm_path_absolute '' present >/dev/null 2>&1; then fail "empty path accepted"; fi
  assert_equals unchanged "$present" "failed conversion changed its destination"
  if fm_path_absolute /literal 'value[0]' >/dev/null 2>&1; then fail "unsafe destination accepted"; fi
  pass "absolute path spelling preserves literal bytes, caller state, and missing-path semantics"
)

test_path_posix_does_not_require_native_conversion() (
  local result calls="$TMP_ROOT/cygpath-calls"
  # shellcheck disable=SC2329 # The public helper may invoke this external-tool double.
  cygpath() { : > "$calls"; return 97; }
  fm_path_absolute /already/absolute result || fail "POSIX path acquired a converter dependency"
  [ ! -e "$calls" ] || fail "POSIX path invoked Windows conversion"
  assert_equals /already/absolute "$result" "POSIX absolute path changed"
  OSTYPE=linux-gnu
  fm_path_absolute 'C:\literal-name' result || fail "POSIX literal filename was rejected"
  assert_equals "$PWD/C:\literal-name" "$result" "POSIX filename became Windows syntax"
  pass "POSIX paths remain in process and foreign-looking POSIX filenames stay literal"
)

test_path_windows_spellings_and_refusals() (
  local dir form input result original=unchanged
  case "${OSTYPE:-}" in msys*|cygwin*) ;; *) return 0 ;; esac
  dir="$TMP_ROOT/windows café '[x] & space"
  mkdir -p "$dir"
  for form in posix mixed native; do
    input=$dir
    case "$form" in
      mixed) input=$(cygpath -m "$dir") ;;
      native) input=$(cygpath -w "$dir") ;;
    esac
    fm_path_absolute "$input" result || fail "$form path spelling was refused"
    [ "$dir" -ef "$result" ] || fail "$form conversion changed directory identity"
    case "$result" in /*) ;; *) fail "$form did not produce an absolute Bash path" ;; esac
  done
  for input in 'C:relative' 'C:' '\current-drive'; do
    if fm_path_absolute "$input" original >/dev/null 2>&1; then fail "ambiguous Windows path was accepted: $input"; fi
    assert_equals unchanged "$original" "ambiguous conversion changed the destination"
  done
  # Conversion itself does not contact or authorize a network share.
  fm_path_absolute '\\server\share\literal path' result || fail "UNC spelling conversion failed"
  assert_equals '//server/share/literal path' "$result" "UNC spelling changed"
  fm_path_absolute '\\server\share' result || fail "UNC root spelling conversion failed"
  assert_equals '//server/share' "$result" "UNC root spelling changed"
  fm_path_absolute 'C:\literal\link\..\state' result || fail "path component preservation failed"
  case "$result" in */literal/link/../state) ;; *) fail "conversion collapsed a path before symlink checks: $result" ;; esac
  fm_path_absolute $'C:\\literal\\last\n\n' result || fail "literal newline-tail conversion failed"
  case "$result" in *$'/literal/last\n\n') ;; *) fail "conversion stripped literal trailing bytes" ;; esac
  # shellcheck disable=SC2329 # The conversion dependency is a command lookup.
  command() {
    if [ "$#" = 2 ] && [ "$1" = -v ] && [ "$2" = cygpath ]; then return 1; fi
    builtin command "$@"
  }
  if fm_path_absolute 'C:\literal' original >/dev/null 2>&1; then fail "missing conversion was silently bypassed"; fi
  assert_equals unchanged "$original" "missing converter changed the destination"
  pass "Windows drive and UNC spellings are explicit, identity-preserving, and refuse ambiguous inputs"
)

test_native_path_argument_reaches_real_consumer() {
  local dir native
  dir="$TMP_ROOT/native argument café '[x] & space"
  mkdir -p "$dir"
  fm_path_native_argument "$dir" native || fail "native argument conversion failed"
  git -C "$native" init -q || fail "Git could not consume the explicit native path"
  git -C "$native" rev-parse --is-inside-work-tree > "$TMP_ROOT/git-result" || fail "native Git argument lost the directory"
  assert_equals true "$(cat "$TMP_ROOT/git-result")" "native Git did not see the fixture directory"
  [ -d "$dir/.git" ] || fail "native path conversion redirected Git to a different directory"
  pass "explicit path arguments reach the real native consumer with Unicode and metacharacters intact"
}

test_path_context_preserves_empty_overrides_and_stages_failures() (
  local before_home before_root
  unset FM_ROOT FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_PROJECTS_OVERRIDE FM_CONFIG_OVERRIDE
  FM_HOME='./home path'
  FM_DATA_OVERRIDE=''
  before_home=$FM_HOME
  fm_path_normalize_context > "$TMP_ROOT/context.stdout" || fail "context normalization failed"
  assert_equals "$PWD/$before_home" "$FM_HOME" "home was not anchored to the caller"
  [ -z "${FM_STATE_OVERRIDE+x}" ] && [ -z "$FM_DATA_OVERRIDE" ] || fail "context changed fallback presence/emptiness"
  [ ! -s "$TMP_ROOT/context.stdout" ] || fail "context initialization printed output"
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      FM_ROOT='./code root'
      FM_HOME='./home again'
      FM_DATA_OVERRIDE='C:ambiguous'
      before_root=$FM_ROOT before_home=$FM_HOME
      if fm_path_normalize_context >/dev/null 2>&1; then fail "invalid context path was accepted"; fi
      assert_equals "$before_root" "$FM_ROOT" "failed context partially changed the code root"
      assert_equals "$before_home" "$FM_HOME" "failed context partially changed the home"
      ;;
  esac
  pass "context initialization preserves fallback semantics and stages conversions before applying them"
)

fm_test_run_cases \
  test_path_absolute_preserves_literal_and_caller_state \
  test_path_posix_does_not_require_native_conversion \
  test_path_windows_spellings_and_refusals \
  test_native_path_argument_reaches_real_consumer \
  test_path_context_preserves_empty_overrides_and_stages_failures

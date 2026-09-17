#!/usr/bin/env bash
# Regression coverage for local startup/report work that multiplied subprocess
# costs on Windows. Exercise the real readers, filesystem guards, and snapshot;
# keep safety/field assertions beside the operation-count and latency bounds.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-startup-performance)

test_watcher_health_reads_records_without_subprocesses() (
  local state="$TMP_ROOT/watcher-health" home="$TMP_ROOT/health-home" watch="$ROOT/bin/fm-watch.sh"
  mkdir -p "$state/.watch.lock" "$home"
  FM_STATE_OVERRIDE="$state"
  # shellcheck source=bin/fm-wake-lib.sh
  . "$ROOT/bin/fm-wake-lib.sh"
  printf '43210\n' > "$state/.watch.lock/pid"
  printf '%s\n' "$home" > "$state/.watch.lock/fm-home"
  printf '%s\n' "$watch" > "$state/.watch.lock/watcher-path"
  printf 'fixture-birth\n' > "$state/.watch.lock/pid-identity"
  touch "$state/.last-watcher-beat"
  fm_pid_alive() { [ "$1" = 43210 ]; }
  fm_pid_identity() { printf 'fixture-birth\n'; }
  # shellcheck disable=SC2329 # A forbidden tool launch is detected through the real reader.
  cat() { return 91; }
  fm_watcher_healthy "$state" "$watch" 300 "$home" \
    || fail "watcher health still launches a process to read its ownership records"
  printf 'replaced-birth\n' > "$state/.watch.lock/pid-identity"
  if fm_watcher_healthy "$state" "$watch" 300 "$home"; then fail "watcher health reused an earlier identity"; fi
  printf 'fixture-birth\n' > "$state/.watch.lock/pid-identity"
  printf 'another-home\n' > "$state/.watch.lock/fm-home"
  if fm_watcher_healthy "$state" "$watch" 300 "$home"; then fail "watcher health accepted another home"; fi
  pass "watcher health reads whole records in-process and rechecks identity and home"
)

# Parent-shell destinations avoid a command-substitution process for every field.
test_metadata_reads_support_in_process_results() (
  # shellcheck source=bin/fm-backend.sh
  . "$ROOT/bin/fm-backend.sh"
  local meta="$TMP_ROOT/fields.meta" value=stale last=stale absent=stale output="$TMP_ROOT/fields.out"
  # shellcheck disable=SC2016 # Expansion syntax is deliberately literal metadata.
  local expected='last=$literal "quoted" \ backslash'
  printf '%s\n' 'key=first' "key=$expected" 'empty=' > "$meta"
  printf 'last=without-final-newline' >> "$meta"
  fm_meta_get "$meta" key value > "$output" || fail "in-process metadata read failed"
  [ ! -s "$output" ] || fail "metadata destination read still writes a captured result"
  [ "$value" = "$expected" ] \
    || fail "metadata destination lost last-value or literal-data semantics"
  fm_meta_get "$meta" missing value
  [ -z "$value" ] || fail "missing metadata key retained a previous value"
  fm_meta_get "$meta" last value
  [ "$value" = without-final-newline ] || fail "unterminated final field was lost"
  [ "$(fm_meta_get "$meta" key)" = "$expected" ] \
    || fail "legacy metadata stdout changed"
  fm_meta_read "$meta" key value last last missing absent > "$output" \
    || fail "bulk metadata read failed"
  [ ! -s "$output" ] && [ "$value" = "$expected" ] \
    && [ "$last" = without-final-newline ] && [ -z "$absent" ] \
    || fail "bulk metadata read changed a literal, absent, or unterminated field"
  if fm_meta_read "$meta" key value last >/dev/null 2>&1; then
    fail "bulk reader accepted an incomplete key/destination pair"
  fi
  fm_meta_get "$TMP_ROOT/absent.meta" key value
  [ -z "$value" ] || fail "missing metadata file retained a previous value"
  if fm_meta_get "$meta" key 'invalid[0]' >/dev/null 2>&1; then
    fail "metadata reader accepted a non-scalar destination"
  fi
  pass "metadata can be read in-process without changing literal or legacy results"
)

test_backend_metadata_selection_stays_in_process() (
  # shellcheck source=bin/fm-backend.sh
  . "$ROOT/bin/fm-backend.sh"
  local meta="$TMP_ROOT/backend-cost.meta" output="$TMP_ROOT/backend-cost.out"
  local expected="$TMP_ROOT/backend-cost.expected" reads="$TMP_ROOT/backend-cost.reads"
  local caller_depth=$BASH_SUBSHELL depth
  : > "$reads"
  # Observe real filesystem reads, including on stock Bash 3.2, without
  # replacing the metadata parser or inspecting implementation source text.
  # shellcheck disable=SC2162,SC2329 # The real parser calls this option-preserving read probe.
  read() { printf '%s\n' "$BASH_SUBSHELL" >> "$reads"; builtin read "$@"; }
  printf 'backend=orca\nterminal=terminal-id\nwindow=window-id\n' > "$meta"
  fm_backend_of_meta "$meta" > "$output" || fail "backend selection failed"
  printf orca > "$expected"
  cmp -s "$expected" "$output" || fail "backend selection changed its output bytes"
  fm_backend_target_of_meta "$meta" > "$output" || fail "terminal selection failed"
  printf terminal-id > "$expected"
  cmp -s "$expected" "$output" || fail "target selection lost the Orca terminal"
  printf 'backend=orca\nterminal=\nwindow=window-id\n' > "$meta"
  fm_backend_target_of_meta "$meta" > "$output" || fail "window fallback failed"
  printf window-id > "$expected"
  cmp -s "$expected" "$output" || fail "target selection lost the Orca fallback"
  [ -s "$reads" ] || fail "backend cost fixture did not observe any real reads"
  while IFS= builtin read -r depth; do
    [ "$depth" -eq "$caller_depth" ] \
      || fail "backend metadata selection read in subshell depth $depth (caller $caller_depth)"
  done < "$reads"
  pass "backend metadata selection retains results without nested read subprocesses"
)

test_backend_metadata_values_preserve_caller_state() (
  # shellcheck source=bin/fm-backend.sh
  . "$ROOT/bin/fm-backend.sh"
  local output="$TMP_ROOT/backend-values.out" errors="$TMP_ROOT/backend-values.err"
  local expected="$TMP_ROOT/backend-values.expected" input="$TMP_ROOT/backend-values.in"
  local v=caller-v backend=caller-backend terminal=caller-terminal window=caller-window
  local selected_backend rc flags cwd remaining
  # shellcheck disable=SC2016 # Path, arguments, and field values are literal data.
  local meta='-backend café [data] $literal.meta' arg_two='$literal two'
  # shellcheck disable=SC2016
  local literal=' terminal=$literal "quoted" \ backslash ; $(never-run)  '
  cd "$TMP_ROOT" || fail "could not enter the literal-path fixture"
  set -f
  IFS=:
  set -- 'argument one' "$arg_two"
  flags=$- cwd=$PWD
  printf 'caller-input\n' > "$input"
  exec < "$input"
  expect_backend_values() {
    local expected_backend=$1 expected_target=$2 expected_rc=$3
    rc=0
    fm_backend_of_meta "$meta" > "$output" 2> "$errors" || rc=$?
    [ "$rc" -eq 0 ] && [ ! -s "$errors" ] || fail "backend reader changed its result status or diagnostics"
    printf '%s' "$expected_backend" > "$expected"
    cmp -s "$expected" "$output" || fail "backend reader changed literal/default/last-value bytes"
    rc=0
    fm_backend_target_of_meta "$meta" > "$output" 2> "$errors" || rc=$?
    [ "$rc" -eq "$expected_rc" ] && [ ! -s "$errors" ] || fail "target reader changed its result status or diagnostics"
    printf '%s' "$expected_target" > "$expected"
    cmp -s "$expected" "$output" || fail "target reader changed literal/fallback/last-value bytes"
  }
  expect_backend_values tmux '' 1
  : > "$meta"
  expect_backend_values tmux '' 1
  printf 'window=default-window\n' > "$meta"
  expect_backend_values tmux default-window 0
  for selected_backend in tmux herdr zellij cmux; do
    printf 'backend=%s\nterminal=ignored\nwindow=selected-window\n' "$selected_backend" > "$meta"
    expect_backend_values "$selected_backend" selected-window 0
  done
  printf '%s\n' 'backend=tmux' 'backend=orca' 'window=ignored' 'terminal=first' "terminal=$literal" > "$meta"
  expect_backend_values orca "$literal" 0
  printf 'backend=orca\nterminal=old\nterminal=\nwindow=fallback\n' > "$meta"
  expect_backend_values orca fallback 0
  printf 'backend=orca\nbackend=\nterminal=ignored\nwindow=old\nwindow=\n' > "$meta"
  expect_backend_values tmux '' 1
  printf 'backend=orca\n' > "$meta"
  expect_backend_values orca '' 1
  printf 'backend=%s\nterminal=ignored\nwindow=%s' "$literal" "$literal" > "$meta"
  expect_backend_values "$literal" "$literal" 0
  printf 'backend=orca\nterminal=%s' "$literal" > "$meta"
  expect_backend_values orca "$literal" 0
  printf 'backend=orca\r\nwindow=carriage-return-is-data\n' > "$meta"
  expect_backend_values $'orca\r' carriage-return-is-data 0
  rm -- "$meta"
  expect_backend_values tmux '' 1
  [ "$v:$backend:$terminal:$window" = caller-v:caller-backend:caller-terminal:caller-window ] \
    || fail "backend selectors changed caller variables"
  [ "$IFS" = : ] && [ "$-" = "$flags" ] && [ "$PWD" = "$cwd" ] \
    || fail "backend selectors changed caller IFS, options, or directory"
  [ "$#" -eq 2 ] && [ "$1" = 'argument one' ] && [ "$2" = "$arg_two" ] \
    || fail "backend selectors changed caller arguments"
  IFS= read -r remaining || fail "backend selectors consumed caller stdin"
  [ "$remaining" = caller-input ] || fail "backend selectors changed caller stdin"
  pass "backend selectors preserve literal results, defaults, failures, and caller state"
)

test_backend_metadata_selection_rechecks_between_reads() (
  # shellcheck source=bin/fm-backend.sh
  . "$ROOT/bin/fm-backend.sh"
  local dir="$TMP_ROOT/backend-fresh" meta first second remove_after_read reads output errors expected
  mkdir -p "$dir"
  meta="$dir/task.meta" first="$dir/first.meta" second="$dir/second.meta"
  remove_after_read="$dir/remove" reads="$dir/reads" output="$dir/out" errors="$dir/err" expected="$dir/expected"
  # Publish a replacement only after a real reader reaches EOF. Its open file
  # remains the old snapshot, while the next independent read sees the new one.
  # shellcheck disable=SC2329 # Invoked by the real metadata reader.
  read() {
    local read_rc=0
    # shellcheck disable=SC2162 # Forward the real reader's options unchanged.
    builtin read "$@" || read_rc=$?
    if [ "$read_rc" -ne 0 ]; then
      printf 'read\n' >> "$reads"
      if [ -f "$remove_after_read" ]; then
        rm -- "$meta" "$remove_after_read" || exit 98
      elif [ -f "$first" ]; then
        mv -f -- "$first" "$meta" || exit 98
      elif [ -f "$second" ]; then
        mv -f -- "$second" "$meta" || exit 98
      fi
    fi
    return "$read_rc"
  }
  expect_fresh_target() {
    local rc=0 count
    : > "$reads"
    fm_backend_target_of_meta "$meta" > "$output" 2> "$errors" || rc=$?
    [ "$rc" -eq "$2" ] && [ ! -s "$errors" ] || fail "fresh target read changed its status or diagnostics"
    printf '%s' "$1" > "$expected"
    cmp -s "$expected" "$output" || fail "target selection reused or reordered a metadata observation"
    count=$(wc -l < "$reads")
    [ "$count" -eq "$3" ] || fail "target selection changed its independent read phases ($count, expected $3)"
  }
  printf 'backend=orca\nterminal=stale\nwindow=stale\n' > "$meta"
  printf 'backend=tmux\nterminal=\nwindow=too-early\n' > "$first"
  printf 'backend=cmux\nterminal=too-late\nwindow=fresh-window\n' > "$second"
  expect_fresh_target fresh-window 0 3
  printf 'backend=herdr\nterminal=ignored\nwindow=stale\n' > "$meta"
  printf 'backend=orca\nterminal=wrong-branch\nwindow=fresh-window\n' > "$first"
  expect_fresh_target fresh-window 0 2
  printf 'backend=orca\nterminal=stale\nwindow=stale\n' > "$meta"
  printf 'backend=tmux\nterminal=fresh-terminal\nwindow=ignored\n' > "$first"
  printf 'backend=cmux\nterminal=too-late\nwindow=too-late\n' > "$second"
  expect_fresh_target fresh-terminal 0 2
  printf 'backend=orca\nterminal=stale\nwindow=stale\n' > "$meta"
  : > "$remove_after_read"
  expect_fresh_target '' 1 1
  pass "backend target selection keeps backend/terminal/window order and fresh independent reads"
)

test_backend_metadata_read_errors_do_not_abort_callers() (
  local selector meta rc output="$TMP_ROOT/backend-read-error.out"
  local errors="$TMP_ROOT/backend-read-error.err" expected="$TMP_ROOT/backend-read-error.expected"
  for selector in fm_backend_of_meta fm_backend_target_of_meta; do
    meta="$TMP_ROOT/read-error-$selector.meta"
    printf 'backend=orca\nterminal=terminal-id\nwindow=window-id\n' > "$meta"
    rc=0
    # The real read encounters a directory replacing the successfully checked
    # file. A continuation marker distinguishes normal failure from an abort.
    # shellcheck disable=SC2016
    "$BASH" -uc '
      . "$1"
      fault_meta=$2
      selector=$3
      function [ {
        local predicate_rc=0
        builtin [ "$@" || predicate_rc=$?
        if test "$#" -eq 3 && test "$1" = -f && test "$2" = "$fault_meta" && test "$predicate_rc" -eq 0; then
          rm -- "$fault_meta" && mkdir -- "$fault_meta" || exit 98
        fi
        return "$predicate_rc"
      }
      "$selector" "$fault_meta"
      printf "\nreturned=%s\n" "$?"
    ' _ "$ROOT/bin/fm-backend.sh" "$meta" "$selector" > "$output" 2> "$errors" || rc=$?
    [ -d "$meta" ] || fail "selector read-error fixture did not replace the file"
    [ "$rc" -eq 0 ] || fail "$selector aborted its caller on a read error (exit $rc)"
    [ ! -s "$errors" ] || fail "$selector changed its read-error diagnostics"
    case "$selector" in
      fm_backend_of_meta) printf 'tmux\nreturned=0\n' > "$expected" ;;
      fm_backend_target_of_meta) printf '\nreturned=1\n' > "$expected" ;;
    esac
    cmp -s "$expected" "$output" || fail "$selector changed its read-error output or status"
  done
  pass "backend selector read errors retain defaults and return without aborting callers"
)

test_metadata_first_read_error_returns_without_aborting() (
  local mode meta rc output="$TMP_ROOT/first-read-error.out" errors="$TMP_ROOT/first-read-error.err"
  local expected="$TMP_ROOT/first-read-error.expected"
  printf 'continued\n' > "$expected"
  for mode in bulk destination stdout; do
    meta="$TMP_ROOT/first-read-error-$mode.meta"
    printf 'key=unread\nlast=unread\n' > "$meta"
    rc=0
    # Preserve the real file-type verdict, then replace that file before open.
    # The real parser and Bash read must handle the resulting filesystem error.
    # shellcheck disable=SC2016 # Expansion belongs to the strict-mode child.
    "$BASH" -euc '
      . "$1"
      fault_meta=$2
      mode=$3
      function [ {
        local predicate_rc=0
        builtin [ "$@" || predicate_rc=$?
        if test "$#" -eq 3 && test "$1" = -f && test "$2" = "$fault_meta" && test "$predicate_rc" -eq 0; then
          rm -- "$fault_meta" && mkdir -- "$fault_meta" || exit 98
        fi
        return "$predicate_rc"
      }
      value=stale last=stale absent=stale
      case "$mode" in
        bulk)
          fm_meta_read "$fault_meta" key value last last missing absent
          [ -z "$value" ] && [ -z "$last" ] && [ -z "$absent" ] || exit 96
          ;;
        destination)
          fm_meta_get "$fault_meta" key value
          [ -z "$value" ]
          ;;
        stdout) fm_meta_get "$fault_meta" key ;;
      esac
      printf "continued\n"
    ' _ "$ROOT/bin/fm-backend.sh" "$meta" "$mode" > "$output" 2> "$errors" || rc=$?
    [ -d "$meta" ] || fail "first-read-error fixture did not replace the file"
    [ "$rc" -eq 0 ] || fail "$mode metadata read aborted its caller (exit $rc)"
    [ ! -s "$errors" ] || fail "$mode metadata read emitted unexpected read-error diagnostics"
    cmp -s "$expected" "$output" || fail "$mode metadata read changed its empty result or continuation"
  done
  pass "metadata readers return empty results after a first-read error without aborting callers"
)

test_metadata_later_read_error_stops_without_replaying_a_line() (
  local mode rc meta="$TMP_ROOT/later-read-error.meta" fault_dir="$TMP_ROOT/later-read-error-dir"
  local output="$TMP_ROOT/later-read-error.out" errors="$TMP_ROOT/later-read-error.err"
  local expected="$TMP_ROOT/later-read-error.expected"
  mkdir -p "$fault_dir"
  printf 'key=first\nkey=must-not-be-read\nlast=must-not-be-read\n' > "$meta"
  printf 'first|continued\n' > "$expected"
  for mode in bulk destination stdout; do
    rc=0
    # Let the first real read succeed, then inject a real I/O error through a
    # directory descriptor. Refuse another read so a stale-buffer loop fails
    # immediately instead of waiting for the runner's timeout.
    # shellcheck disable=SC2016 # Expansion belongs to the strict-mode child.
    "$BASH" -euc '
      . "$1"
      fault_dir=$3
      mode=$4
      read_calls=0
      read() {
        read_calls=$((read_calls + 1))
        case "$read_calls" in
          1) builtin read "$@" ;;
          2) builtin read "$@" < "$fault_dir" ;;
          *) exit 97 ;;
        esac
      }
      value=stale last=stale absent=stale
      case "$mode" in
        bulk)
          fm_meta_read "$2" key value last last missing absent
          [ -z "$last" ] && [ -z "$absent" ] || exit 96
          printf "%s" "$value"
          ;;
        destination)
          fm_meta_get "$2" key value
          printf "%s" "$value"
          ;;
        stdout) fm_meta_get "$2" key ;;
      esac
      [ "$read_calls" -eq 2 ]
      printf "|continued\n"
    ' _ "$ROOT/bin/fm-backend.sh" "$meta" "$fault_dir" "$mode" > "$output" 2> "$errors" || rc=$?
    [ "$rc" -eq 0 ] || fail "$mode metadata read did not stop after the I/O error (exit $rc)"
    [ ! -s "$errors" ] || fail "$mode metadata read emitted unexpected read-error diagnostics"
    cmp -s "$expected" "$output" || fail "$mode metadata read lost a completed field or consumed a later field"
  done
  pass "metadata readers stop after a later read error without replaying a prior line"
)

test_record_guards_use_fast_resolution_and_keep_fallback() (
  # shellcheck source=bin/fm-backlog-transition-lib.sh
  . "$ROOT/bin/fm-backlog-transition-lib.sh"
  local home="$TMP_ROOT/record-home" foreign="$TMP_ROOT/foreign" calls="$TMP_ROOT/perl-calls"
  local FM_HOME=$home resolved native=0
  mkdir -p "$home/state" "$foreign"
  printf 'kind=ship\n' > "$home/state/task.meta"
  printf 'foreign\n' > "$foreign/task.meta"
  : > "$calls"
  # Observe interpreter launches, not implementation text or fabricated paths.
  perl() { printf 'call\n' >> "$calls"; command perl "$@"; }
  if realpath -e -- "$home" >/dev/null 2>&1; then native=1; fi
  fm_backlog_record_present "$home/state/task.meta" record "$home/state" \
    || fail "ordinary record was refused"
  if [ "$native" = 1 ]; then
    [ ! -s "$calls" ] || fail "record guard still uses repeated Perl path walks with native realpath available"
  fi
  resolved=$(fm_backlog_canonical_existing "$home/state/task.meta") \
    || fail "existing record was not resolved"

  # Fresh observations must notice changed ancestry, not reuse an earlier grant.
  fm_test_make_symlink "$foreign" "$home/outside" || fail "directory symlink fixture failed"
  if fm_backlog_record_present "$home/outside/task.meta" record "$home/state"; then
    fail "record guard accepted an ancestor escaping its authorized root"
  fi
  fm_test_make_symlink task.meta "$home/state/alias.meta" || fail "file symlink fixture failed"
  if fm_backlog_record_present "$home/state/alias.meta" record "$home/state"; then
    fail "record guard accepted an internal final-component symlink"
  fi
  rm "$home/state/task.meta"
  fm_test_make_symlink "$foreign/task.meta" "$home/state/task.meta" || fail "replacement fixture failed"
  if fm_backlog_record_present "$home/state/task.meta" record "$home/state"; then
    fail "record guard reused an earlier successful identity after replacement"
  fi
  rm "$home/state/task.meta"
  printf 'kind=ship\n' > "$home/state/task.meta"

  # A BSD/curated PATH without the GNU flags must retain the portable reader.
  realpath() { return 64; }
  : > "$calls"
  [ "$(fm_backlog_canonical_existing "$home/state/task.meta")" = "$resolved" ] \
    || fail "portable path fallback changed the resolved record"
  [ -s "$calls" ] || fail "unsupported native realpath did not use the portable fallback"
  fm_backlog_record_present "$home/state/task.meta" record "$home/state" \
    || fail "portable fallback refused an ordinary record"
  if fm_backlog_record_present "$home/state/alias.meta" record "$home/state"; then
    fail "portable fallback accepted a final-component symlink"
  fi
  pass "fresh record guards retain confinement and symlink checks on native and portable paths"
)

test_recorded_herdr_presentations_skip_orphan_discovery() (
  local home="$TMP_ROOT/current-presentations" fakebin calls i=1 out
  mkdir -p "$home/state" "$home/data" "$home/config"
  fakebin=$(fm_fakebin "$home")
  calls="$home/herdr-calls"
  : > "$calls"
  command cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
printf 'call\n' >> "$FM_TEST_HERDR_CALLS"
printf '%s\n' '{"result":{"workspaces":[]}}'
SH
  chmod +x "$fakebin/herdr"
  while [ "$i" -le 9 ]; do
    printf 'kind=ship\nbackend=herdr\n' > "$home/state/task-$i.meta"
    printf 'version=1\ntask_id=task-%s\nprojection_id=abcdefghijklmnopqrstuv\n' "$i" \
      > "$home/state/task-$i.herdr-presentation"
    i=$((i + 1))
  done
  out=$(PATH="$fakebin:$PATH" FM_TEST_HERDR_CALLS="$calls" \
    FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_STATE_OVERRIDE="$home/state" \
    "$ROOT/bin/fm-herdr-session-cleanup.sh" 2>&1) || fail "current-presentation cleanup failed"
  [ ! -s "$calls" ] || fail "orphan cleanup queried Herdr even though every journal still has a task record"
  [ -z "$out" ] || fail "current task presentations produced cleanup diagnostics: $out"
  rm -f "$home/state/task-2.meta"
  fm_test_make_symlink ../missing.meta "$home/state/task-2.meta" || fail "metadata symlink fixture failed"
  PATH="$fakebin:$PATH" FM_TEST_HERDR_CALLS="$calls" \
    FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_STATE_OVERRIDE="$home/state" \
    "$ROOT/bin/fm-herdr-session-cleanup.sh" >/dev/null 2>&1 || fail "symlinked-record cleanup failed"
  [ ! -s "$calls" ] || fail "cleanup treated dangling metadata as absence"
  rm -f "$home/state/task-1.meta"
  PATH="$fakebin:$PATH" FM_TEST_HERDR_CALLS="$calls" \
    FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_STATE_OVERRIDE="$home/state" \
    "$ROOT/bin/fm-herdr-session-cleanup.sh" >/dev/null 2>&1 || fail "orphan discovery failed"
  [ -s "$calls" ] || fail "cleanup cached the earlier all-recorded result after a task disappeared"
  [ -f "$home/state/task-1.herdr-presentation" ] \
    || fail "discovery alone authorized retiring an unverified journal"
  pass "current Herdr presentations skip discovery while a newly orphaned journal is rechecked"
)

test_lock_pid_reads_stay_in_process_and_preserve_ownership() (
  local home="$TMP_ROOT/lock-home" lock calls current recorded
  # shellcheck disable=SC2030 # Each subshell owns an independent synthetic home.
  local FM_HOME=$home FM_ROOT_OVERRIDE=$home FM_STATE_OVERRIDE="$home/state"
  mkdir -p "$home/state"
  # shellcheck source=bin/fm-wake-lib.sh
  . "$ROOT/bin/fm-wake-lib.sh"
  lock="$home/state/fixture.lock"
  calls="$home/cat-calls"
  : > "$calls"
  cat() { printf 'call\n' >> "$calls"; command cat "$@"; }
  fm_lock_try_acquire "$lock" || fail "fresh lock was refused"
  fm_current_pid current || fail "current process could not be identified"
  IFS= read -r recorded < "$lock/pid" || fail "lock did not publish an owner"
  [ "$recorded" = "$current" ] || fail "lock belongs to a different process"
  fm_lock_set_role "$lock" terminal-check || fail "owner could not set its lock role"
  printf '%s\n\n' "$current" > "$lock/pid"
  fm_lock_set_role "$lock" autoarm || fail "trailing newlines changed the recorded owner"
  (fm_lock_release "$lock") || fail "non-owner release failed unexpectedly"
  [ -e "$lock" ] || fail "a subshell released its parent's lock"
  printf '%s\nforeign-trailer\n' "$current" > "$lock/pid"
  fm_lock_release "$lock"
  [ -e "$lock" ] || fail "release accepted only the first line of a malformed owner"
  printf '%s\000foreign-trailer\n' "$current" > "$lock/pid"
  fm_lock_release "$lock"
  [ -e "$lock" ] || fail "release accepted a NUL-terminated prefix as its owner"
  printf '%s' "$current" > "$lock/pid"
  fm_lock_release "$lock"
  [ ! -e "$lock" ] && [ ! -L "$lock" ] || fail "owner could not release its lock"
  [ ! -s "$calls" ] || fail "lock ownership checks still launch cat for tiny local records"
  pass "in-process lock reads retain whole-record and parent/subshell ownership checks"
)

test_lock_release_survives_removed_records_under_errexit() (
  local home="$TMP_ROOT/removed-owner" out
  mkdir -p "$home/state"
  # The child must enable errexit: Bash 5.2 aborts on a missing $(<file) even
  # when that assignment has an || fallback, unlike newer Bash versions.
  # shellcheck disable=SC2016
  out=$(FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_STATE_OVERRIDE="$home/state" \
    bash -euc '
      . "$1"
      fm_lock_release "$STATE/absent.lock"
      fm_lock_try_acquire "$STATE/retiring.lock"
      rm -rf "$STATE"
      fm_lock_release "$STATE/retiring.lock"
      printf "removed-owner-ok\n"
    ' _ "$ROOT/bin/fm-wake-lib.sh" 2>&1) \
    || fail "missing lock-owner records aborted an errexit cleanup: $out"
  [ "$out" = removed-owner-ok ] \
    || fail "idempotent release emitted an error after its home was removed: $out"
  pass "errexit cleanup quietly releases already-removed owner records and homes"
)

test_status_snapshot_batches_fresh_file_facts() (
  # shellcheck source=bin/fm-classify-lib.sh
  . "$ROOT/bin/fm-classify-lib.sh"
  local state="$TMP_ROOT/status-facts" calls os_calls os out task size ident old_ident count
  mkdir -p "$state"
  printf 'note: context\n' > "$state/task.status"
  calls="$state/stat-calls"
  os_calls="$state/uname-calls"
  : > "$calls"
  : > "$os_calls"
  os=$(command uname -s)
  stat() { printf 'call\n' >> "$calls"; command stat "$@"; }
  # shellcheck disable=SC2329 # A regression sentinel: no hot-path call is expected.
  uname() { printf 'call\n' >> "$os_calls"; command uname "$@"; }
  out=$(status_presentation_snapshot "$state") || fail "status snapshot failed"
  IFS=$'\t' read -r task size ident <<< "$out"
  [ "$task" = task ] && [ "$size" = 14 ] && [ -n "$ident" ] \
    || fail "status snapshot lost its captured task, byte size, or identity"
  old_ident=$ident
  # BSD stat is intentionally addressed by absolute path; native Windows and
  # Linux exercise the command-count guard, and all platforms exercise facts.
  if [ "$os" != Darwin ]; then
    count=$(wc -l < "$calls")
    [ "$count" -eq 1 ] || fail "one status snapshot launched stat $count times (budget 1)"
  fi
  [ ! -s "$os_calls" ] || fail "status reads repeatedly rediscover the same operating system"
  printf 'note: replaced\n' > "$state/replacement"
  mv -f "$state/replacement" "$state/task.status"
  out=$(status_presentation_snapshot "$state") || fail "replacement snapshot failed"
  IFS=$'\t' read -r task size ident <<< "$out"
  [ "$size" = 15 ] && [ "$ident" != "$old_ident" ] \
    || fail "snapshot reused file facts after a status replacement"
  printf 'note: appended\n' >> "$state/task.status"
  out=$(status_presentation_snapshot "$state") || fail "append snapshot failed"
  IFS=$'\t' read -r task size ident <<< "$out"
  [ "$size" = 30 ] || fail "snapshot reused a size after an append"
  pass "status snapshots batch native file facts without caching file identity or size"
)

test_status_event_rechecks_identity_after_its_span_read() (
  # shellcheck source=bin/fm-classify-lib.sh
  . "$ROOT/bin/fm-classify-lib.sh"
  local state="$TMP_ROOT/status-replacement" reader out task endpoint ident
  mkdir -p "$state"
  printf 'done: original\n' > "$state/task.status"
  out=$(status_presentation_snapshot "$state") || fail "initial snapshot failed"
  IFS=$'\t' read -r task endpoint ident <<< "$out"
  reader="$state/replace-reader"
  command cat > "$reader" <<'SH'
#!/usr/bin/env bash
[ "$2" = 0 ] || exit 1
command cat "$1" || exit 1
printf 'done: replaced\n' > "$1.replacement" || exit 1
touch -r "$1" "$1.replacement" || exit 1
mv -f "$1.replacement" "$1"
SH
  chmod +x "$reader"
  if FM_STATUS_SPAN_READER="$reader" status_snapshot_latest_event "$state/task.status" "$endpoint" "$ident"; then
    fail "latest-event read accepted a replacement between its pre/post checks"
  fi
  [ -z "$FM_STATUS_SNAPSHOT_EVENT_LINE" ] || fail "failed event read retained a prior result"
  out=$(status_presentation_snapshot "$state") || fail "replacement snapshot failed"
  IFS=$'\t' read -r task endpoint ident <<< "$out"
  status_snapshot_latest_event "$state/task.status" "$endpoint" "$ident" \
    || fail "fresh replacement event was refused"
  [ "$FM_STATUS_SNAPSHOT_EVENT_LINE" = 'done: replaced' ] \
    || fail "fresh event did not belong to the replacement file"
  pass "batched file facts retain fresh pre/post-read replacement refusal"
)

test_backlog_path_validation_avoids_interpreter_launches() (
  # shellcheck source=bin/fm-backlog-transition-lib.sh
  . "$ROOT/bin/fm-backlog-transition-lib.sh"
  local data="$TMP_ROOT/literal path café" calls resolved code char out rc
  mkdir -p "$data"
  calls="$TMP_ROOT/path-validation-calls"
  : > "$calls"
  # shellcheck disable=SC2329 # Regression sentinels for removed interpreter launches.
  perl() { printf 'perl\n' >> "$calls"; command perl "$@"; }
  # shellcheck disable=SC2329 # The path predicate must stay in-process.
  awk() { printf 'awk\n' >> "$calls"; command awk "$@"; }
  resolved=$(fm_backlog_data_absolute "$data") || fail "literal data directory was refused"
  [ "$resolved" -ef "$data" ] || fail "data resolution changed the filesystem object"
  [ ! -s "$calls" ] || fail "literal path validation still launches Perl or awk"
  for code in 1 9 10 13 31 127; do
    printf -v char '%03o' "$code"
    printf -v char '%b' "\\$char"
    rc=0
    out=$(fm_backlog_data_absolute "$data$char" 2>&1) || rc=$?
    [ "$rc" -eq 2 ] && [[ "$out" == *'invalid control byte'* ]] \
      || fail "path validation accepted or misclassified control byte $code"
  done
  pass "literal path validation keeps byte-level refusals without per-read interpreters"
)

test_routine_status_history_stays_bounded_and_keeps_decisions() (
  # shellcheck source=bin/fm-timeout-lib.sh
  . "$ROOT/bin/fm-timeout-lib.sh"
  local log="$TMP_ROOT/routine.status" i=0 out
  printf 'needs-decision [key=choice]: choose the release\n' > "$log"
  while [ "$i" -lt 200 ]; do
    printf 'working: progress %s; prose mentions blocked: and resolved: but is not a decision\n' "$i" >> "$log"
    i=$((i + 1))
  done
  # This bound is deliberately generous for the real filesystem work, but a
  # per-line subprocess storm exceeds it on native Windows. No worker is run.
  # shellcheck disable=SC2016
  out=$(fm_run_timed 20 bash -c '. "$1"; status_open_decisions "$2"' \
    _ "$ROOT/bin/fm-classify-lib.sh" "$log") \
    || fail "routine status history exceeded its 20-second read bound"
  [ "$out" = $'choice\tneeds-decision\tchoose the release' ] \
    || fail "routine events masked the still-open decision"
  printf '  resolved [key=choice]: selected\n' >> "$log"
  # shellcheck disable=SC2016
  out=$(fm_run_timed 20 bash -c '. "$1"; status_open_decisions "$2"' \
    _ "$ROOT/bin/fm-classify-lib.sh" "$log") \
    || fail "updated status history exceeded its read bound"
  [ -z "$out" ] || fail "status read cached a decision after its resolution"
  pass "routine history stays bounded without losing or caching decision transitions"
)

test_status_text_destinations_preserve_legacy_capture_semantics() (
  # shellcheck source=bin/fm-classify-lib.sh
  . "$ROOT/bin/fm-classify-lib.sh"
  local line reader expected actual expected_rc actual_rc output="$TMP_ROOT/text-reader.out"
  for line in \
    'needs-decision corr=0123456789abcdef [key=choice]: keep "quoted" text' \
    'resolved: [key=choice] answer' \
    'blocked [key=before]: [key=after] literal note' \
    'corr=0123456789abcdef resolved [key=choice]: not a transition' \
    'needs-decision [key=bad/key]: malformed key' \
    $'note: trailing spaces  \n\n' \
    'legacy without colon'; do
    for reader in status_line_verb status_line_note _fm_decision_key; do
      expected_rc=0
      expected=$("$reader" "$line") || expected_rc=$?
      actual=stale
      actual_rc=0
      "$reader" "$line" actual > "$output" || actual_rc=$?
      [ "$actual_rc" -eq "$expected_rc" ] && [ ! -s "$output" ] \
        || fail "$reader changed its failure or output-channel contract"
      if [ "$actual_rc" -eq 0 ]; then
        [ "$actual" = "$expected" ] || fail "$reader changed its captured literal bytes"
      fi
    done
  done
  if status_line_verb 'done: finished' 'invalid[0]' >/dev/null 2>&1; then
    fail "status reader accepted a non-scalar result destination"
  fi
  pass "status text destinations retain literal, malformed-key, and legacy capture behavior"
)

test_transition_history_stays_in_process_and_keeps_open_keys() (
  # shellcheck source=bin/fm-timeout-lib.sh
  . "$ROOT/bin/fm-timeout-lib.sh"
  local log="$TMP_ROOT/transitions.status" i=0 out
  printf 'needs-decision [key=retained]: preserve the unanswered choice\n' > "$log"
  while [ "$i" -lt 100 ]; do
    printf 'blocked corr=0123456789abcdef [key=step-%s]: waiting\n' "$i" >> "$log"
    printf 'resolved: [key=step-%s] completed\n' "$i" >> "$log"
    i=$((i + 1))
  done
  # Real transitions must be cheap too, not only the routine-line prefilter.
  # shellcheck disable=SC2016
  out=$(fm_run_timed 20 bash -c '. "$1"; status_open_decisions "$2"' \
    _ "$ROOT/bin/fm-classify-lib.sh" "$log") \
    || fail "transition history exceeded its 20-second read bound"
  [ "$out" = $'retained\tneeds-decision\tpreserve the unanswered choice' ] \
    || fail "transition folding lost an unanswered key or retained a resolved key"
  pass "real decision transitions stay bounded without changing correlation or keyed closure"
)

test_snapshot_projection_bounds_json_tool_launches() (
  local home="$TMP_ROOT/snapshot-home" fakebin real_jq calls json count i=1
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects"
  fakebin=$(fm_fakebin "$home")
  real_jq=$(command -v jq) || fail "jq is required for the snapshot regression"
  calls="$home/jq-calls"
  : > "$calls"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "call\\n" >> %q\n' "$calls"
    # shellcheck disable=SC2016 # Expansion belongs to the generated jq wrapper.
    printf 'if [ "${OS:-}" = Windows_NT ]; then set -- --binary "$@"; fi\n'
    printf 'exec %q "$@"\n' "$real_jq"
  } > "$fakebin/jq"
  chmod +x "$fakebin/jq"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  while [ "$i" -le 3 ]; do
    fm_write_meta "$home/state/task-$i.meta" \
      'kind=ship' 'harness=copilot' 'mode=direct-PR' "spawn_gen=gen-$i" \
      "worktree=$home/projects/absent-$i" 'project=literal="data"' \
      "pr=https://github.com/example/repo/pull/$i"
    printf 'needs-decision [key=choice]: preserve "quoted" notes\nworking: unrelated progress\n' \
      > "$home/state/task-$i.status"
    i=$((i + 1))
  done
  json=$(PATH="$fakebin:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" FM_PROJECTS_OVERRIDE="$home/projects" \
    "$ROOT/bin/fm-fleet-snapshot.sh" --json) || fail "real snapshot failed"
  printf '%s' "$json" | "$real_jq" -e '
    .schema == "fm-fleet-snapshot.v1" and (.tasks | length) == 3
    and all(.tasks[];
      .project == "literal=\"data\"" and .current_state.state == "unknown"
      and .paths.meta.present and (.paths.worktree.present | not)
      and .paths.home.path == null and .endpoint.exists == null
      and .pr.source == "meta" and (.pr.url | startswith("https://github.com/example/repo/pull/"))
      and (.hints.open_decisions | length) == 1
      and .hints.open_decisions[0].summary == "preserve \"quoted\" notes")
  ' >/dev/null || fail "bounded projection changed captured paths, tasks, PRs, or decisions: $json"
  count=$(wc -l < "$calls")
  [ "$count" -le 32 ] || fail "three-task snapshot launched jq $count times (budget 32)"
  pass "real snapshot preserves facts without per-field JSON subprocesses"
)

fm_test_run_cases \
  test_metadata_reads_support_in_process_results \
  test_backend_metadata_selection_stays_in_process \
  test_backend_metadata_values_preserve_caller_state \
  test_backend_metadata_selection_rechecks_between_reads \
  test_backend_metadata_read_errors_do_not_abort_callers \
  test_metadata_first_read_error_returns_without_aborting \
  test_metadata_later_read_error_stops_without_replaying_a_line \
  test_watcher_health_reads_records_without_subprocesses \
  test_record_guards_use_fast_resolution_and_keep_fallback \
  test_recorded_herdr_presentations_skip_orphan_discovery \
  test_lock_pid_reads_stay_in_process_and_preserve_ownership \
  test_lock_release_survives_removed_records_under_errexit \
  test_status_snapshot_batches_fresh_file_facts \
  test_status_event_rechecks_identity_after_its_span_read \
  test_backlog_path_validation_avoids_interpreter_launches \
  test_routine_status_history_stays_bounded_and_keeps_decisions \
  test_status_text_destinations_preserve_legacy_capture_semantics \
  test_transition_history_stays_in_process_and_keeps_open_keys \
  test_snapshot_projection_bounds_json_tool_launches

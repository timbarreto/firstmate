#!/usr/bin/env bash
# Behavior tests for the semantic busy-state contract (bin/fm-busy-lib.sh and
# its only writer bin/fm-busy-event.sh).
#
# Covers the captain-approved redesign invariants: busy/idle/unknown/dead with
# explicit source attribution; missing, malformed, stale (gen-mismatch), and
# untrusted (source-mismatch) semantic data classify unknown - never idle;
# adapter isolation (one adapter's writer or Grok's regex can never classify
# another adapter); endpoint death is the only process-level override and
# yields dead, never busy; converted adapters never classify from rendered
# footer text. All hermetic over temp dirs; no real agent session is invoked.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-busy-state)
EV="$ROOT/bin/fm-busy-event.sh"

new_state_dir() {  # <name>
  local d="$TMP_ROOT/$1/state"
  mkdir -p "$d"
  printf '%s' "$d"
}

# The public stdout reader needs no child shell merely to build its path.
# DEBUG inheritance observes real execution and works on stock Bash 3.2.
test_current_gen_path_stays_in_process() (
  local state depth log
  state=$(new_state_dir current-gen-cost)
  printf 'g.literal-1\n' > "$state/t1.busy-gen"
  log="$state/contexts"
  : > "$log"
  depth=$BASH_SUBSHELL
  set -T
  trap 'if [ "$BASH_SUBSHELL" -gt "$depth" ]; then printf "%s\n" "$BASH_SUBSHELL" >> "$log"; fi' DEBUG
  fm_busy_current_gen "$state" t1 > "$state/actual" || fail "current gen read failed"
  trap - DEBUG
  printf 'g.literal-1' > "$state/expected"
  cmp -s "$state/expected" "$state/actual" || fail "current gen stdout changed"
  [ ! -s "$log" ] || fail "current gen lookup created a nested shell for path construction"
  pass "current gen lookup preserves stdout without nested process work"
)

# Count observed child-shell contexts, not native process starts or source text.
# The budget retains setup, the stdout gen read, and the prior-record head read.
test_writer_process_budget() {
  local state hook log count=0 depth
  state=$(new_state_dir writer-cost)
  printf 'g.fixture\n' > "$state/t1.busy-gen"
  printf 'v1 gen=g.fixture seq=7 state=busy source=pi-ext event=agent-start ts=1\n' \
    > "$state/t1.busy-state"
  hook="$state/context-hook.sh"
  log="$state/contexts"
  : > "$log"
  cat > "$hook" <<'SH'
_fm_test_seen_depth=$BASH_SUBSHELL
set -T
trap 'if [ "$BASH_SUBSHELL" -ne "$_fm_test_seen_depth" ]; then _fm_test_seen_depth=$BASH_SUBSHELL; printf "%s\n" "$BASH_SUBSHELL" >> "$FM_TEST_CONTEXT_LOG"; fi' DEBUG
SH
  BASH_ENV="$hook" FM_TEST_CONTEXT_LOG="$log" "$EV" apply "$state" t1 idle \
    --gen g.fixture --source pi-ext --event agent-settled \
    > "$state/stdout" 2> "$state/stderr" || fail "instrumented apply failed"
  [ ! -s "$state/stdout" ] && [ ! -s "$state/stderr" ] || fail "successful apply was not silent"
  [ "$(fm_busy_record_read "$state" t1)" = 'idle pi-ext agent-settled 8' ] \
    || fail "instrumented apply did not advance the real record"
  while IFS= read -r depth; do count=$((count + 1)); done < "$log"
  [ "$count" -gt 0 ] || fail "child-shell observation was inactive"
  [ "$count" -le 10 ] || fail "busy apply created $count child-shell contexts (budget 10)"
  pass "busy apply preserves its record within the reduced child-shell budget"
}

test_generation_first_line_characterization() {
  local state shape want rc
  state=$(new_state_dir gen-lines)
  for shape in missing empty blank unterminated malformed carriage multiline blank-first valid; do
    rm -f "$state/t1.busy-gen"
    want=1
    case "$shape" in
      missing) ;;
      empty) : > "$state/t1.busy-gen" ;;
      blank) printf '\n' > "$state/t1.busy-gen" ;;
      unterminated) printf 'g.fixture' > "$state/t1.busy-gen" ;;
      malformed) printf 'bad token\n' > "$state/t1.busy-gen" ;;
      carriage) printf 'g.fixture\r\n' > "$state/t1.busy-gen" ;;
      multiline) printf 'g.fixture\nignored second line\n' > "$state/t1.busy-gen"; want=0 ;;
      blank-first) printf '\ng.fixture\n' > "$state/t1.busy-gen" ;;
      valid) printf 'g.fixture\n' > "$state/t1.busy-gen"; want=0 ;;
    esac
    rc=0
    fm_busy_current_gen "$state" t1 > "$state/stdout" 2> "$state/stderr" || rc=$?
    expect_code "$want" "$rc" "generation first-line outcome changed for $shape"
    [ ! -s "$state/stderr" ] || fail "generation read diagnosed $shape"
    : > "$state/expected"
    [ "$want" != 0 ] || printf 'g.fixture' > "$state/expected"
    cmp -s "$state/expected" "$state/stdout" || fail "generation bytes changed for $shape"
  done
  pass "generation reads preserve first-line, unterminated, empty, and malformed outcomes"
}

test_prior_record_first_line_characterization() {
  local state shape want
  state=$(new_state_dir record-lines)
  printf 'g.fixture\n' > "$state/t1.busy-gen"
  for shape in missing empty malformed stale bad-seq backslash unterminated multiline duplicate carriage; do
    rm -f "$state/t1.busy-state"
    want=1
    case "$shape" in
      missing) ;;
      empty) : > "$state/t1.busy-state" ;;
      malformed) printf 'not a record\n' > "$state/t1.busy-state" ;;
      stale) printf 'v1 gen=g.old seq=7 state=busy\n' > "$state/t1.busy-state" ;;
      bad-seq) printf 'v1 gen=g.fixture seq=NaN state=busy\n' > "$state/t1.busy-state" ;;
      backslash) printf 'v1 gen=g.fixture seq=1\\2 state=busy\n' > "$state/t1.busy-state" ;;
      unterminated) printf 'v1 gen=g.fixture seq=7 state=busy' > "$state/t1.busy-state"; want=8 ;;
      multiline) printf 'v1 gen=g.fixture seq=7 state=busy\nv1 gen=g.fixture seq=99 state=idle\n' > "$state/t1.busy-state"; want=8 ;;
      duplicate) printf 'unvalidated gen=g.fixture seq=2 seq=7 state=busy\n' > "$state/t1.busy-state"; want=8 ;;
      carriage) printf 'v1 gen=g.fixture seq=7 state=busy\r\n' > "$state/t1.busy-state"; want=8 ;;
    esac
    "$EV" apply "$state" t1 idle --gen g.fixture --source pi-ext --event agent-settled \
      > "$state/stdout" 2> "$state/stderr" || fail "prior-record apply failed for $shape"
    [ ! -s "$state/stdout" ] && [ ! -s "$state/stderr" ] || fail "prior-record apply diagnosed $shape"
    [ "$(fm_busy_record_read "$state" t1)" = "idle pi-ext agent-settled $want" ] \
      || fail "prior-record sequence changed for $shape"
    [ ! -e "$state/t1.busy-state.lock" ] || fail "apply retained the lock for $shape"
  done
  pass "writer preserves literal first-line and existing malformed-record sequence behavior"
}

test_prior_record_nul_diagnostic_is_preserved() {
  local state
  state=$(new_state_dir record-nul)
  printf 'g.fixture\n' > "$state/t1.busy-gen"
  printf 'v1 gen=g.fixture seq=7 state=busy\000\n' > "$state/t1.busy-state"
  # Stock Bash 3.2 predates the warning. Probe the shell capability, not the
  # writer's source or version spelling, while pinning the record result below.
  ( : "$(printf 'x\000y')" ) 2> "$state/shell-diagnostic"
  "$EV" apply "$state" t1 idle --gen g.fixture --source pi-ext --event agent-settled \
    > "$state/stdout" 2> "$state/stderr" || fail "NUL-containing prior record aborted apply"
  [ ! -s "$state/stdout" ] || fail "NUL-containing apply changed stdout"
  if [ -s "$state/shell-diagnostic" ]; then
    assert_contains "$(cat "$state/stderr")" 'ignored null byte in input' \
      "writer silently lost the shell's NUL-input diagnostic"
  else
    [ ! -s "$state/stderr" ] || fail "writer added a diagnostic absent from this Bash"
  fi
  [ "$(fm_busy_record_read "$state" t1)" = 'idle pi-ext agent-settled 8' ] \
    || fail "NUL-containing prior record changed sequence handling"
  pass "NUL-containing prior records retain the supported Bash diagnostic and sequence"
}

test_busy_paths_and_current_gen_preserve_caller_state() (
  local state="./state café & '\$literal [x] (1)" id=-t._1 gen before_umask before_options before_pwd out
  cd "$TMP_ROOT" || fail "literal-path fixture directory missing"
  mkdir -p "$state"
  umask 027
  before_umask=$(umask)
  gen=$("$EV" arm "$state" "$id") || fail "literal-path arm failed"
  set -efu
  set -- 'keep two words' 'literal *'
  IFS=':|'
  before_options=$-
  before_pwd=$PWD
  fm_busy_current_gen "$state" "$id" > "$state/gen-output" || fail "literal-path gen read failed"
  printf '%s' "$gen" > "$state/expected-gen"
  cmp -s "$state/expected-gen" "$state/gen-output" || fail "literal-path gen output changed"
  [ "$#" = 2 ] && [ "$1" = 'keep two words' ] && [ "$2" = 'literal *' ] || fail "reader changed arguments"
  [ "$IFS" = ':|' ] && [ "$-" = "$before_options" ] && [ "$PWD" = "$before_pwd" ] \
    || fail "reader changed caller IFS, options, or directory"
  "$EV" apply "$state" "$id" idle --current-gen --source fm-recovery --event relaunch \
    > "$state/stdout" 2> "$state/stderr" || fail "literal-path current-gen apply failed"
  [ ! -s "$state/stdout" ] && [ ! -s "$state/stderr" ] || fail "literal-path apply was not silent"
  # The changed stdout gen helper is the custom-IFS seam above. Inspect the
  # written record with the unmodified full parser's ordinary caller setup.
  out=$(IFS=$' \t\n' fm_busy_record_read "$state" "$id") || fail "literal record unreadable: $out"
  [ "$out" = 'idle fm-recovery relaunch 2' ] || fail "literal record changed: $out"
  "$EV" progress "$state" "$id" --gen "$gen" || fail "literal-path progress failed"
  [ -f "$state/$id.progress" ] && [ ! -e "$state/$id.turn-ended" ] || fail "progress was not separate"
  "$EV" retire "$state" "$id" --gen "$gen" || fail "literal-path retirement failed"
  [ ! -e "$state/$id.busy-gen" ] && [ ! -e "$state/$id.busy-state" ] && [ ! -e "$state/$id.progress" ] \
    || fail "literal-path retirement left its artifacts"
  [ "$(umask)" = "$before_umask" ] || fail "busy operations changed caller umask"
  pass "literal relative paths preserve caller state across gen, arm, apply, progress, and retire"
)

test_generation_read_error_returns_without_aborting() (
  local state rc=0
  state=$(new_state_dir gen-read-error)
  printf 'g.fixture\n' > "$state/t1.busy-gen"
  # Replace a real file only after the real file-type check has succeeded.
  # shellcheck disable=SC2329 # Invoked by the sourced reader's executable predicate.
  function [() {
    builtin [ "$@" || return $?
    if [[ "$#" = 3 && "$1" = -f && "$2" = "$state/t1.busy-gen" ]]; then
      mv "$2" "$2.saved" && mkdir "$2" || return 1
    fi
    return 0
  }
  set -eu
  fm_busy_current_gen "$state" t1 > "$state/stdout" 2> "$state/stderr" || rc=$?
  unset -f '['
  [ "$rc" = 1 ] || fail "generation I/O error changed refusal status"
  [ -d "$state/t1.busy-gen" ] || fail "generation I/O race did not execute"
  [ ! -s "$state/stdout" ] && [ ! -s "$state/stderr" ] || fail "generation I/O error was not quiet"
  pass "a real generation read error returns quietly without aborting a strict caller"
)

test_prior_record_read_failure_resets_sequence() {
  local state hook
  state=$(new_state_dir record-read-error)
  printf 'g.fixture\n' > "$state/t1.busy-gen"
  printf 'v1 gen=g.fixture seq=7 state=busy\n' > "$state/t1.busy-state"
  hook="$state/remove-after-check.sh"
  cat > "$hook" <<'SH'
function [() {
  builtin [ "$@" || return $?
  if [[ "$#" = 3 && "$1" = -f && "$2" = "$FM_TEST_RECORD" ]]; then
    mv "$2" "$2.saved" || return 1
  fi
  return 0
}
SH
  BASH_ENV="$hook" FM_TEST_RECORD="$state/t1.busy-state" "$EV" apply "$state" t1 idle \
    --gen g.fixture --source pi-ext --event agent-settled \
    > "$state/stdout" 2> "$state/stderr" || fail "prior-record read error aborted apply"
  [ -f "$state/t1.busy-state.saved" ] || fail "prior-record I/O race did not execute"
  [ ! -s "$state/stdout" ] && [ ! -s "$state/stderr" ] || fail "prior-record I/O error changed diagnostics"
  [ "$(fm_busy_record_read "$state" t1)" = 'idle pi-ext agent-settled 1' ] \
    || fail "unreadable prior record did not retain its sequence-reset outcome"
  pass "a real prior-record open failure retains quiet publication from sequence one"
}

test_record_publication_keeps_lock_and_private_umask() {
  local state hook
  state=$(new_state_dir record-publication)
  printf 'g.fixture\n' > "$state/t1.busy-gen"
  printf 'v1 gen=g.fixture seq=7 state=busy source=pi-ext event=agent-start ts=1\n' > "$state/t1.busy-state"
  cp "$state/t1.busy-state" "$state/before"
  hook="$state/observe-publication.sh"
  cat > "$hook" <<'SH'
mv() {
  if [[ "$#" = 3 && "$1" = -f && "$3" = "$FM_TEST_RECORD" ]]; then
    [ -d "$FM_TEST_RECORD.lock" ] || return 91
    cmp -s "$FM_TEST_BEFORE" "$FM_TEST_RECORD" || return 92
    case "$(umask)" in 0077|077) ;; *) return 93 ;; esac
    local line='' extra=''
    { IFS= read -r line && ! IFS= read -r extra; } < "$2" || return 94
    case "$line" in 'v1 gen=g.fixture seq=8 state=idle source=pi-ext event=agent-settled ts='[0-9]*) ;; *) return 95 ;; esac
    : > "$FM_TEST_PUBLICATION_SEEN"
  fi
  command mv "$@"
}
SH
  BASH_ENV="$hook" FM_TEST_RECORD="$state/t1.busy-state" FM_TEST_BEFORE="$state/before" \
    FM_TEST_PUBLICATION_SEEN="$state/published" "$EV" apply "$state" t1 idle \
    --gen g.fixture --source pi-ext --event agent-settled \
    > "$state/stdout" 2> "$state/stderr" || fail "record publication lost its lock, old contents, or private umask"
  [ -f "$state/published" ] || fail "publication observation did not execute"
  [ ! -s "$state/stdout" ] && [ ! -s "$state/stderr" ] || fail "publication changed output"
  [ "$(fm_busy_record_read "$state" t1)" = 'idle pi-ext agent-settled 8' ] || fail "published record incomplete"
  [ ! -e "$state/t1.busy-state.lock" ] || fail "publication retained its lock"
  pass "record replacement publishes a complete line under its lock and private writer umask"
}

test_current_gen_binding_stays_before_lock_for_apply() {
  local state fakebin real_mkdir mode rc
  state=$(new_state_dir generation-lock)
  fakebin=$(fm_fakebin "$TMP_ROOT/generation-lock")
  real_mkdir=$(command -v mkdir)
  cat > "$fakebin/mkdir" <<'SH'
#!/usr/bin/env bash
if [ "$#" = 1 ] && [ "$1" = "$FM_TEST_LOCK" ] && [ -d "$1" ]; then
  "$FM_TEST_REAL_MKDIR" "$@" 2>/dev/null && exit 97
  printf 'g.replacement\n' > "$FM_TEST_STATE/t1.busy-gen.new"
  mv "$FM_TEST_STATE/t1.busy-gen.new" "$FM_TEST_STATE/t1.busy-gen" || exit 98
  printf 'v1 gen=g.replacement seq=1 state=busy source=fm-spawn event=launch-brief ts=1\n' \
    > "$FM_TEST_STATE/t1.busy-state.new"
  mv "$FM_TEST_STATE/t1.busy-state.new" "$FM_TEST_STATE/t1.busy-state" || exit 98
  rmdir "$FM_TEST_LOCK" || exit 98
  : > "$FM_TEST_STATE/replaced"
  exit 1
fi
exec "$FM_TEST_REAL_MKDIR" "$@"
SH
  chmod +x "$fakebin/mkdir"
  for mode in apply retire; do
    printf 'g.original\n' > "$state/t1.busy-gen"
    printf 'v1 gen=g.original seq=7 state=busy source=pi-ext event=agent-start ts=1\n' > "$state/t1.busy-state"
    rm -f "$state/replaced"
    mkdir "$state/t1.busy-state.lock"
    rc=0
    if [ "$mode" = apply ]; then
      PATH="$fakebin:$PATH" FM_TEST_REAL_MKDIR="$real_mkdir" FM_TEST_LOCK="$state/t1.busy-state.lock" \
        FM_TEST_STATE="$state" "$EV" apply "$state" t1 idle --current-gen --source fm-recovery --event relaunch \
        > "$state/stdout" 2> "$state/stderr" || rc=$?
      expect_code 1 "$rc" "pre-lock current-gen apply must reject replacement while waiting"
      printf 'error: stale busy-state gen for t1 (event rejected)\n' > "$state/expected-error"
      cmp -s "$state/expected-error" "$state/stderr" || fail "stale generation refusal changed"
      [ "$(fm_busy_record_read "$state" t1)" = 'busy fm-spawn launch-brief 1' ] || fail "stale apply changed replacement"
    else
      PATH="$fakebin:$PATH" FM_TEST_REAL_MKDIR="$real_mkdir" FM_TEST_LOCK="$state/t1.busy-state.lock" \
        FM_TEST_STATE="$state" "$EV" retire "$state" t1 --current-gen \
        > "$state/stdout" 2> "$state/stderr" || rc=$?
      expect_code 0 "$rc" "current-gen retire must still bind the generation under the lock"
      [ ! -e "$state/t1.busy-gen" ] && [ ! -e "$state/t1.busy-state" ] || fail "retire did not remove replacement"
      [ ! -s "$state/stderr" ] || fail "current-gen retire changed diagnostics"
    fi
    [ -f "$state/replaced" ] || fail "$mode did not reach the contended-lock replacement"
    [ ! -s "$state/stdout" ] && [ ! -e "$state/t1.busy-state.lock" ] || fail "$mode changed output or lock release"
  done
  pass "apply keeps pre-lock binding while retire retains its distinct under-lock current generation"
}

# --- writer: arm and apply ---------------------------------------------------

test_arm_seeds_busy_spawn() {
  local state gen out
  state=$(new_state_dir arm-seed)
  gen=$("$EV" arm "$state" t1) || fail "arm failed"
  [ -f "$state/t1.busy-gen" ] || fail "arm did not write the gen sidecar"
  [ "$(cat "$state/t1.busy-gen")" = "$gen" ] || fail "sidecar gen does not match printed gen"
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "busy fm-spawn" ] || fail "seed should classify 'busy fm-spawn', got '$out'"
  pass "arm mints a gen sidecar and seeds busy fm-spawn at seq=1"
}

test_apply_advances_seq_and_source() {
  local state gen out seq
  state=$(new_state_dir apply-seq)
  gen=$("$EV" arm "$state" t1)
  "$EV" apply "$state" t1 idle --gen "$gen" --source claude-hook --event stop \
    || fail "apply idle failed"
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "idle claude-hook" ] || fail "expected 'idle claude-hook', got '$out'"
  "$EV" apply "$state" t1 busy --gen "$gen" --source claude-hook --event user-prompt-submit \
    || fail "apply busy failed"
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "busy claude-hook" ] || fail "expected 'busy claude-hook', got '$out'"
  seq=$(fm_busy_record_read "$state" t1 | awk '{print $4}')
  [ "$seq" = 3 ] || fail "expected seq 3 after seed + two applies, got '$seq'"
  pass "apply advances seq under the armed gen and attributes the writing source"
}

test_apply_current_gen_reset() {
  local state out
  state=$(new_state_dir apply-current)
  "$EV" arm "$state" t1 >/dev/null
  "$EV" apply "$state" t1 idle --current-gen --source fm-interrupt --event interrupt \
    || fail "apply --current-gen failed"
  out=$(fm_busy_classify tmux w1 pi t1 "$state")
  [ "$out" = "idle fm-interrupt" ] || fail "expected 'idle fm-interrupt', got '$out'"
  "$EV" apply "$state" t1 unknown --current-gen --source fm-recovery --event relaunch \
    || fail "apply unknown failed"
  out=$(fm_busy_classify tmux w1 pi t1 "$state")
  [ "$out" = "unknown fm-recovery" ] || fail "expected 'unknown fm-recovery', got '$out'"
  pass "firstmate-owned interrupt and recovery events bind to the current gen"
}

test_apply_unarmed_refused() {
  local state
  state=$(new_state_dir apply-unarmed)
  if "$EV" apply "$state" t1 busy --gen g1.2.3 --source claude-hook --event x 2>/dev/null; then
    fail "apply against an unarmed task must be refused"
  fi
  [ ! -f "$state/t1.busy-state" ] || fail "refused apply must not write a record"
  pass "apply is refused for a task whose busy contract was never armed"
}

test_retire_serializes_and_rejects_stale_gen() {
  local state old_gen new_gen out retire_pid i=0
  state=$(new_state_dir retire)
  old_gen=$("$EV" arm "$state" t1)
  mkdir "$state/t1.busy-state.lock"
  "$EV" retire "$state" t1 --gen "$old_gen" >/dev/null 2>&1 &
  retire_pid=$!
  while [ "$i" -lt 20 ] && ! kill -0 "$retire_pid" 2>/dev/null; do
    i=$((i + 1))
  done
  [ -e "$state/t1.busy-state" ] || fail "retire bypassed the writer lock"
  rmdir "$state/t1.busy-state.lock"
  wait "$retire_pid" || fail "retire failed after acquiring the writer lock"
  [ ! -e "$state/t1.busy-state" ] || fail "retire left the record behind"
  [ ! -e "$state/t1.busy-gen" ] || fail "retire left the gen sidecar behind"

  new_gen=$("$EV" arm "$state" t1)
  if "$EV" retire "$state" t1 --gen "$old_gen" 2>/dev/null; then
    fail "retire accepted a superseded incarnation"
  fi
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "busy fm-spawn" ] || fail "stale retirement changed the new incarnation, got '$out'"
  [ "$(cat "$state/t1.busy-gen")" = "$new_gen" ] || fail "stale retirement changed the new gen"
  pass "retire waits for the writer lock and cannot remove a new incarnation"
}

# Regression for issue #2625: the writer lock's stale-lock branch resolved the
# lock's mtime with `stat -f %m ... || stat -c %Y ...`. On GNU coreutils `-f` is
# *filesystem* stat, so it consumes the format string as a path, complains on
# stderr, prints "  File: ..." on stdout, and still exits 0 - the GNU form in the
# fallback never ran. The following `$((now - mtime))` then evaluated the word
# `File`, which under `set -u` aborted the writer with "File: unbound variable".
# fm-teardown.sh died there after returning the worktree, leaving state/<id>.meta
# and friends behind to generate stale wakes forever, and every re-run died
# identically because the abandoned lock directory was never broken.
#
# The stat and uname stubs make this deterministic on any host: the writer must
# take the Linux path and still break a provably stale lock.
test_stale_lock_broken_under_gnu_stat() {
  local state gen fakebin real_uname out status
  state=$(new_state_dir gnu-stat-lock)
  gen=$("$EV" arm "$state" t1)
  fakebin=$(fm_fakebin "$TMP_ROOT/gnu-stat-lock")
  real_uname=$(command -v uname)

  # GNU coreutils semantics, self-contained so no real stat is consulted.
  cat > "$fakebin/stat" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = -c ] && [ "${2:-}" = %Y ]; then
  printf '%s\n' 1000000000   # long-abandoned lock
  exit 0
fi
if [ "${1:-}" = -f ]; then
  echo "stat: cannot read file system information for '$2': No such file or directory" >&2
  shift 2
  printf '  File: "%s"\n' "${1:-}"
  exit 0
fi
exit 1
SH
  chmod +x "$fakebin/stat"
  cat > "$fakebin/uname" <<SH
#!/usr/bin/env bash
if [ \$# -eq 0 ]; then printf 'Linux\n'; exit 0; fi
exec "$real_uname" "\$@"
SH
  chmod +x "$fakebin/uname"

  mkdir "$state/t1.busy-state.lock"
  out=$(PATH="$fakebin:$PATH" "$EV" retire "$state" t1 --gen "$gen" 2>&1) && status=0 || status=$?
  case "$out" in
    *'unbound variable'*) fail "the writer still dies on GNU stat output: $out" ;;
  esac
  [ "$status" = 0 ] || fail "retire did not break a provably stale writer lock: $out"
  [ ! -e "$state/t1.busy-state" ] || fail "retire left the record behind"
  [ ! -e "$state/t1.busy-gen" ] || fail "retire left the gen sidecar behind"
  [ ! -e "$state/t1.busy-state.lock" ] || fail "retire left the stale lock behind"

  # Teardown must be able to run again over the same task without failing.
  PATH="$fakebin:$PATH" "$EV" retire "$state" t1 --current-gen \
    || fail "a repeated retire over already-cleaned state was not idempotent"
  pass "the writer breaks a stale lock instead of dying on GNU stat output"
}

test_retire_missing_sidecar_is_idempotent() {
  local state gen
  state=$(new_state_dir retire-missing)
  gen=$("$EV" arm "$state" t1)
  rm -f "$state/t1.busy-gen"

  "$EV" retire "$state" t1 --gen "$gen" || fail "exact-gen retire rejected a missing sidecar"
  [ ! -e "$state/t1.busy-state" ] || fail "retire left an orphan record behind"
  "$EV" retire "$state" t1 --gen "$gen" || fail "repeated exact-gen retire was not idempotent"
  "$EV" retire "$state" t1 --current-gen || fail "current-gen retire was not idempotent"

  printf 'malformed gen\n' > "$state/t1.busy-gen"
  printf 'orphan\n' > "$state/t1.busy-state"
  if "$EV" retire "$state" t1 --gen "$gen" 2>/dev/null; then
    fail "retire accepted a malformed existing sidecar"
  fi
  [ -e "$state/t1.busy-state" ] || fail "retire removed the record for a malformed existing sidecar"
  pass "retire treats only an absent sidecar as already retired"
}

# --- stale event rejection ----------------------------------------------------

test_stale_gen_event_rejected() {
  local state old_gen new_gen out
  state=$(new_state_dir stale-event)
  old_gen=$("$EV" arm "$state" t1)
  new_gen=$("$EV" arm "$state" t1)
  [ "$old_gen" != "$new_gen" ] || fail "re-arm must mint a fresh gen"
  if "$EV" apply "$state" t1 idle --gen "$old_gen" --source claude-hook --event stop 2>/dev/null; then
    fail "an event carrying a stale gen must be rejected"
  fi
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "busy fm-spawn" ] || fail "stale event must not change the record, got '$out'"
  pass "a late event from a previous incarnation is rejected, record unchanged"
}

test_stale_gen_record_unknown() {
  local state gen out
  state=$(new_state_dir stale-record)
  gen=$("$EV" arm "$state" t1)
  # Simulate a record left behind by a superseded incarnation.
  printf 'g-superseded.1.1\n' > "$state/t1.busy-gen.new"
  mv "$state/t1.busy-gen.new" "$state/t1.busy-gen"
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "unknown gen-mismatch" ] || fail "stale record must classify 'unknown gen-mismatch', got '$out'"
  pass "a record from a stale incarnation classifies unknown, never idle"
}

# --- missing and malformed semantic data --------------------------------------

test_missing_record_unknown_not_idle() {
  local state out h
  state=$(new_state_dir missing)
  for h in claude opencode pi pi-signed; do
    out=$(fm_busy_classify tmux w1 "$h" t1 "$state")
    [ "$out" = "unknown missing" ] || fail "$h with no record must be 'unknown missing', got '$out'"
  done
  out=$(fm_busy_classify tmux w1 codex t1 "$state")
  [ "$out" = "unknown codex-unverified" ] || fail "codex with no verified source must be 'unknown codex-unverified', got '$out'"
  pass "a converted adapter with no record classifies unknown, never idle"
}

test_malformed_record_unknown() {
  local state gen out
  state=$(new_state_dir malformed)
  gen=$("$EV" arm "$state" t1)
  for bad in \
    'garbage' \
    "v0 gen=$gen seq=1 state=busy source=claude-hook event=x ts=1" \
    "v1 gen=$gen seq=NaN state=busy source=claude-hook event=x ts=1" \
    "v1 gen=$gen seq=1 state=frobbing source=claude-hook event=x ts=1" \
    "v1 gen=$gen seq=1 state=busy source=bad source event=x ts=1" \
    "v1 gen=$gen seq=1 state=busy source=claude-hook event=x ts=1 rogue=1"; do
    printf '%s\n' "$bad" > "$state/t1.busy-state"
    out=$(fm_busy_classify tmux w1 claude t1 "$state")
    [ "$out" = "unknown malformed" ] || fail "malformed record '$bad' must be 'unknown malformed', got '$out'"
  done
  printf 'v1 gen=%s seq=1 state=busy source=claude-hook event=x ts=1\nsecond line\n' "$gen" > "$state/t1.busy-state"
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "unknown malformed" ] || fail "multi-line record must be 'unknown malformed', got '$out'"
  pass "malformed records classify unknown malformed, never busy or idle"
}

test_record_without_sidecar_unknown() {
  local state out
  state=$(new_state_dir orphan-record)
  printf 'v1 gen=g1.1.1 seq=1 state=busy source=claude-hook event=x ts=1\n' > "$state/t1.busy-state"
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "unknown malformed" ] || fail "record without an armed gen must be unknown, got '$out'"
  pass "a record with no armed gen sidecar classifies unknown"
}

# --- adapter isolation ---------------------------------------------------------

test_source_mismatch_cross_adapter() {
  local state gen out
  state=$(new_state_dir cross-adapter)
  gen=$("$EV" arm "$state" t1)
  "$EV" apply "$state" t1 busy --gen "$gen" --source pi-ext --event agent-start
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "unknown source-mismatch" ] || fail "pi-ext record on a claude task must be untrusted, got '$out'"
  out=$(fm_busy_classify tmux w1 pi t1 "$state")
  [ "$out" = "busy pi-ext" ] || fail "pi-ext record on a pi task must classify, got '$out'"
  out=$(fm_busy_classify tmux w1 grok t1 "$state")
  [ "$out" = "unknown source-mismatch" ] || fail "grok trusts no semantic source, got '$out'"
  pass "a record is trusted only by the adapter whose source wrote it"
}

test_converted_adapters_ignore_footer_text() {
  local state out h
  state=$(new_state_dir no-footer)
  local tail='• Working (6s • esc to interrupt)
   ■■■■⬝⬝⬝⬝  esc interrupt
Working...
Ctrl+c:cancel'
  for h in claude opencode pi pi-signed; do
    out=$(fm_busy_classify tmux w1 "$h" t1 "$state" "$tail")
    [ "$out" = "unknown missing" ] || fail "$h must never classify from footer text, got '$out'"
  done
  out=$(fm_busy_classify tmux w1 codex t1 "$state" "$tail")
  [ "$out" = "unknown codex-unverified" ] || fail "codex must never classify from footer text, got '$out'"
  pass "converted adapters never classify busy from rendered footer text"
}

test_grok_regex_isolated() {
  local state out
  state=$(new_state_dir grok-arm)
  out=$(fm_busy_classify tmux w1 grok t1 "$state" 'thinking hard
Ctrl+c:cancel')
  [ "$out" = "busy grok-regex" ] || fail "grok busy tail must classify 'busy grok-regex', got '$out'"
  out=$(fm_busy_classify tmux w1 grok t1 "$state" 'done.
> ')
  [ "$out" = "idle grok-regex" ] || fail "grok idle tail must classify 'idle grok-regex', got '$out'"
  # Another adapter's footer never makes grok busy either.
  out=$(fm_busy_classify tmux w1 grok t1 "$state" '• Working (6s • esc to interrupt)')
  [ "$out" = "idle grok-regex" ] || fail "a claude footer must not classify grok busy, got '$out'"
  pass "the grok fallback is regex-scoped to grok and classifies only grok tasks"
}

# --- kimi verification gate -----------------------------------------------------

test_codex_unverified_gate() {
  local state gen out
  state=$(new_state_dir codex-gate)
  gen=$("$EV" arm "$state" t1)
  "$EV" apply "$state" t1 busy --gen "$gen" --source codex-hook --event user-prompt-submit
  out=$(fm_busy_classify tmux w1 codex t1 "$state")
  [ "$out" = "unknown codex-unverified" ] || fail "unverified codex must classify unknown, got '$out'"
  [ -z "$(fm_busy_sources_for_harness codex)" ] \
    || fail "codex must trust no semantic source until one is verified"
  pass "codex classifies unknown until a semantic source passes its verification gate"
}

test_kimi_unverified_gate() {
  local state gen out
  state=$(new_state_dir kimi-gate)
  gen=$("$EV" arm "$state" t1)
  "$EV" apply "$state" t1 busy --gen "$gen" --source kimi-hook --event user-prompt-submit
  out=$(fm_busy_classify tmux w1 kimi t1 "$state")
  [ "$out" = "unknown kimi-unverified" ] || fail "unverified kimi must classify unknown, got '$out'"
  out=$(fm_busy_classify tmux w1 kimi t1 "$state" '🌒 · thinking')
  [ "$out" = "unknown kimi-unverified" ] || fail "kimi must not classify from footer text, got '$out'"
  pass "standalone kimi classifies unknown until the live verification gate opens"
}

test_cursor_ignores_rendered_and_native_signals() {
  local state out
  state=$(new_state_dir cursor-gate)
  # Cursor's verdict comes from its own transcript, never from rendered text.
  # With no binding to fold, the honest answer is unknown - and a rendered
  # busy-looking footer must not change that.
  out=$(fm_busy_classify tmux w1 cursor t1 "$state" 'Working')
  [ "$out" = "unknown cursor-transcript" ] \
    || fail "cursor must not classify from its rendered footer, got '$out'"
  out=$(fm_busy_classify tmux w1 cursor t1 "$state" 'ctrl+c to stop')
  [ "$out" = "unknown cursor-transcript" ] \
    || fail "cursor must not classify from the ctrl+c busy token either, got '$out'"
  # Herdr's narrower native streaming state is not cursor's turn lifecycle.
  # shellcheck disable=SC2329 # invoked indirectly through fm_busy_classify
  fm_backend_busy_state() { printf '%s' busy; }
  out=$(fm_busy_classify herdr s:p cursor t1 "$state")
  [ "$out" = "unknown cursor-transcript" ] \
    || fail "cursor must not borrow herdr's native busy verdict, got '$out'"
  unset -f fm_backend_busy_state
  # The fold is a PULL source: nothing is armed, so no stored record is trusted.
  [ -z "$(fm_busy_sources_for_harness cursor)" ] \
    || fail "cursor must trust no stored record source; its fold has no writer"
  pass "cursor classifies only from its transcript fold, never rendered text or native state"
}

# --- endpoint death and native fallbacks ----------------------------------------

test_dead_endpoint_overrides() {
  local state gen out
  state=$(new_state_dir dead)
  gen=$("$EV" arm "$state" t1)
  # shellcheck disable=SC2329 # invoked indirectly through fm_busy_classify_live
  fm_backend_target_exists() { return 1; }
  out=$(fm_busy_classify_live tmux w1 claude t1 "$state")
  [ "$out" = "dead endpoint-gone" ] || fail "gone endpoint must classify dead, got '$out'"
  # shellcheck disable=SC2329 # invoked indirectly through fm_busy_classify_live
  fm_backend_target_exists() { return 0; }
  out=$(fm_busy_classify_live tmux w1 claude t1 "$state")
  [ "$out" = "busy fm-spawn" ] || fail "live endpoint must fall through to the record, got '$out'"
  out=$(fm_busy_classify_live tmux '' claude t1 "$state")
  [ "$out" = "unknown no-target" ] || fail "empty target must classify unknown, got '$out'"
  unset -f fm_backend_target_exists
  pass "endpoint death is the only process-level override and yields dead, never busy"
}

test_herdr_native_busy_only() {
  local state out
  state=$(new_state_dir herdr-native)
  # shellcheck disable=SC2329 # invoked indirectly through fm_busy_classify
  fm_backend_busy_state() { printf '%s' "$FAKE_NATIVE"; }
  FAKE_NATIVE=busy
  out=$(fm_busy_classify herdr s:p claude t1 "$state")
  [ "$out" = "busy herdr-native" ] || fail "native busy with no record must classify busy, got '$out'"
  FAKE_NATIVE=idle
  out=$(fm_busy_classify herdr s:p claude t1 "$state")
  [ "$out" = "unknown missing" ] || fail "native idle must NOT classify idle, got '$out'"
  # A valid record outranks the native verdict.
  local gen
  gen=$("$EV" arm "$state" t1)
  "$EV" apply "$state" t1 idle --gen "$gen" --source claude-hook --event stop
  FAKE_NATIVE=busy
  out=$(fm_busy_classify herdr s:p claude t1 "$state")
  [ "$out" = "idle claude-hook" ] || fail "the adapter record must outrank herdr's native verdict, got '$out'"
  unset -f fm_backend_busy_state
  pass "herdr's native verdict is trusted for busy only, and records outrank it"
}

# The record parser runs inside sourcing callers (the watcher, the daemon, the
# crew-state reader), so it must not disturb their shell: no clobbered
# positional parameters and no changed glob setting.
test_record_read_leaves_caller_shell_intact() {
  local state out
  state=$(new_state_dir parser-isolation)
  "$EV" arm "$state" t1 >/dev/null
  out=$(bash -c '
    set -f
    . "$1/bin/fm-busy-lib.sh"
    set -- keepme second
    fm_busy_record_read "$2" t1 >/dev/null
    printf "%s|%s|%s" "$1" "$#" "$-"
  ' _ "$ROOT" "$state")
  case "$out" in
    keepme\|2\|*f*) : ;;
    *) fail "record parsing disturbed the caller's shell: $out" ;;
  esac
  # A glob-shaped field must survive parsing literally rather than expanding.
  printf 'v1 gen=%s seq=1 state=busy source=* event=x ts=1\n' "$(cat "$state/t1.busy-gen")" \
    > "$state/t1.busy-state"
  out=$(fm_busy_classify tmux w1 claude t1 "$state")
  [ "$out" = "unknown malformed" ] || fail "a glob-shaped source must be rejected, not expanded, got '$out'"
  pass "record parsing never clobbers the caller's positional parameters, glob setting, or fields"
}

test_boolean_view_never_promotes_unknown() {
  local state gen
  state=$(new_state_dir boolean)
  gen=$("$EV" arm "$state" t1)
  fm_busy_is_busy tmux w1 claude t1 "$state" || fail "busy record must read busy"
  "$EV" apply "$state" t1 idle --gen "$gen" --source claude-hook --event stop
  if fm_busy_is_busy tmux w1 claude t1 "$state"; then
    fail "idle record must not read busy"
  fi
  printf 'garbage\n' > "$state/t1.busy-state"
  if fm_busy_is_busy tmux w1 claude t1 "$state"; then
    fail "malformed record must not read busy"
  fi
  pass "the boolean view reports busy only on an exact busy verdict"
}

test_progress_is_generation_bound_and_not_semantic_state() {
  local state gen replacement before
  state=$(new_state_dir native-progress)
  gen=$("$EV" arm "$state" t1)
  before=$(cat "$state/t1.busy-state")
  "$EV" progress "$state" t1 --gen "$gen" || fail "current progress was refused"
  [ -f "$state/t1.progress" ] || fail "progress marker missing"
  [ ! -e "$state/t1.turn-ended" ] || fail "progress emitted a completed turn"
  [ "$(cat "$state/t1.busy-state")" = "$before" ] || fail "progress changed semantic state"
  replacement=$("$EV" arm "$state" t1)
  [ ! -e "$state/t1.progress" ] || fail "arm retained the previous incarnation's progress"
  if "$EV" progress "$state" t1 --gen "$gen" 2>/dev/null; then fail "stale progress was accepted"; fi
  [ ! -e "$state/t1.progress" ] || fail "stale progress wrote a marker"
  "$EV" progress "$state" t1 --gen "$replacement" || fail "replacement progress was refused"
  "$EV" retire "$state" t1 --gen "$replacement" || fail "retire failed"
  [ ! -e "$state/t1.progress" ] || fail "retire retained progress"
  pass "native progress is generation-bound, separately recorded, and cleared on arm and retire"
}

fm_test_run_cases \
  test_progress_is_generation_bound_and_not_semantic_state \
  test_arm_seeds_busy_spawn \
  test_apply_advances_seq_and_source \
  test_apply_current_gen_reset \
  test_apply_unarmed_refused \
  test_retire_serializes_and_rejects_stale_gen \
  test_retire_missing_sidecar_is_idempotent \
  test_stale_lock_broken_under_gnu_stat \
  test_stale_gen_event_rejected \
  test_stale_gen_record_unknown \
  test_missing_record_unknown_not_idle \
  test_malformed_record_unknown \
  test_record_without_sidecar_unknown \
  test_source_mismatch_cross_adapter \
  test_converted_adapters_ignore_footer_text \
  test_grok_regex_isolated \
  test_codex_unverified_gate \
  test_kimi_unverified_gate \
  test_cursor_ignores_rendered_and_native_signals \
  test_dead_endpoint_overrides \
  test_herdr_native_busy_only \
  test_record_read_leaves_caller_shell_intact \
  test_boolean_view_never_promotes_unknown \
  test_current_gen_path_stays_in_process \
  test_writer_process_budget \
  test_generation_first_line_characterization \
  test_prior_record_first_line_characterization \
  test_prior_record_nul_diagnostic_is_preserved \
  test_busy_paths_and_current_gen_preserve_caller_state \
  test_generation_read_error_returns_without_aborting \
  test_prior_record_read_failure_resets_sequence \
  test_current_gen_binding_stays_before_lock_for_apply \
  test_record_publication_keeps_lock_and_private_umask

echo "all fm-busy-state tests passed"

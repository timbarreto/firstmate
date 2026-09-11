#!/usr/bin/env bash
# First-signal ownership refusal and same-stop escalation with real process groups.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-procevent-stop-proof)
export FM_PROCEVENT_CLAIM_ROOT="$TMP_ROOT/claims"

pe() { FM_HOME="$1" "$ROOT/bin/fm-procevent.sh" "${@:2}"; }

wait_for() {
  local file=$1
  for _ in $(seq 1 100); do [ -s "$file" ] && return 0; sleep 0.1; done
  return 1
}

post_term_evidence() {
  local case=$1 runner=$2 claim=$3 signals=$4 started=$5 out=$6
  {
    printf 'post-TERM evidence (%s case)\n' "$case"
    printf '  elapsed since retire started: %ss\n' "$(( $(date +%s) - started ))"
    printf '  identity recorded at claim time: %s\n' "$(sed -n '4p' "$claim" 2>/dev/null || echo '<claim unreadable>')"
    printf '  identity readable now (real ps): %s\n' "$(LC_ALL=C ps -p "$runner" -o lstart= 2>/dev/null || echo '<ps failed>')"
    printf '  signals file: %s (%s bytes)\n' "$signals" "$(wc -c < "$signals" 2>/dev/null | tr -d ' ' || echo 0)"
    printf '  leader state: %s\n' "$(ps -o pid=,ppid=,pgid=,stat= -p "$runner" 2>/dev/null || echo '<leader gone>')"
    printf '  leader wchan: %s\n' "$(ps -o wchan= -p "$runner" 2>/dev/null || echo '<none>')"
    printf '  live members of the runner group:\n'
    ps -Ao pid,ppid,pgid,stat,wchan,command 2>/dev/null | awk -v g="$runner" 'NR==1 || $3==g' | sed 's/^/    /'
    printf '  retire said: %s\n' "${out:-<no output>}"
  } >&2
}

check_stop_proof() {
  local post_term_case=$1 HPOST_TERM POST_TERM_SOURCE POST_TERM_PID POST_TERM_SIGNALS
  local POST_TERM_BIN REAL_PS REAL_PERL POST_TERM_RUNNER post_term_status post_term_started post_term_out
  HPOST_TERM="$TMP_ROOT/post-term-$post_term_case"
  mkdir -p "$HPOST_TERM/state"
  POST_TERM_SOURCE="$HPOST_TERM/source.sh"
  POST_TERM_PID="$HPOST_TERM/child.pid"
  POST_TERM_SIGNALS="$HPOST_TERM/child.signals"
  cat > "$POST_TERM_SOURCE" <<'SH'
#!/usr/bin/env bash
trap 'printf "signalled\n" >> "$2"' TERM
printf '%s\n' "$$" > "$1"
while [ "$SECONDS" -lt "${FM_TEST_STUB_MAX_BLOCK_SECONDS:-120}" ]; do sleep 1; done
SH
  chmod +x "$POST_TERM_SOURCE"
  POST_TERM_BIN=$(fm_fakebin "$HPOST_TERM/tools")
  REAL_PS=$(command -v ps) || fail "the post-TERM reuse fixture requires ps"
  REAL_PERL=$(command -v perl) || fail "the post-TERM reuse fixture requires perl"
  fm_test_track_procevent_home "$HPOST_TERM"
  pe "$HPOST_TERM" register lavish post-term-src -- \
    "$POST_TERM_SOURCE" "$POST_TERM_PID" "$POST_TERM_SIGNALS" >/dev/null
  FM_PROC_ROOT_OVERRIDE="$TMP_ROOT/no-post-term-proc" \
    FM_PROCEVENT_OWNER_CHECK_SECONDS=5 pe "$HPOST_TERM" reconcile >/dev/null
  wait_for "$POST_TERM_PID" || fail "the post-TERM reuse fixture did not start"
  wait_for "$FM_PROCEVENT_CLAIM_ROOT/post-term-src.claim" \
    || fail "the post-TERM reuse fixture did not claim its source"
  POST_TERM_RUNNER=$(sed -n '2p' "$FM_PROCEVENT_CLAIM_ROOT/post-term-src.claim")
  # Cross startup's source-lock boundary before suspending its owner.
  FM_PROC_ROOT_OVERRIDE="$TMP_ROOT/no-post-term-proc" pe "$HPOST_TERM" list >/dev/null \
    || fail "the post-TERM fixture never finished its source launch"
  kill -STOP "$POST_TERM_RUNNER" || fail "the post-TERM fixture could not keep its leader alive"
  cat > "$POST_TERM_BIN/ps" <<SH
#!/usr/bin/env bash
if [ "\${1-}" = -p ] && [ "\${2-}" = "$POST_TERM_RUNNER" ] \
  && [ "\${3-}" = -o ] && [ "\${4-}" = lstart= ]; then
  if [ "$post_term_case" = mismatch ]; then
    printf 'reused identity\n'
    exit 0
  fi
  [ ! -s "$POST_TERM_SIGNALS" ] || exit 1
fi
exec "$REAL_PS" "\$@"
SH
  # The portable process-group owner uses getpgrp through Perl, not ps.
  cat > "$POST_TERM_BIN/perl" <<SH
#!/usr/bin/env bash
if [ "\$#" -eq 3 ] && [ "\${1-}" = -we ] && [ "\${3-}" = "$POST_TERM_RUNNER" ]; then
  printf 'queried\n' >> "$HPOST_TERM/pgid-queries"
  case "$post_term_case" in
    unreadable-pgid) [ ! -s "$POST_TERM_SIGNALS" ] || exit 1 ;;
    nonleader) printf '%s\n' "$((POST_TERM_RUNNER + 1))"; exit 0 ;;
  esac
fi
exec "$REAL_PERL" "\$@"
SH
  chmod +x "$POST_TERM_BIN/ps" "$POST_TERM_BIN/perl"
  post_term_status=0
  post_term_started=$(date +%s)
  post_term_out=$(PATH="$POST_TERM_BIN:$PATH" FM_PROC_ROOT_OVERRIDE="$TMP_ROOT/no-post-term-proc" \
    pe "$HPOST_TERM" retire post-term-src 2>&1) || post_term_status=$?
  case "$post_term_case" in
    mismatch|nonleader)
      assert_absent "$POST_TERM_SIGNALS" "the first signal refuses $post_term_case evidence"
      [ "$post_term_status" -ne 0 ] || fail "retirement escalated despite $post_term_case evidence"
      assert_contains "$post_term_out" "cannot confirm runner identity" \
        "first-signal $post_term_case evidence refuses retirement"
      kill -0 "$POST_TERM_RUNNER" 2>/dev/null \
        || fail "the post-TERM fixture lost its leader instead of exercising $post_term_case evidence"
      kill -0 -"$POST_TERM_RUNNER" 2>/dev/null \
        || fail "a $post_term_case group was killed during escalation"
      assert_present "$HPOST_TERM/state/procevent/post-term-src.source" \
        "first-signal $post_term_case evidence preserves registration"
      assert_present "$FM_PROCEVENT_CLAIM_ROOT/post-term-src.claim" \
        "first-signal $post_term_case evidence preserves its claim"
      kill -KILL -"$POST_TERM_RUNNER" 2>/dev/null || true
      ;;
    *)
      if [ ! -s "$POST_TERM_SIGNALS" ]; then
        post_term_evidence "$post_term_case" "$POST_TERM_RUNNER" \
          "$FM_PROCEVENT_CLAIM_ROOT/post-term-src.claim" "$POST_TERM_SIGNALS" \
          "$post_term_started" "$post_term_out"
        fail "the post-TERM fixture never received TERM"
      fi
      [ "$post_term_status" -eq 0 ] \
        || fail "retirement abandoned a proved stop after $post_term_case identity: $post_term_out"
      assert_absent "$HPOST_TERM/state/procevent/post-term-src.source" \
        "proved escalation retires the source after $post_term_case identity"
      assert_absent "$FM_PROCEVENT_CLAIM_ROOT/post-term-src.claim" \
        "proved escalation releases its claim after $post_term_case identity"
      ;;
  esac
  if [ "$post_term_case" != mismatch ]; then
    assert_present "$HPOST_TERM/pgid-queries" "the ownership fixture intercepts the real PGID query"
  fi
  for _ in $(seq 1 50); do kill -0 -"$POST_TERM_RUNNER" 2>/dev/null || break; sleep 0.1; done
  kill -0 -"$POST_TERM_RUNNER" 2>/dev/null && fail "the post-TERM fixture group survived: $post_term_case"
  pe "$HPOST_TERM" retire post-term-src >/dev/null
  pass "stop $post_term_case evidence preserves the proved-stop boundary"
}

test_stop_refuses_mismatched_identity() { check_stop_proof mismatch; }
test_stop_preserves_proof_after_unreadable_identity() { check_stop_proof unreadable; }
test_stop_preserves_proof_after_unreadable_pgid() { check_stop_proof unreadable-pgid; }
test_stop_refuses_nonleader_evidence() { check_stop_proof nonleader; }

fm_test_run_cases \
  test_stop_refuses_mismatched_identity \
  test_stop_preserves_proof_after_unreadable_identity \
  test_stop_preserves_proof_after_unreadable_pgid \
  test_stop_refuses_nonleader_evidence

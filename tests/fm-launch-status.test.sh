#!/usr/bin/env bash
# Execute the generation-bound status boundary/read interfaces consumed by
# spawn, control and crew-state. Fixtures are serialized status logs, not
# implementation-source assertions.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-classify-lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-launch-status)

test_launch_status_only_reads_this_generation() {
  local file="$TMP_ROOT/generation.status" boundary current
  printf 'done: previous worker\n' > "$file"
  boundary=$(status_launch_boundary "$file" replacement)
  if status_launch_current "$file" "$boundary" replacement; then fail "old completion confirmed a replacement"; fi
  printf 'working: replacement started\ndone [key=finish]: requested change completed\n' >> "$file"
  current=$(status_launch_current "$file" "$boundary" replacement)
  [ "$current" = 'done [key=finish]: requested change completed' ] || fail "fresh terminal report was lost: $current"
  if status_launch_current "$file" "$boundary" other; then fail "another generation adopted this report"; fi
  printf 'note: extra evidence\nresolved [key=finish]: acknowledged\n' >> "$file"
  [ "$(status_launch_current "$file" "$boundary" replacement)" = "$current" ] || fail "non-state annotations hid a report"
  printf 'working: a new requirement\n' >> "$file"
  [ "$(status_launch_current "$file" "$boundary" replacement)" = 'working: a new requirement' ] || fail "later work retained stale terminal evidence"
  printf 'failed: replacement could not finish\n' >> "$file"
  [ "$(status_launch_current "$file" "$boundary" replacement)" = 'failed: replacement could not finish' ] || fail "failure report was lost"
  pass "launch reports exclude prior generations and follow later state declarations"
}

test_launch_status_absent_and_incomplete_logs() {
  local file="$TMP_ROOT/new.status" boundary
  boundary=$(status_launch_boundary "$file" new)
  if status_launch_current "$file" "$boundary" new; then fail "absent log proved a report"; fi
  printf 'done: incomplete' > "$file"
  if status_launch_current "$file" "$boundary" new; then fail "partial line proved a terminal report"; fi
  printf '\n' >> "$file"
  [ "$(status_launch_current "$file" "$boundary" new)" = 'done: incomplete' ] || fail "completed append was not reported"
  printf 'working: new partial declaration' >> "$file"
  if status_launch_current "$file" "$boundary" new; then fail "an unfinished later state retained terminal evidence"; fi
  printf 'working: old unfinished prefix' > "$file"
  boundary=$(status_launch_boundary "$file" newer)
  printf 'done: suffix of the previous line\n' >> "$file"
  if status_launch_current "$file" "$boundary" newer; then fail "old unfinished line became a replacement report"; fi
  printf 'done: new complete line\n' >> "$file"
  [ "$(status_launch_current "$file" "$boundary" newer)" = 'done: new complete line' ] || fail "new line after an old partial line was lost"
  pass "absent logs and partial lines do not masquerade as complete worker reports"
}

test_launch_status_changed_log_is_not_evidence() {
  local file boundary variant
  for variant in rotated truncated rewritten linked; do
    file="$TMP_ROOT/$variant.status"
    printf 'working: earlier worker with a long previous record\n' > "$file"
    boundary=$(status_launch_boundary "$file" replacement)
    case "$variant" in
      rotated) mv "$file" "$file.old"; printf 'working: earlier worker with a long previous record\n' > "$file" ;;
      truncated) : > "$file" ;;
      rewritten) printf 'working: different text of the same prefix length!!\n' > "$file" ;;
      linked) ln "$file" "$file.link" ;;
    esac
    printf 'done: not safely attributable\n' >> "$file"
    if status_launch_current "$file" "$boundary" replacement; then fail "$variant log confirmed a replacement"; fi
  done
  if status_launch_boundary "$TMP_ROOT/linked.status" next; then fail "multiply-linked evidence was accepted"; fi
  for boundary in 'v2|new|0|-|-' 'v1|new|bad|-|-' 'v1|new|0|-|-|extra'; do
    if status_launch_current "$TMP_ROOT/new.status" "$boundary" new; then fail "malformed boundary was accepted"; fi
  done
  pass "rotation, truncation, rewritten prefixes and linked evidence cannot confirm launch"
}

test_launch_status_changed_snapshot_is_not_evidence() {
  local file="$TMP_ROOT/racing.status" boundary
  printf 'working: old\n' > "$file"
  boundary=$(status_launch_boundary "$file" new)
  printf 'done: initial completion\n' >> "$file"
  cat > "$TMP_ROOT/append-reader" <<'SH'
#!/usr/bin/env bash
set -eu
perl -e 'open my $f, "<", $ARGV[0] or die $!; seek $f, $ARGV[1], 0; read $f, my $s, $ARGV[2]; print $s' "$@"
if [ "$3" -gt 1 ]; then printf 'working: resumed during the read\n' >> "$1"; fi
SH
  chmod +x "$TMP_ROOT/append-reader"
  if FM_STATUS_SPAN_READER="$TMP_ROOT/append-reader" status_launch_current "$file" "$boundary" new; then
    fail "a changed snapshot returned the stale terminal report"
  fi
  [ "$(status_launch_current "$file" "$boundary" new)" = 'working: resumed during the read' ] || fail "fresh retry did not reconcile the new activity"
  pass "a concurrent append invalidates the snapshot rather than returning stale completion"
}

test_launch_status_captured_copy_keeps_origin_proof() {
  local file="$TMP_ROOT/source.status" captured="$TMP_ROOT/captured.status" boundary
  printf 'done: predecessor\n' > "$file"
  boundary=$(status_launch_boundary "$file" replacement)
  printf 'done: replacement completed\n' >> "$file"
  cp "$file" "$captured"
  [ "$(status_launch_current "$captured" "$boundary" replacement "$file")" = 'done: replacement completed' ] \
    || fail "a captured copy lost its source's generation-bound report"
  printf 'working: another turn\n' >> "$file"
  if status_launch_current "$captured" "$boundary" replacement "$file"; then fail "a stale captured report hid newer work"; fi
  cp "$file" "$captured"
  printf 'done: invented snapshot completion\n' >> "$captured"
  if status_launch_current "$captured" "$boundary" replacement "$file"; then fail "an unproven captured append became evidence"; fi
  cp "$file" "$captured"
  ln "$captured" "$captured.link"
  if status_launch_current "$captured" "$boundary" replacement "$file"; then fail "a multiply-linked capture became evidence"; fi
  pass "captured reports retain their original file identity and cannot hide newer source activity"
}

test_launch_status_empty_span_reader_is_not_evidence() {
  local file="$TMP_ROOT/empty-reader.status" boundary
  boundary=$(status_launch_boundary "$file" replacement)
  printf 'done: replacement completed\n' > "$file"
  [ "$(status_launch_current "$file" "$boundary" replacement)" = 'done: replacement completed' ] \
    || fail "the empty-reader control fixture has no valid report"
  if FM_STATUS_SPAN_READER=true status_launch_current "$file" "$boundary" replacement; then
    fail "an empty configured span read silently fell back to the source"
  fi
  pass "an empty configured span reader cannot manufacture report evidence"
}

fm_test_run_cases \
  test_launch_status_only_reads_this_generation \
  test_launch_status_absent_and_incomplete_logs \
  test_launch_status_changed_log_is_not_evidence \
  test_launch_status_changed_snapshot_is_not_evidence \
  test_launch_status_captured_copy_keeps_origin_proof \
  test_launch_status_empty_span_reader_is_not_evidence

#!/usr/bin/env bash
# Regression coverage for local startup/report work that multiplied subprocess
# costs on Windows. Exercise the real readers, filesystem guards, and snapshot;
# keep safety/field assertions beside the operation-count and latency bounds.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-startup-performance)

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
  test_record_guards_use_fast_resolution_and_keep_fallback \
  test_routine_status_history_stays_bounded_and_keeps_decisions \
  test_snapshot_projection_bounds_json_tool_launches

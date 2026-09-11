#!/usr/bin/env bash
# fm-test-run.sh - single owner of Firstmate's behavior-test runner, lane
# composition for portable CI shards, local --jobs for proven-concurrent work,
# timing markers, and the complete-regression coverage guard.
#
# Selection modes (exactly one of: --all, --family, --changed, --lane,
# --proven-isolated, or script paths):
#   fm-test-run.sh --all
#   fm-test-run.sh --family <name>
#   fm-test-run.sh --changed [--base <git-ref>]
#   fm-test-run.sh --lane portable-parallel-1|portable-parallel-2|portable-serial
#   fm-test-run.sh --lane portable-serial-<k>of<n>   (one CI serial shard)
#   fm-test-run.sh --proven-isolated
#   fm-test-run.sh tests/<name>.test.sh [more scripts...]
#
# Inspection (no execution):
#   fm-test-run.sh --list --all
#   fm-test-run.sh --list --family <name>
#   fm-test-run.sh --list --lane portable-parallel-1
#   fm-test-run.sh --list-scheduled --family <name>
#   fm-test-run.sh --list-scheduled --lane portable-parallel-1
#   fm-test-run.sh --list-families
#   fm-test-run.sh --list-concurrent-safe-families
#   fm-test-run.sh --concurrent-safe-family-jobs-max <name>
#   fm-test-run.sh --list-lanes
#   fm-test-run.sh --check-coverage
#
# Aggregation (no suite execution):
#   fm-test-run.sh --aggregate-json <out.json> <lane.json> [more lane.json...]
#
# Options:
#   --json <path>   write a deterministic timing artifact after the run. Each
#                   script record carries its family, expected gate-skip class,
#                   exit, duration, whether it gate-skipped, and the reason it
#                   gave (empty when it ran), so a lane can say which harness or
#                   tool this host could not exercise.
#   --list          print selected script paths (one per line) and exit 0
#   --list-scheduled
#                   print selected paths longest-hint-first and exit 0.
#                   Only --lane portable-parallel-1 or portable-parallel-2 uses
#                   parallel hints, falling back to serial weights if missing.
#                   Every other selection uses serial weights alone.
#                   Equal weights are ordered by path under LC_ALL=C.
#   --base <ref>    with --changed, compare against this ref (default: origin/main)
#   --exclude-family <name>
#                   drop scripts whose primary family matches <name> after selection
#                   (repeatable; portable CI lanes exclude real-herdr-gated so the
#                   dedicated required Herdr lane owns that coverage)
#   --fail-on-gate-skip <token>
#                   after each script, fail the run if any output line contains
#                   "skip: <token>" (e.g. --fail-on-gate-skip 'herdr not found').
#                   The required Herdr CI lane uses this so a missing pin cannot
#                   silently pass as a gate skip.
#   --jobs N        run the selected scripts with up to N concurrent workers.
#                   Plain --changed and a plain list of script paths use
#                   min(4, cpus) workers when multiple selected scripts are
#                   admissible; --lane, --family, and --all stay serial unless
#                   asked for concurrency explicitly.
#                   N>1 is allowed only when every selected script is proven
#                   safe to run concurrently: individually in the proven-isolated
#                   set (bin/fm-test-isolation-proof.sh --list), or in a family
#                   carrying a recorded concurrent proof
#                   (list_concurrent_safe_families below). Overall cap is 8;
#                   family proofs may impose a lower cap. Individually proven
#                   scripts share one phase; scripts admitted only by a family
#                   proof run in a separate phase for each family. Concurrent
#                   phases use serial weights, longest-hint-first. Unproven stateful
#                   scripts, plus measured process-heavy Windows scripts, run
#                   serially after all concurrent phases. Default is 1 (serial)
#                   except for plain --changed and a plain list of script paths,
#                   which use the bounded automatic scheduler.
#   --per-script-timeout-secs N
#                   terminate a script that runs longer than N seconds and
#                   record it as exit 124 (0 disables, the default). --changed
#                   applies a 900s automatic floor, with larger measured bounds
#                   for process-heavy Git-for-Windows scripts. --max-wall-ms is
#                   checked after the run and so cannot catch a hang on its own.
#                   External interruption cleanup is outside this runner's
#                   guarantee; configured per-script bounds remain authoritative.
#   --max-wall-ms N fail the run when its measured invocation wall clock exceeds
#                   N milliseconds, including an empty selection. It is
#                   evaluated after selection and suite execution and cannot
#                   interrupt a running script; per-script hangs are
#                   bounded by --per-script-timeout-secs. Pathological output
#                   sinks that block finalization are explicitly out of scope.
#   -h, --help      print this header
#
# Per-script machine-parseable markers (stdout):
#   FM_TEST_BEGIN <iso8601> <script> family=<family> expected_gate_skip=<class>
#   FM_TEST_END <iso8601> <script> exit=<code> duration_ms=<n> gate_skip=<true|false>
#
# After all scripts (stdout):
#   FM_TEST_SUMMARY total=<n> failed=<n> skipped_gate=<n> duration_ms=<n>
#   FM_TEST_SUMMARY_FAMILY family=<name> count=<n> duration_ms=<n> failed=<n>
#   FM_TEST_SLOWEST rank=<k> script=<path> duration_ms=<n>
#   FM_TEST_BUDGET max_wall_ms=<n> duration_ms=<n>   (only with --max-wall-ms)
#
# Placement refusal:
#   A task worker is assigned an isolated worktree, and that placement is
#   checked only when its task starts. When FM_TASK_ID marks such a worker and
#   this runner resolves to the repository's PRIMARY checkout, every executing
#   mode refuses before selecting a suite: the suite creates and switches
#   branches, and the primary is the checkout every linked worktree resolves
#   against. Inspection modes execute nothing and stay available, and a run with
#   no FM_TASK_ID set is unchanged.
#
# Exit status is non-zero if any selected script exits non-zero, a configured
# --fail-on-gate-skip token appears, the measured duration exceeds
# --max-wall-ms, timing-artifact finalization fails, or a concurrent worker
# violates its isolation check. Other gate skips (first meaningful line
# matching ^skip:) remain successful and are counted as skipped_gate; each one
# is logged with its reason and recorded in the timing artifact.
#
# expected_gate_skip classes name why a family is allowed to skip: herdr (the
# pinned real-Herdr lane), optional-binary (a backend whose binary is optional),
# live-capability (a live-harness guard governed by fm_live_gate, which records
# unavailable tools and explicit policy skips; see tests/lib.sh), or none.
#
# Family labels, duration hints, gates and ordered changed-path registrations
# live in tests/catalog/{core,fork}.tsv, validated by fm-test-catalog-lib.sh.
# Scheduling, reference expansion and production portable-shard composition
# remain here. Portable and family admission evidence remains owned by
# bin/fm-test-isolation-proof.sh; portable parallel shards are a
# duration-balanced partition of that exact set, packed from the measured hints
# in portable_parallel_weight_hints (see docs/fm-test-portable-shards.md).
# --check-coverage reports parallel_max_ms (the larger lane hint sum),
# parallel_imbalance_ms (the absolute difference between the sums), and
# parallel_unhinted (the number of members missing a parallel hint).
# These sums exclude unhinted members and are estimates, not measured job wall
# times. Missing parallel hints are reported without failing this guard.
#
# portable-serial stays strictly serial. Its CI shards (portable-serial-<k>of<n>)
# split it across separate runners, so two of its stateful scripts still never
# share a machine. This script owns <n>: a lane whose <n> disagrees with the
# configured shard count is refused, so a CI matrix cannot silently drop a shard.
# --changed is conservative: it over-selects related families rather than
# under-selecting; their union can cover the complete inventory. The one
# place it is deliberately narrow is a bin/ path with no curated family: a test
# that names it is selected as that SCRIPT, because the reference is per-script
# evidence. Consumer bin/ scripts still resolve through the curated map, so
# recorded family-level coupling still expands to the whole family.
set -eu

now_ms() {
  local value
  value=$(date +%s%3N 2>/dev/null || true)
  case "$value" in
    ''|*[!0-9]*) ;;
    *)
      printf '%s\n' "$value"
      return
      ;;
  esac
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time() * 1000))'
  else
    echo $(($(date +%s) * 1000))
  fi
}

RUN_STARTED_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RUN_STARTED_MS=$(now_ms)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=bin/fm-private-path-lib.sh
. "$ROOT/bin/fm-private-path-lib.sh" || exit 1

MODE=
LIST_ONLY=0
LIST_SCHEDULED=0
LIST_FAMILIES=0
LIST_CONCURRENT_SAFE_FAMILIES=0
LIST_LANES=0
CHECK_COVERAGE=0
AGGREGATE_OUT=
FAMILY=
LANE=
BASE_REF=origin/main
JSON_PATH=
SCRIPTS=()
EXCLUDE_FAMILIES=()
FAIL_ON_GATE_SKIP=
JOBS=1
JOBS_EXPLICIT=0
JOBS_MAX=8
MAX_WALL_MS=
PER_SCRIPT_TIMEOUT_SECS=0
CHANGED_TIMEOUT_AUTOMATIC=0
RUNNER_UNAME_S=$(uname -s 2>/dev/null || true)
# Bound applied automatically on the automatic --changed path, derived from
# measured healthy runtimes with margin rather than picked. On ordinary hosts,
# 900s remains well above the slowest measured behavior script. Git-for-Windows
# exceptions below preserve the same role against that platform's much higher
# process-launch cost. These are guards, not speed controls: a HUNG script
# becomes a bounded failure instead of silently outrunning its caller.
CHANGED_DEFAULT_TIMEOUT_SECS=900
# Git Bash pays a much higher process-launch cost. These bounds retain a
# fail-closed tripwire above the measured September 4, 2026 healthy runs:
# 797s for the arm policy matrix, 2,638s for the Herdr backend contract, and
# 3,569s for the captain-hold lifecycle contract.
CHANGED_WINDOWS_ARM_TIMEOUT_SECS=1800
CHANGED_WINDOWS_HERDR_TIMEOUT_SECS=4500
CHANGED_WINDOWS_CAPTAIN_TIMEOUT_SECS=7200

# How many separate-runner shards the portable serial remainder splits into.
# One owner: CI lane names carry this count and are refused when they disagree.
PORTABLE_SERIAL_SHARDS=5

# Balance hint for a portable-serial script with no measured duration, close to
# the measured per-script mean so a newly added test neither starves nor
# overloads the shard it lands in.
PORTABLE_SERIAL_DEFAULT_WEIGHT_MS=27000

# Largest share of the serial lane allowed to run on the default weight above.
# Hints are what keep the shards balanced, so once too much of the lane is
# unmeasured the balance is guesswork and one shard can reach its CI job cap
# while another sits idle. The coverage guard refuses past this share, which
# leaves room for newly added tests while making a stale hint table fail loudly
# instead of silently. docs/fm-test-portable-shards.md owns the refresh.
PORTABLE_SERIAL_MAX_UNHINTED_PERCENT=15

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0" >&2
}

die() {
  printf 'fm-test-run: %s\n' "$*" >&2
  exit 2
}

log() {
  printf 'fm-test-run: %s\n' "$*" >&2
}

native_windows_private_directory_valid() {
  fm_private_path_native worker validate directory "$1"
}

worker_directory_private() {
  local dir=$1 mode
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  case "$(uname -s 2>/dev/null)" in
    MSYS*|MINGW*)
      native_windows_private_directory_valid "$dir"
      return
      ;;
  esac
  mode=$(stat -c %a "$dir" 2>/dev/null || /usr/bin/stat -f %Lp "$dir" 2>/dev/null) || return 1
  case "$mode" in
    700|0700) return 0 ;;
    *) return 1 ;;
  esac
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Enforce the placement refusal described in this script's header.
#
# The primary checkout is the working tree whose own git dir IS the repository's
# common git dir; every linked worktree has a git dir under it instead. That is
# the same predicate bin/fm-spawn.sh uses to keep a launch out of the primary,
# and unlike comparing top-level paths it still holds when the primary is
# reached through a different path. When git resolves neither directory - a
# non-repository fixture, a detached copy - nothing proves this is the primary,
# so the run proceeds.
refuse_primary_checkout_for_task() {
  local task_id git_dir common_dir top
  task_id=${FM_TASK_ID:-}
  [ -n "$task_id" ] || return 0
  git_dir=$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null) \
    && git_dir=$(cd "$git_dir" 2>/dev/null && pwd -P) || git_dir=
  common_dir=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    && common_dir=$(cd "$common_dir" 2>/dev/null && pwd -P) || common_dir=
  [ -n "$git_dir" ] && [ -n "$common_dir" ] || return 0
  [ "$git_dir" = "$common_dir" ] || return 0
  top=$(cd "$ROOT" && pwd -P)
  die "refusing to run in the repository primary checkout $top while FM_TASK_ID=$task_id is set; run from the assigned task worktree instead"
}

cpu_count() {
  local n
  n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
  case "$n" in
    ''|*[!0-9]*) n=1 ;;
  esac
  [ "$n" -ge 1 ] || n=1
  printf '%s\n' "$n"
}

running_on_windows() {
  case "$RUNNER_UNAME_S" in
    MSYS*|MINGW*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

# Primary family for one tests/*.test.sh basename. Unmapped scripts are
# unclassified so new tests are still runnable and visible in summaries.
#
# Family classification is metadata, not permission to run concurrently.
# New or reclassified members still need the proof owners admission evidence.
family_for_basename() {
  if fm_test_catalog_get test "tests/$1"; then
    printf '%s\n' "$FM_TEST_CATALOG_VALUE"
  else
    printf '%s\n' unclassified
  fi
}

expected_gate_skip_for_family() {
  if fm_test_catalog_get family "$1"; then
    printf '%s\n' "$FM_TEST_CATALOG_VALUE"
  else
    printf '%s\n' none
  fi
}

list_known_families() {
  printf '%s' "$FM_TEST_CATALOG_FAMILIES"
}

list_known_lanes() {
  local i
  printf '%s\n' portable-parallel-1
  printf '%s\n' portable-parallel-2
  printf '%s\n' portable-serial
  i=1
  while [ "$i" -le "$PORTABLE_SERIAL_SHARDS" ]; do
    printf 'portable-serial-%sof%s\n' "$i" "$PORTABLE_SERIAL_SHARDS"
    i=$((i + 1))
  done
  printf '%s\n' real-herdr-gated
}

# Exact proven-isolated candidate set (same paths as
# bin/fm-test-isolation-proof.sh --list). Do not expand without a new concurrent
# isolation proof archive.
list_proven_isolated() {
  [ -z "$PROVEN_ISOLATED_LIST" ] || printf '%s\n' "$PROVEN_ISOLATED_LIST"
}

# Load metadata and independent proof results once, before any selection mode.
[ -r "$ROOT/bin/fm-test-catalog-lib.sh" ] || die "required test catalog loader is missing"
# shellcheck source=bin/fm-test-catalog-lib.sh
. "$ROOT/bin/fm-test-catalog-lib.sh" || die "could not load the test catalog module"
fm_test_catalog_load "$ROOT" || die "invalid test catalog"
[ -x "$ROOT/bin/fm-test-isolation-proof.sh" ] || die "required isolation proof owner is missing"
PROVEN_ISOLATED_LIST=$("$ROOT/bin/fm-test-isolation-proof.sh" --list) \
  || die "could not read the portable isolation proof list"
FAMILY_ADMISSION_LIST=$("$ROOT/bin/fm-test-isolation-proof.sh" --list-family-admissions) \
  || die "could not read the family isolation proof admissions"
while IFS= read -r proof_path; do
  [ -n "$proof_path" ] || continue
  case "$proof_path" in
    tests/*.test.sh) [ -f "$ROOT/$proof_path" ] || die "proof references missing test: $proof_path" ;;
    *) die "invalid portable proof path: $proof_path" ;;
  esac
done <<<"$PROVEN_ISOLATED_LIST"

# Per-script serial CI duration hints, one "<path> <ms>" per line, used to
# pack only the two portable parallel lanes. Measurement provenance and the
# refresh procedure are owned by docs/fm-test-portable-shards.md.
portable_parallel_weight_hints() {
  printf '%s' "$FM_TEST_CATALOG_PARALLEL_WEIGHTS"
}

# Sum the hints above for the scripts read on stdin, and report how many of
# them had no hint at all, as "<summed_ms> <unhinted_count>".
portable_parallel_lane_weight() {
  awk '
    FILENAME != "-" { if (NF) { hint[$1] = $2 } ; next }
    NF {
      if ($1 in hint) { total += hint[$1] } else { unhinted++ }
    }
    END { printf "%d %d\n", total + 0, unhinted + 0 }
  ' <(portable_parallel_weight_hints) -
}

# Portable parallel shard 1: LPT balance of the proven-isolated set over the
# hints above. Stored order agrees with this lane's --list-scheduled output.
# tests/fm-pi-primary-types.test.sh belongs to this lane because
# this is the parallel job that installs the Pi package; moving it needs that
# workflow step moved with it.
list_portable_parallel_1() {
  cat <<'EOF'
tests/fm-lint.test.sh
tests/fm-pr-merge.test.sh
tests/fm-test-run.test.sh
tests/fm-cd-pretool-check.test.sh
tests/fm-pi-primary-types.test.sh
tests/fm-grok-harness.test.sh
tests/fm-composer-lib.test.sh
tests/fm-review-diff.test.sh
tests/fm-tmux-submit-busy.test.sh
tests/fm-composer-ghost.test.sh
tests/fm-brief.test.sh
EOF
}

# Portable parallel shard 2: the complementary LPT half of the proven set.
list_portable_parallel_2() {
  cat <<'EOF'
tests/fm-captain-hold-lifecycle.test.sh
tests/fm-x-mode.test.sh
tests/fm-arm-pretool-check.test.sh
tests/fm-backend-herdr.test.sh
tests/fm-crew-state.test.sh
tests/fm-herdr-lab.test.sh
tests/fm-send-popup-settle.test.sh
tests/fm-send-strict.test.sh
tests/fm-spawn-batch.test.sh
tests/fm-send-settle.test.sh
tests/fm-ensure-agents-md.test.sh
tests/fm-supervision-instructions.test.sh
tests/fm-transition-lib.test.sh
EOF
}

# Families whose scripts are proven safe to run concurrently WITH EACH OTHER
# under the bounded local scheduler. Deliberately separate from the
# proven-isolated set, which must stay exactly equal to the portable CI shard
# union (see the coverage guard); these families keep their serial CI lane and
# only gain concurrency for a local run.
#
# Membership is empirical, never assumed:
# `bin/fm-test-isolation-proof.sh --pool <family> --jobs 4` is the owner of the
# proof, and docs/fm-test-isolation-proof.md records the dated result.
list_concurrent_safe_families() {
  cat <<'EOF'
watcher-wake-lock
pure-contract-unit
pr-forge
secondmate
session-bootstrap
standalone
EOF
}

family_is_concurrent_safe() {
  local want=$1 line
  while IFS= read -r line; do
    [ "$line" = "$want" ] && return 0
  done < <(list_concurrent_safe_families)
  return 1
}

concurrent_safe_family_jobs_max() {
  case "$1" in
    watcher-wake-lock|pure-contract-unit|pr-forge) printf '4\n' ;;
    secondmate|session-bootstrap|standalone) printf '4\n' ;;
    *) printf '1\n' ;;
  esac
}

# A script may run under --jobs when it is individually proven isolated or is
# an exact repository member of a family carrying a recorded concurrent proof.
script_allows_concurrency() {
  local s=$1 family repo_script
  is_proven_isolated_script "$s" && return 0
  family=$(family_for_basename "${s##*/}")
  family_is_concurrent_safe "$family" || return 1
  case $'\n'"$FAMILY_ADMISSION_LIST"$'\n' in
    *$'\n'"$family"$'\t'"$s"$'\n'*) ;;
    *) return 1 ;;
  esac
  while IFS= read -r repo_script; do
    [ "$repo_script" = "$s" ] && return 0
  done < <(all_repo_tests)
  return 1
}

automatic_concurrency_allowed() {
  local s=$1
  script_allows_concurrency "$s" || return 1
  running_on_windows || return 0
  # These scripts are logically isolated, but their process-heavy Windows runs
  # must not compete with another test: captain lifecycle reads can cross their
  # own bounded registry windows, while arm and Herdr need their measured
  # automatic timeout headroom preserved.
  case "${s##*/}" in
    fm-arm-pretool-check.test.sh|\
    fm-backend-herdr.test.sh|\
    fm-captain-hold-lifecycle.test.sh)
      return 1
      ;;
  esac
  return 0
}

automatic_changed_timeout_secs_for() {  # <script>
  if running_on_windows; then
    case "${1##*/}" in
      fm-arm-pretool-check.test.sh)
        printf '%s\n' "$CHANGED_WINDOWS_ARM_TIMEOUT_SECS"
        return
        ;;
      fm-backend-herdr.test.sh)
        printf '%s\n' "$CHANGED_WINDOWS_HERDR_TIMEOUT_SECS"
        return
        ;;
      fm-captain-hold-lifecycle.test.sh)
        printf '%s\n' "$CHANGED_WINDOWS_CAPTAIN_TIMEOUT_SECS"
        return
        ;;
    esac
  fi
  printf '%s\n' "$CHANGED_DEFAULT_TIMEOUT_SECS"
}

is_proven_isolated_script() {
  local want=$1
  case $'\n'"$PROVEN_ISOLATED_LIST"$'\n' in
    *$'\n'"$want"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

# The portable serial remainder: every tests/*.test.sh that is neither
# proven-isolated nor real-herdr-gated. Watcher, lock, AFK, real tmux, daemon,
# secondmate lifecycle, bootstrap, the live-harness-optin family, GUI-backend,
# and other unproven work stays here. Derived rather than enumerated so a newly added test
# lands here by default instead of falling out of every lane.
list_portable_serial() {
  local s base fam
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    base=${s##*/}
    fam=$(family_for_basename "$base")
    if [ "$fam" = "real-herdr-gated" ]; then
      continue
    fi
    if is_proven_isolated_script "$s"; then
      continue
    fi
    printf '%s\n' "$s"
  done < <(all_repo_tests)
}

# Catalog duration hints are milliseconds. docs/fm-test-portable-shards.md owns
# the evidence and refresh procedure; these hints never grant concurrency.
portable_serial_weight_hints() {
  printf '%s' "$FM_TEST_CATALOG_WEIGHTS"
}

# The portable-serial scripts with no measured hint, one per line. These fall
# back to PORTABLE_SERIAL_DEFAULT_WEIGHT_MS, so they are balanced on a guess
# rather than on evidence; the coverage guard bounds how many there may be.
portable_serial_unhinted() {
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-test-unhinted.XXXXXX") || return 1
  portable_serial_weight_hints | awk 'NF { print $1 }' | LC_ALL=C sort -u >"$tmp/hinted"
  list_portable_serial | LC_ALL=C sort -u >"$tmp/serial"
  LC_ALL=C comm -23 "$tmp/serial" "$tmp/hinted"
  rm -rf "$tmp"
}

portable_parallel_weight_for() {
  if fm_test_catalog_get parallel-duration "$1"; then
    printf '%s\n' "$FM_TEST_CATALOG_VALUE"
    return 0
  fi
  portable_serial_weight_for "$1"
}

portable_serial_weight_for() {
  if fm_test_catalog_get duration "$1"; then
    printf '%s\n' "$FM_TEST_CATALOG_VALUE"
  else
    printf '%s\n' "$PORTABLE_SERIAL_DEFAULT_WEIGHT_MS"
  fi
}

portable_serial_weighted_paths() {
  awk -v default_weight="$PORTABLE_SERIAL_DEFAULT_WEIGHT_MS" '
    FILENAME != "-" {
      weights[$1] = $2
      next
    }
    NF {
      weight = ($1 in weights) ? weights[$1] : default_weight
      print weight "\t" $1
    }
  ' <(portable_serial_weight_hints) -
}

# Longest-processing-time assignment of the serial remainder to
# PORTABLE_SERIAL_SHARDS bins, printing "<shard>\t<script>" for every script.
# Deterministic: candidates are ordered by hint descending then path, and ties
# between equally loaded bins always take the lowest bin index.
portable_serial_assignments() {
  local ms script i best best_load
  local -a loads=()
  i=1
  while [ "$i" -le "$PORTABLE_SERIAL_SHARDS" ]; do
    loads[i]=0
    i=$((i + 1))
  done
  while IFS=$'\t' read -r ms script; do
    [ -n "$script" ] || continue
    best=1
    best_load=${loads[1]}
    i=2
    while [ "$i" -le "$PORTABLE_SERIAL_SHARDS" ]; do
      if [ "${loads[i]}" -lt "$best_load" ]; then
        best_load=${loads[i]}
        best=$i
      fi
      i=$((i + 1))
    done
    loads[best]=$((best_load + ms))
    printf '%s\t%s\n' "$best" "$script"
  done < <(
    list_portable_serial |
      portable_serial_weighted_paths |
      LC_ALL=C sort -t$'\t' -k1,1nr -k2,2
  )
}

# Parse "<k>of<n>" from a portable-serial shard lane and echo <k>, refusing when
# <n> disagrees with this script's configured count so a CI matrix built for a
# different shard count fails loudly instead of dropping tests.
portable_serial_shard_index() {
  local lane=$1 spec index count
  spec=${lane#portable-serial-}
  index=${spec%%of*}
  count=${spec#*of}
  case "$spec" in
    *of*) ;;
    *) die "unknown lane '$lane' (see --list-lanes)" ;;
  esac
  case "$index" in
    ''|*[!0-9]*) die "unknown lane '$lane' (see --list-lanes)" ;;
  esac
  case "$count" in
    ''|*[!0-9]*) die "unknown lane '$lane' (see --list-lanes)" ;;
  esac
  if [ "$count" -ne "$PORTABLE_SERIAL_SHARDS" ]; then
    die "lane '$lane' asks for $count portable serial shards but this runner is configured for $PORTABLE_SERIAL_SHARDS (see --list-lanes)"
  fi
  if [ "$index" -lt 1 ] || [ "$index" -gt "$PORTABLE_SERIAL_SHARDS" ]; then
    die "lane '$lane' shard index is outside 1..$PORTABLE_SERIAL_SHARDS (see --list-lanes)"
  fi
  printf '%s\n' "$index"
}

select_proven_isolated() {
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    add_script "$s"
  done < <(list_proven_isolated)
}

select_lane() {
  local want=$1 s shard idx found=0
  case "$want" in
    portable-parallel-1)
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        add_script "$s"
        found=1
      done < <(list_portable_parallel_1)
      ;;
    portable-parallel-2)
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        add_script "$s"
        found=1
      done < <(list_portable_parallel_2)
      ;;
    portable-serial)
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        add_script "$s"
        found=1
      done < <(list_portable_serial)
      ;;
    portable-serial-*)
      # One separate-runner shard of the same remainder, still serial in itself.
      shard=$(portable_serial_shard_index "$want")
      while IFS=$'\t' read -r idx s; do
        [ -n "$s" ] || continue
        if [ "$idx" = "$shard" ]; then
          add_script "$s"
          found=1
        fi
      done < <(portable_serial_assignments)
      ;;
    real-herdr-gated)
      select_family real-herdr-gated
      found=1
      ;;
    *)
      die "unknown lane '$want' (see --list-lanes)"
      ;;
  esac
  [ "$found" -eq 1 ] || die "lane '$want' selected no tests"
}

run_coverage_guard() {
  local tmp missing extra a b shard unhinted serial_total
  local p1_ms p1_unhinted p2_ms p2_unhinted parallel_max_ms parallel_imbalance_ms
  local -a saved_scripts=()
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-test-coverage.XXXXXX")

  all_repo_tests | LC_ALL=C sort -u >"$tmp/all"
  list_proven_isolated | LC_ALL=C sort -u >"$tmp/proven"
  list_portable_parallel_1 | LC_ALL=C sort -u >"$tmp/s1"
  list_portable_parallel_2 | LC_ALL=C sort -u >"$tmp/s2"

  cat "$tmp/s1" "$tmp/s2" | LC_ALL=C sort | uniq -d >"$tmp/shard_dups"
  if [ -s "$tmp/shard_dups" ]; then
    log "coverage guard: portable parallel shards share scripts:"
    cat "$tmp/shard_dups" >&2
    rm -rf "$tmp"
    return 1
  fi
  cat "$tmp/s1" "$tmp/s2" | LC_ALL=C sort -u >"$tmp/shards_union"
  missing=$(LC_ALL=C comm -23 "$tmp/proven" "$tmp/shards_union" || true)
  extra=$(LC_ALL=C comm -13 "$tmp/proven" "$tmp/shards_union" || true)
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    log "coverage guard: portable shards must equal the proven-isolated set"
    [ -z "$missing" ] || { log "missing from shards:"; printf '%s\n' "$missing" >&2; }
    [ -z "$extra" ] || { log "extra beyond proven:"; printf '%s\n' "$extra" >&2; }
    rm -rf "$tmp"
    return 1
  fi

  # Serial (whole lane and each CI shard) + Herdr lane listings without
  # disturbing a caller's selection.
  saved_scripts=("${SCRIPTS[@]+"${SCRIPTS[@]}"}")
  SCRIPTS=()
  select_lane portable-serial
  printf '%s\n' "${SCRIPTS[@]+"${SCRIPTS[@]}"}" | LC_ALL=C sort -u >"$tmp/serial"
  : >"$tmp/serial_shards_raw"
  shard=1
  while [ "$shard" -le "$PORTABLE_SERIAL_SHARDS" ]; do
    SCRIPTS=()
    select_lane "portable-serial-${shard}of${PORTABLE_SERIAL_SHARDS}"
    if [ "${#SCRIPTS[@]}" -eq 0 ]; then
      log "coverage guard: portable serial shard $shard of $PORTABLE_SERIAL_SHARDS is empty"
      SCRIPTS=("${saved_scripts[@]+"${saved_scripts[@]}"}")
      rm -rf "$tmp"
      return 1
    fi
    printf '%s\n' "${SCRIPTS[@]+"${SCRIPTS[@]}"}" >>"$tmp/serial_shards_raw"
    shard=$((shard + 1))
  done
  SCRIPTS=()
  select_family real-herdr-gated
  printf '%s\n' "${SCRIPTS[@]+"${SCRIPTS[@]}"}" | LC_ALL=C sort -u >"$tmp/herdr"
  SCRIPTS=("${saved_scripts[@]+"${saved_scripts[@]}"}")

  # Every serial script runs in exactly one CI shard: no duplicate work across
  # runners, and no script silently left out of the required lane.
  LC_ALL=C sort "$tmp/serial_shards_raw" | uniq -d >"$tmp/serial_shard_dups"
  if [ -s "$tmp/serial_shard_dups" ]; then
    log "coverage guard: portable serial shards share scripts:"
    cat "$tmp/serial_shard_dups" >&2
    rm -rf "$tmp"
    return 1
  fi
  LC_ALL=C sort -u "$tmp/serial_shards_raw" >"$tmp/serial_shards"
  missing=$(LC_ALL=C comm -23 "$tmp/serial" "$tmp/serial_shards" || true)
  extra=$(LC_ALL=C comm -13 "$tmp/serial" "$tmp/serial_shards" || true)
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    log "coverage guard: portable serial shards must equal the portable serial lane"
    [ -z "$missing" ] || { log "missing from serial shards:"; printf '%s\n' "$missing" >&2; }
    [ -z "$extra" ] || { log "extra beyond serial lane:"; printf '%s\n' "$extra" >&2; }
    rm -rf "$tmp"
    return 1
  fi

  for pair in "shards_union:serial" "shards_union:herdr" "serial:herdr"; do
    a=${pair%%:*}
    b=${pair#*:}
    LC_ALL=C comm -12 "$tmp/$a" "$tmp/$b" >"$tmp/overlap"
    if [ -s "$tmp/overlap" ]; then
      log "coverage guard: overlap between $a and $b:"
      cat "$tmp/overlap" >&2
      rm -rf "$tmp"
      return 1
    fi
  done

  cat "$tmp/shards_union" "$tmp/serial" "$tmp/herdr" | LC_ALL=C sort >"$tmp/union_raw"
  uniq -d "$tmp/union_raw" >"$tmp/union_dups"
  if [ -s "$tmp/union_dups" ]; then
    log "coverage guard: duplicate scripts across lanes:"
    cat "$tmp/union_dups" >&2
    rm -rf "$tmp"
    return 1
  fi
  LC_ALL=C sort -u "$tmp/union_raw" >"$tmp/union"
  missing=$(LC_ALL=C comm -23 "$tmp/all" "$tmp/union" || true)
  extra=$(LC_ALL=C comm -13 "$tmp/all" "$tmp/union" || true)
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    log "coverage guard: union of portable shards + portable serial + Herdr must equal tests/*.test.sh"
    [ -z "$missing" ] || { log "missing from union:"; printf '%s\n' "$missing" >&2; }
    [ -z "$extra" ] || { log "extra beyond inventory:"; printf '%s\n' "$extra" >&2; }
    rm -rf "$tmp"
    return 1
  fi

  # Hint drift is what makes a balanced-looking partition run unbalanced: the
  # shards are packed from hints, so every unmeasured script is balanced on a
  # guess and enough of them let one shard reach its CI job cap while another
  # runner sits idle. Bound the unmeasured share here rather than waiting for a
  # shard to time out.
  portable_serial_unhinted >"$tmp/unhinted"
  unhinted=$(wc -l <"$tmp/unhinted" | tr -d ' ')
  serial_total=$(wc -l <"$tmp/serial" | tr -d ' ')
  if [ "$serial_total" -gt 0 ] &&
    [ "$((unhinted * 100))" -gt "$((serial_total * PORTABLE_SERIAL_MAX_UNHINTED_PERCENT))" ]; then
    log "coverage guard: $unhinted of $serial_total portable serial scripts have no measured duration hint (max ${PORTABLE_SERIAL_MAX_UNHINTED_PERCENT}%)"
    log "refresh the hints from a green run's timing artifacts: docs/fm-test-portable-shards.md"
    cat "$tmp/unhinted" >&2
    rm -rf "$tmp"
    return 1
  fi


  # Keep these estimates derived from the membership and hint owners; see the
  # header for the distinction between packed weights and measured job time.
  read -r p1_ms p1_unhinted <<<"$(list_portable_parallel_1 | portable_parallel_lane_weight)"
  read -r p2_ms p2_unhinted <<<"$(list_portable_parallel_2 | portable_parallel_lane_weight)"
  parallel_max_ms=$p1_ms
  [ "$p2_ms" -le "$parallel_max_ms" ] || parallel_max_ms=$p2_ms
  parallel_imbalance_ms=$((p1_ms - p2_ms))
  [ "$parallel_imbalance_ms" -ge 0 ] || parallel_imbalance_ms=$((-parallel_imbalance_ms))

  printf 'FM_TEST_COVERAGE ok total=%s parallel=%s parallel_max_ms=%s parallel_imbalance_ms=%s parallel_unhinted=%s serial=%s serial_shards=%s serial_unhinted=%s herdr=%s\n' \
    "$(wc -l <"$tmp/all" | tr -d ' ')" \
    "$(wc -l <"$tmp/shards_union" | tr -d ' ')" \
    "$parallel_max_ms" \
    "$parallel_imbalance_ms" \
    "$((p1_unhinted + p2_unhinted))" \
    "$(wc -l <"$tmp/serial" | tr -d ' ')" \
    "$PORTABLE_SERIAL_SHARDS" \
    "$unhinted" \
    "$(wc -l <"$tmp/herdr" | tr -d ' ')"
  rm -rf "$tmp"
  return 0
}

aggregate_timing_json() {
  local out=$1
  shift
  [ "$#" -gt 0 ] || die "--aggregate-json requires at least one input timing JSON"
  command -v python3 >/dev/null 2>&1 || die "--aggregate-json requires python3"
  python3 - "$out" "$@" <<'PY'
import json, sys
from pathlib import Path

out = Path(sys.argv[1])
inputs = [Path(p) for p in sys.argv[2:]]
lanes = []
all_scripts = []
failed = 0
skipped = 0
total = 0
wall_ms = 0
for path in inputs:
    doc = json.loads(path.read_text(encoding="utf-8"))
    summary = doc.get("summary") or {}
    lane = {
        "path": str(path),
        "run_id": doc.get("run_id"),
        "selection": doc.get("selection"),
        "started_at": doc.get("started_at"),
        "finished_at": doc.get("finished_at"),
        "summary": summary,
    }
    lanes.append(lane)
    total += int(summary.get("total") or 0)
    failed += int(summary.get("failed") or 0)
    skipped += int(summary.get("skipped_gate") or 0)
    wall_ms = max(wall_ms, int(summary.get("duration_ms") or 0))
    for s in doc.get("scripts") or []:
        row = dict(s)
        row["lane_selection"] = doc.get("selection")
        row["lane_run_id"] = doc.get("run_id")
        all_scripts.append(row)

all_scripts.sort(key=lambda s: (-int(s.get("duration_ms") or 0), s.get("path") or ""))
agg = {
    "kind": "aggregate",
    "lanes": lanes,
    "summary": {
        "lanes": len(lanes),
        "total": total,
        "failed": failed,
        "skipped_gate": skipped,
        "critical_path_duration_ms": wall_ms,
    },
    "scripts": all_scripts,
    "slowest": all_scripts[:15],
}
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(agg, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"FM_TEST_AGGREGATE lanes={len(lanes)} total={total} failed={failed} skipped_gate={skipped} critical_path_duration_ms={wall_ms}")
PY
}

all_repo_tests() {
  # Deterministic lexical order (same as bash glob expansion under LC_ALL=C).
  local f
  # shellcheck disable=SC2035
  for f in tests/*.test.sh; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f"
  done | LC_ALL=C sort
}

normalize_script_path() {
  local p=$1
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    tests/*|./tests/*)
      p=${p#./}
      printf '%s\n' "$p"
      ;;
    *.test.sh)
      if [ -f "tests/$p" ]; then
        printf 'tests/%s\n' "$p"
      else
        printf '%s\n' "$p"
      fi
      ;;
    *)
      printf '%s\n' "$p"
      ;;
  esac
}

# Append unique relative-or-absolute script paths to SCRIPTS.
add_script() {
  local p existing
  p=$(normalize_script_path "$1")
  for existing in "${SCRIPTS[@]+"${SCRIPTS[@]}"}"; do
    [ "$existing" = "$p" ] && return 0
  done
  SCRIPTS+=("$p")
}

select_all() {
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    add_script "$s"
  done < <(all_repo_tests)
}

select_family() {
  local want=$1 s base fam found=0
  [ -n "$want" ] || die "--family requires a name"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    base=${s##*/}
    fam=$(family_for_basename "$base")
    if [ "$fam" = "$want" ]; then
      add_script "$s"
      found=1
    fi
  done < <(all_repo_tests)
  [ "$found" -eq 1 ] || die "no tests mapped to family '$want'"
}

CHANGED_REFERENCE_INDEX=
CHANGED_REFERENCE_LOOKUP=0
CHANGED_REFERENCE_RESULTS=()

clear_changed_reference_lookup() {
  CHANGED_REFERENCE_INDEX=
  CHANGED_REFERENCE_LOOKUP=0
  CHANGED_REFERENCE_RESULTS=()
  unset -f changed_reference_lookup 2>/dev/null || true
}

prepare_changed_reference_index() {
  local changed_paths=$1 patterns=$2 index_file=$3 all_tests=$4
  local path fixture_ref b s
  local -a reference_files=()

  : >"$patterns"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\n' "$path" >>"$patterns"
    case "$path" in
      .opencode/plugins/*|.pi/extensions/*|\
      tests/lib.sh|tests/*-helpers.sh|tests/*-fixture.sh|tests/fixtures.sh|tests/assets/*)
        printf '%s\n' "${path##*/}" >>"$patterns"
        ;;
      tests/fixtures/*/*)
        fixture_ref=${path#tests/fixtures/}
        fixture_ref=${fixture_ref%%/*}
        printf 'fixtures/%s\n' "$fixture_ref" >>"$patterns"
        ;;
    esac
  done <"$changed_paths"

  while IFS= read -r s; do
    [ -n "$s" ] || continue
    reference_files+=("$s")
  done <"$all_tests"
  for b in bin/*.sh bin/*.mjs bin/*.ps1 bin/backends/*.sh bin/harnesses/*.sh bin/platform/*.sh bin/platform/*.mjs bin/platform/*.d.mts bin/platform/*.ps1; do
    [ -f "$b" ] || continue
    reference_files+=("$b")
    printf '%s\n' "${b##*/}" >>"$patterns"
  done

  LC_ALL=C sort -u "$patterns" -o "$patterns"
  : >"$index_file"
  [ -s "$patterns" ] && [ "${#reference_files[@]}" -gt 0 ] || return 0
  if command -v perl >/dev/null 2>&1; then
    perl - "$patterns" "${reference_files[@]}" >"$index_file" <<'PL'
use strict;
use warnings;

my $patterns_path = shift @ARGV;
open my $patterns_fh, '<', $patterns_path or die "$patterns_path: $!\n";
chomp(my @patterns = <$patterns_fh>);
close $patterns_fh;
@patterns = grep { length } @patterns;

my %matches;
for my $file (@ARGV) {
  open my $file_fh, '<', $file or next;
  local $/;
  my $content = <$file_fh>;
  close $file_fh;
  for my $pattern (@patterns) {
    push @{$matches{$pattern}}, $file if index($content, $pattern) >= 0;
  }
}

sub shell_quote {
  my ($value) = @_;
  $value =~ s/'/'"'"'/g;
  return "'$value'";
}

print "changed_reference_lookup() {\n";
print "  CHANGED_REFERENCE_RESULTS=()\n";
print "  case \"\$1\" in\n";
for my $pattern (@patterns) {
  next unless exists $matches{$pattern};
  print "    ", shell_quote($pattern), ")\n";
  print "      CHANGED_REFERENCE_RESULTS=(",
    join(" ", map { shell_quote($_) } @{$matches{$pattern}}), ")\n";
  print "      ;;\n";
}
print "  esac\n";
print "}\n";
PL
    # shellcheck source=/dev/null
    . "$index_file"
    CHANGED_REFERENCE_LOOKUP=1
    return 0
  else
    grep -F -H -f "$patterns" -- "${reference_files[@]}" 2>/dev/null \
      | awk -v OFS='\t' '
          NR == FNR {
            if ($0 != "" && !pattern_seen[$0]++) {
              patterns[++pattern_count] = $0
            }
            next
          }
          {
            separator = index($0, ":")
            if (separator == 0) {
              next
            }
            file = substr($0, 1, separator - 1)
            text = substr($0, separator + 1)
            for (i = 1; i <= pattern_count; i++) {
              if (index(text, patterns[i])) {
                key = patterns[i] SUBSEP file
                if (!match_seen[key]++) {
                  print patterns[i], file
                }
              }
            }
          }
        ' "$patterns" - >"$index_file"
  fi
}

test_files_referencing() {
  local needle=$1 indexed_needle s
  local found=0
  local -a test_files=()

  if [ "$CHANGED_REFERENCE_LOOKUP" -eq 1 ]; then
    changed_reference_lookup "$needle"
    for s in "${CHANGED_REFERENCE_RESULTS[@]+"${CHANGED_REFERENCE_RESULTS[@]}"}"; do
      case "$s" in
        tests/*.test.sh)
          printf '%s\n' "$s"
          found=1
          ;;
      esac
    done
    [ "$found" -eq 1 ]
    return
  fi

  if [ -n "$CHANGED_REFERENCE_INDEX" ] && [ -f "$CHANGED_REFERENCE_INDEX" ]; then
    while IFS=$'\t' read -r indexed_needle s; do
      [ "$indexed_needle" = "$needle" ] || continue
      case "$s" in
        tests/*.test.sh)
          printf '%s\n' "$s"
          found=1
          ;;
      esac
    done <"$CHANGED_REFERENCE_INDEX"
    [ "$found" -eq 1 ]
    return
  fi

  while IFS= read -r s; do
    [ -n "$s" ] || continue
    test_files+=("$s")
  done < <(all_repo_tests)
  [ "${#test_files[@]}" -gt 0 ] || return 1

  grep -F -l -- "$needle" "${test_files[@]}" 2>/dev/null
}

families_for_test_reference() {
  local needle=$1 s
  local found=0
  if [ "$CHANGED_REFERENCE_LOOKUP" -eq 1 ]; then
    changed_reference_lookup "$needle"
    for s in "${CHANGED_REFERENCE_RESULTS[@]+"${CHANGED_REFERENCE_RESULTS[@]}"}"; do
      case "$s" in
        tests/*.test.sh)
          family_for_basename "${s##*/}"
          found=1
          ;;
      esac
    done
    [ "$found" -eq 1 ]
    return
  fi

  while IFS= read -r s; do
    [ -n "$s" ] || continue
    family_for_basename "${s##*/}"
    found=1
  done < <(test_files_referencing "$needle")
  [ "$found" -eq 1 ]
}

# Tests that name <needle>, selected as individual scripts rather than widened
# to each referencing test's whole family. A direct reference is per-script
# evidence, so it selects per script: one real-Herdr E2E sourcing a shared
# helper must not drag in every other script of that expensive family.
scripts_for_test_reference() {
  local needle=$1 s
  local found=0
  if [ "$CHANGED_REFERENCE_LOOKUP" -eq 1 ]; then
    changed_reference_lookup "$needle"
    for s in "${CHANGED_REFERENCE_RESULTS[@]+"${CHANGED_REFERENCE_RESULTS[@]}"}"; do
      case "$s" in
        tests/*.test.sh)
          printf '__script__:%s\n' "${s##*/}"
          found=1
          ;;
      esac
    done
    [ "$found" -eq 1 ]
    return
  fi

  while IFS= read -r s; do
    [ -n "$s" ] || continue
    printf '__script__:%s\n' "${s##*/}"
    found=1
  done < <(test_files_referencing "$needle")
  [ "$found" -eq 1 ]
}

# bin/ scripts other than <needle> itself that name <needle>.
bin_consumers_of() {
  local needle=$1 indexed_needle b
  local -a consumers=()
  if [ "$CHANGED_REFERENCE_LOOKUP" -eq 1 ]; then
    changed_reference_lookup "$needle"
    for b in "${CHANGED_REFERENCE_RESULTS[@]+"${CHANGED_REFERENCE_RESULTS[@]}"}"; do
      case "$b" in
        bin/*.sh|bin/*.mjs|bin/*.d.mts|bin/*.ps1)
          [ "${b##*/}" = "$needle" ] || printf '%s\n' "$b"
          ;;
      esac
    done
    return 0
  fi

  if [ -n "$CHANGED_REFERENCE_INDEX" ] && [ -f "$CHANGED_REFERENCE_INDEX" ]; then
    while IFS=$'\t' read -r indexed_needle b; do
      [ "$indexed_needle" = "$needle" ] || continue
      case "$b" in
        bin/*.sh|bin/*.mjs|bin/*.d.mts|bin/*.ps1)
          [ "${b##*/}" = "$needle" ] || printf '%s\n' "$b"
          ;;
      esac
    done <"$CHANGED_REFERENCE_INDEX"
    return 0
  fi

  for b in bin/*.sh bin/*.mjs bin/*.ps1 bin/backends/*.sh bin/harnesses/*.sh bin/platform/*.sh bin/platform/*.mjs bin/platform/*.d.mts bin/platform/*.ps1; do
    [ -f "$b" ] || continue
    [ "${b##*/}" = "$needle" ] || consumers+=("$b")
  done
  [ "${#consumers[@]}" -gt 0 ] || return 0
  grep -F -l -- "$needle" "${consumers[@]}" 2>/dev/null || true
}

# An unmapped bin/ path has no curated family of its own. Its blast radius is
# the tests that name it, plus the curated families of the bin/ scripts that
# consume it. Direct test references resolve per script (above) while consumer
# scripts resolve back through the curated map, so genuine family-level
# coupling a maintainer recorded is preserved while an incidental single-script
# reference no longer selects that script's whole family.
BIN_FALLBACK_DEPTH=0
CHANGED_SUPPRESS_UNMAPPED=0

emit_unmapped_changed_path() {
  local path=$1
  [ "$CHANGED_SUPPRESS_UNMAPPED" -eq 0 ] || return 1
  printf '%s\n' "__unmapped__:$path"
}

families_for_unmapped_bin() {
  local path=$1 needle consumer out found=0
  needle=${path##*/}
  if [ "$CHANGED_REFERENCE_LOOKUP" -eq 1 ]; then
    if scripts_for_test_reference "$needle"; then
      found=1
    fi
    if [ "$BIN_FALLBACK_DEPTH" -lt 2 ]; then
      BIN_FALLBACK_DEPTH=$((BIN_FALLBACK_DEPTH + 1))
      changed_reference_lookup "$needle"
      for consumer in "${CHANGED_REFERENCE_RESULTS[@]+"${CHANGED_REFERENCE_RESULTS[@]}"}"; do
        case "$consumer" in
          bin/*.sh|bin/*.mjs|bin/*.d.mts|bin/*.ps1) ;;
          *) continue ;;
        esac
        [ "${consumer##*/}" = "$needle" ] && continue
        CHANGED_SUPPRESS_UNMAPPED=$((CHANGED_SUPPRESS_UNMAPPED + 1))
        if families_for_changed_path "$consumer"; then
          found=1
        fi
        CHANGED_SUPPRESS_UNMAPPED=$((CHANGED_SUPPRESS_UNMAPPED - 1))
      done
      BIN_FALLBACK_DEPTH=$((BIN_FALLBACK_DEPTH - 1))
    fi
    [ "$found" -eq 1 ]
    return
  fi

  if out=$(scripts_for_test_reference "$needle"); then
    printf '%s\n' "$out"
    found=1
  fi
  if [ "$BIN_FALLBACK_DEPTH" -lt 2 ]; then
    BIN_FALLBACK_DEPTH=$((BIN_FALLBACK_DEPTH + 1))
    while IFS= read -r consumer; do
      [ -n "$consumer" ] || continue
      while IFS= read -r entry; do
        case "$entry" in
          __unmapped__:*) ;;
          *)
            printf '%s\n' "$entry"
            found=1
            ;;
        esac
      done < <(families_for_changed_path "$consumer")
    done < <(bin_consumers_of "$needle")
    BIN_FALLBACK_DEPTH=$((BIN_FALLBACK_DEPTH - 1))
  fi
  [ "$found" -eq 1 ]
}

# Conservative path → family map. Over-selects rather than under-selects.
# Never expands to the complete suite.
families_for_changed_path() {
  local path=$1 fixture_ref
  if fm_test_catalog_maps "$path"; then
    case "$path" in
      tests/lib.sh|tests/*-helpers.sh|tests/*-fixture.sh|tests/fixtures.sh|tests/assets/*)
        # A curated mapping supplements, rather than replaces, fixture consumers.
        families_for_test_reference "${path##*/}" || true
        ;;
    esac
    return 0
  fi
  case "$path" in
    tests/*.test.sh)
      # A single test file change selects only that script via basename family
      # resolution in the caller; emit a marker family of __script__
      printf '%s\n' "__script__:${path##*/}"
      ;;
    .opencode/plugins/*|.pi/extensions/*)
      families_for_test_reference "${path##*/}" \
        || emit_unmapped_changed_path "$path"
      ;;
    tests/lib.sh|tests/*-helpers.sh|tests/*-fixture.sh|tests/fixtures.sh|tests/assets/*)
      families_for_test_reference "${path##*/}" \
        || emit_unmapped_changed_path "$path"
      ;;
    tests/fixtures/*/*)
      # A fixture belongs to whichever suite reads its directory, found by the
      # same reference scan used for shared helpers. Keyed on the directory
      # rather than the file so adding a fixture selects the same suite.
      # A removed fixture directory has no consuming suite left to select.
      fixture_ref=${path#tests/fixtures/}
      fixture_ref=${fixture_ref%%/*}
      if [ -d "tests/fixtures/$fixture_ref" ]; then
        families_for_test_reference "fixtures/$fixture_ref" \
          || emit_unmapped_changed_path "$path"
      fi
      ;;
    bin/*)
      # A deleted script has no consuming suite left to select, the same rule
      # the fixture case above applies. Refusing on its absent mapping would
      # make every retirement branch unable to select its changed tests.
      if [ -e "$path" ]; then
        families_for_unmapped_bin "$path" \
          || emit_unmapped_changed_path "$path"
      fi
      ;;
    tests/*)
      emit_unmapped_changed_path "$path"
      ;;
    README.md|LICENSE|assets/*|docs/*)
      ;;
    *)
      if [ -e "$path" ]; then
        families_for_test_reference "$path" \
          || emit_unmapped_changed_path "$path"
      else
        # A retired source path with no remaining test consumer cannot select
        # a runnable suite. Known source paths above retain their mappings,
        # and a still-referenced removal is found by the same reference scan.
        families_for_test_reference "$path" || true
      fi
      ;;
  esac
}

select_changed() {
  local base=$1 path entry fam script_name s f matched
  local changed_tmp changed_paths all_tests entries candidates
  local unmapped_path=
  local -a wanted_families=()
  local -a wanted_scripts=()

  if ! git -C "$ROOT" rev-parse --verify "$base" >/dev/null 2>&1; then
    die "changed-file base ref not found: $base (pass --base <ref>)"
  fi

  changed_tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-test-changed.XXXXXX") \
    || die "could not create changed-test selection workspace"
  changed_paths="$changed_tmp/paths"
  {
    git -C "$ROOT" diff --name-only "${base}...HEAD" 2>/dev/null
    git -C "$ROOT" diff --name-only HEAD 2>/dev/null
    git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null
  } >"$changed_paths"
  all_tests="$changed_tmp/all-tests"
  all_repo_tests >"$all_tests"
  CHANGED_REFERENCE_INDEX="$changed_tmp/references.tsv"
  if ! prepare_changed_reference_index \
    "$changed_paths" "$changed_tmp/patterns" "$CHANGED_REFERENCE_INDEX" "$all_tests"; then
    rm -rf "$changed_tmp"
    clear_changed_reference_lookup
    die "could not build changed-test reference index"
  fi

  entries="$changed_tmp/entries"
  : >"$entries"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    families_for_changed_path "$path" >>"$entries"
  done <"$changed_paths"

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      __script__:*)
        script_name=${entry#__script__:}
        wanted_scripts+=("$script_name")
        ;;
      __unmapped__:*)
        unmapped_path=${entry#__unmapped__:}
        break
        ;;
      *)
        wanted_families+=("$entry")
        ;;
    esac
  done <"$entries"

  if [ -n "$unmapped_path" ]; then
    rm -rf "$changed_tmp"
    clear_changed_reference_lookup
    die "no changed-test mapping for source path: $unmapped_path"
  fi

  # Dedup families
  local f seen_f
  local -a unique_families=()
  for f in "${wanted_families[@]+"${wanted_families[@]}"}"; do
    seen_f=0
    for u in "${unique_families[@]+"${unique_families[@]}"}"; do
      [ "$u" = "$f" ] && { seen_f=1; break; }
    done
    [ "$seen_f" -eq 0 ] && unique_families+=("$f")
  done

  candidates="$changed_tmp/candidates"
  : >"$candidates"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    fam=$(family_for_basename "${s##*/}")
    matched=0
    for f in "${unique_families[@]+"${unique_families[@]}"}"; do
      if [ "$fam" = "$f" ]; then
        matched=1
        break
      fi
    done
    [ "$matched" -eq 0 ] || printf '%s\n' "$s" >>"$candidates"
  done <"$all_tests"
  for script_name in "${wanted_scripts[@]+"${wanted_scripts[@]}"}"; do
    if [ -f "tests/$script_name" ]; then
      printf 'tests/%s\n' "$script_name" >>"$candidates"
    fi
  done
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    SCRIPTS+=("$s")
  done < <(LC_ALL=C sort -u "$candidates")

  rm -rf "$changed_tmp"
  clear_changed_reference_lookup

  if [ "${#SCRIPTS[@]}" -eq 0 ]; then
    log "no tests selected for changes vs $base (map is conservative; use --all for the complete suite)"
  fi
}

detect_gate_skip() {
  # True when the first non-empty output line is a skip: gate message.
  local file=$1 first
  first=$(awk 'NF { print; exit }' "$file" 2>/dev/null || true)
  case "$first" in
    skip:*) return 0 ;;
    *) return 1 ;;
  esac
}

# Echo the reason a gate skip gave, i.e. the first meaningful output line with
# its leading "skip:" removed. Tabs and stray whitespace are folded so the
# reason stays one field of the tab-separated record the JSON artifact is built
# from. Callers only use this once detect_gate_skip has already said yes.
gate_skip_reason() {
  local file=$1 first
  first=$(awk 'NF { print; exit }' "$file" 2>/dev/null || true)
  first=${first#skip:}
  printf '%s\n' "$first" | tr '\t' ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

# True when any output line contains "skip: <token>" (token may contain spaces).
detect_gate_skip_token() {
  local file=$1 token=$2
  [ -n "$token" ] || return 1
  grep -F -q "skip: $token" "$file" 2>/dev/null
}

apply_exclude_families() {
  local s fam keep ex
  local -a kept=()
  [ "${#EXCLUDE_FAMILIES[@]}" -gt 0 ] || return 0
  for s in "${SCRIPTS[@]+"${SCRIPTS[@]}"}"; do
    fam=$(family_for_basename "${s##*/}")
    keep=1
    for ex in "${EXCLUDE_FAMILIES[@]+"${EXCLUDE_FAMILIES[@]}"}"; do
      if [ "$fam" = "$ex" ]; then
        keep=0
        break
      fi
    done
    [ "$keep" -eq 1 ] && kept+=("$s")
  done
  SCRIPTS=("${kept[@]+"${kept[@]}"}")
}

write_json_artifact() {
  local out=$1
  local started=$2
  local finished=$3
  local run_id=$4
  local total=$5
  local failed=$6
  local skipped=$7
  local duration=$8
  local selection=$9
  local records_file=${10}
  local families_file=${11}

  if ! command -v python3 >/dev/null 2>&1; then
    die "--json requires python3 to emit a valid timing artifact"
  fi

  python3 - "$out" "$started" "$finished" "$run_id" "$total" "$failed" "$skipped" "$duration" "$selection" "$records_file" "$families_file" <<'PY'
import json, sys

out, started, finished, run_id, total, failed, skipped, duration, selection, records_file, families_file = sys.argv[1:]

scripts = []
with open(records_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        path, family, expected, exit_s, dur_s, gate, reason = line.split("\t")
        scripts.append({
            "path": path,
            "family": family,
            "expected_gate_skip": expected,
            "duration_ms": int(dur_s),
            "exit": int(exit_s),
            "gate_skip": gate == "true",
            "gate_skip_reason": reason,
        })

families = []
with open(families_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        name, count_s, dur_s, failed_s = line.split("\t")
        families.append({
            "name": name,
            "count": int(count_s),
            "duration_ms": int(dur_s),
            "failed": int(failed_s),
        })

doc = {
    "run_id": run_id,
    "started_at": started,
    "finished_at": finished,
    "selection": selection,
    "summary": {
        "total": int(total),
        "failed": int(failed),
        "skipped_gate": int(skipped),
        "duration_ms": int(duration),
    },
    "scripts": scripts,
    "families": families,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=all
      shift
      ;;
    --family)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      [ "$#" -gt 1 ] || die "--family requires a name"
      MODE=family
      FAMILY=$2
      shift 2
      ;;
    --family=*)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=family
      FAMILY=${1#--family=}
      shift
      ;;
    --lane)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      [ "$#" -gt 1 ] || die "--lane requires a name (see --list-lanes)"
      MODE=lane
      LANE=$2
      shift 2
      ;;
    --lane=*)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=lane
      LANE=${1#--lane=}
      shift
      ;;
    --proven-isolated)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=proven-isolated
      shift
      ;;
    --changed)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=changed
      shift
      ;;
    --base)
      [ "$#" -gt 1 ] || die "--base requires a git ref"
      BASE_REF=$2
      shift 2
      ;;
    --base=*)
      BASE_REF=${1#--base=}
      shift
      ;;
    --json)
      [ "$#" -gt 1 ] || die "--json requires a path"
      JSON_PATH=$2
      shift 2
      ;;
    --json=*)
      JSON_PATH=${1#--json=}
      shift
      ;;
    --jobs)
      [ "$#" -gt 1 ] || die "--jobs requires a positive integer"
      JOBS=$2
      JOBS_EXPLICIT=1
      shift 2
      ;;
    --jobs=*)
      JOBS=${1#--jobs=}
      JOBS_EXPLICIT=1
      shift
      ;;
    --max-wall-ms)
      [ "$#" -gt 1 ] || die "--max-wall-ms requires a positive integer"
      MAX_WALL_MS=$2
      shift 2
      ;;
    --max-wall-ms=*)
      MAX_WALL_MS=${1#--max-wall-ms=}
      shift
      ;;
    --per-script-timeout-secs)
      [ "$#" -gt 1 ] || die "--per-script-timeout-secs requires a whole number of seconds"
      PER_SCRIPT_TIMEOUT_SECS=$2
      shift 2
      ;;
    --per-script-timeout-secs=*)
      PER_SCRIPT_TIMEOUT_SECS=${1#--per-script-timeout-secs=}
      shift
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --list-scheduled)
      LIST_SCHEDULED=1
      shift
      ;;
    --list-families)
      LIST_FAMILIES=1
      shift
      ;;
    --list-concurrent-safe-families)
      LIST_CONCURRENT_SAFE_FAMILIES=1
      shift
      ;;
    --concurrent-safe-family-jobs-max)
      [ "$#" -gt 1 ] || die "--concurrent-safe-family-jobs-max requires a family name"
      concurrent_safe_family_jobs_max "$2"
      exit 0
      ;;
    --concurrent-safe-family-jobs-max=*)
      concurrent_safe_family_jobs_max "${1#--concurrent-safe-family-jobs-max=}"
      exit 0
      ;;
    --list-lanes)
      LIST_LANES=1
      shift
      ;;
    --check-coverage)
      CHECK_COVERAGE=1
      shift
      ;;
    --aggregate-json)
      [ "$#" -gt 1 ] || die "--aggregate-json requires an output path"
      AGGREGATE_OUT=$2
      shift 2
      # Remaining args after options will be collected as inputs below via MODE.
      # For aggregation we accept only input JSON paths as free args after this.
      MODE=aggregate
      ;;
    --exclude-family)
      [ "$#" -gt 1 ] || die "--exclude-family requires a name"
      EXCLUDE_FAMILIES+=("$2")
      shift 2
      ;;
    --exclude-family=*)
      EXCLUDE_FAMILIES+=("${1#--exclude-family=}")
      shift
      ;;
    --fail-on-gate-skip)
      [ "$#" -gt 1 ] || die "--fail-on-gate-skip requires a token (e.g. 'herdr not found')"
      FAIL_ON_GATE_SKIP=$2
      shift 2
      ;;
    --fail-on-gate-skip=*)
      FAIL_ON_GATE_SKIP=${1#--fail-on-gate-skip=}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        SCRIPTS+=("$1")
        shift
      done
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [ "${MODE:-}" = "aggregate" ]; then
        SCRIPTS+=("$1")
      elif [ -z "$MODE" ] || [ "$MODE" = scripts ]; then
        MODE=scripts
        SCRIPTS+=("$1")
      else
        die "script paths cannot be combined with --$MODE"
      fi
      shift
      ;;
  esac
done

if [ "$LIST_FAMILIES" -eq 1 ]; then
  list_known_families
  exit 0
fi

if [ "$LIST_CONCURRENT_SAFE_FAMILIES" -eq 1 ]; then
  list_concurrent_safe_families
  exit 0
fi

if [ "$LIST_LANES" -eq 1 ]; then
  list_known_lanes
  exit 0
fi

if [ "$CHECK_COVERAGE" -eq 1 ]; then
  run_coverage_guard
  exit $?
fi

if [ "${MODE:-}" = "aggregate" ]; then
  [ -n "$AGGREGATE_OUT" ] || die "--aggregate-json requires an output path"
  [ "${#SCRIPTS[@]}" -gt 0 ] || die "--aggregate-json requires at least one input timing JSON"
  for s in "${SCRIPTS[@]}"; do
    [ -f "$s" ] || die "aggregate input not found: $s"
  done
  aggregate_timing_json "$AGGREGATE_OUT" "${SCRIPTS[@]}"
  exit 0
fi

case "$JOBS" in
  ''|*[!0-9]*) die "--jobs must be a positive integer" ;;
esac
[ "$JOBS" -ge 1 ] || die "--jobs must be >= 1"
[ "$JOBS" -le "$JOBS_MAX" ] || die "--jobs is capped at $JOBS_MAX (got $JOBS)"

if [ -n "$MAX_WALL_MS" ]; then
  case "$MAX_WALL_MS" in
    ''|*[!0-9]*) die "--max-wall-ms requires a positive integer" ;;
  esac
  [ "$MAX_WALL_MS" -gt 0 ] || die "--max-wall-ms requires a positive integer"
fi

case "$PER_SCRIPT_TIMEOUT_SECS" in
  ''|*[!0-9]*) die "--per-script-timeout-secs requires a whole number of seconds (0 disables)" ;;
esac

# Refuse before any suite is selected or run. The inspection modes execute
# nothing: --list-families, --list-concurrent-safe-families, --list-lanes,
# --check-coverage, --concurrent-safe-family-jobs-max and --aggregate-json have
# already exited above, and --list/--list-scheduled print their selection and
# exit below. An unset MODE still falls through to the usage error, so a caller
# who named no selection mode is told that rather than this.
if [ -n "${MODE:-}" ] && [ "$LIST_ONLY" -eq 0 ] && [ "$LIST_SCHEDULED" -eq 0 ]; then
  refuse_primary_checkout_for_task
fi

case "${MODE:-}" in
  all)
    select_all
    SELECTION_DESC="all"
    ;;
  family)
    select_family "$FAMILY"
    SELECTION_DESC="family=$FAMILY"
    ;;
  lane)
    select_lane "$LANE"
    SELECTION_DESC="lane=$LANE"
    ;;
  proven-isolated)
    select_proven_isolated
    SELECTION_DESC="proven-isolated"
    ;;
  changed)
    select_changed "$BASE_REF"
    SELECTION_DESC="changed:base=$BASE_REF"
    ;;
  scripts)
    # Normalize and re-add through add_script for consistent paths.
    raw=("${SCRIPTS[@]+"${SCRIPTS[@]}"}")
    SCRIPTS=()
    for s in "${raw[@]}"; do
      add_script "$s"
    done
    SELECTION_DESC="scripts"
    ;;
  *)
    die "select with --all, --family <name>, --lane <name>, --proven-isolated, --changed, or one or more script paths (see --help)"
    ;;
esac

apply_exclude_families
if [ "${#EXCLUDE_FAMILIES[@]}" -gt 0 ]; then
  SELECTION_DESC="${SELECTION_DESC};exclude-family=$(IFS=,; printf '%s' "${EXCLUDE_FAMILIES[*]}")"
fi
if [ -n "$FAIL_ON_GATE_SKIP" ]; then
  SELECTION_DESC="${SELECTION_DESC};fail-on-gate-skip=$FAIL_ON_GATE_SKIP"
fi
if [ "$LIST_ONLY" -eq 1 ] || [ "$LIST_SCHEDULED" -eq 1 ]; then
  if [ "$LIST_SCHEDULED" -eq 1 ]; then
    case "$MODE:$LANE" in
      lane:portable-parallel-1|lane:portable-parallel-2)
        for s in "${SCRIPTS[@]+"${SCRIPTS[@]}"}"; do
          printf '%s\t%s\n' "$(portable_parallel_weight_for "$s")" "$s"
        done
        ;;
      *)
        printf '%s\n' "${SCRIPTS[@]+"${SCRIPTS[@]}"}" | portable_serial_weighted_paths
        ;;
    esac | LC_ALL=C sort -t"$(printf '\t')" -k1,1nr -k2,2 | cut -f2-
  else
    for s in "${SCRIPTS[@]+"${SCRIPTS[@]}"}"; do
      printf '%s\n' "$s"
    done
  fi
  exit 0
fi

# An empty selection is a clean result, not a no-op that falls through. Exiting
# here also keeps every array expansion below off the empty-array path: under
# `set -u`, bash 3.2 (the stock macOS shell) treats "${arr[@]}" on an empty
# array as an unbound-variable error, while bash 4.4+ makes it a harmless no-op.
# A contributor on stock macOS who changes only documentation must still get
# total=0 and exit 0 rather than a crash.
if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  log "nothing to run"
  empty_finished_ms=$(now_ms)
  empty_duration=$((empty_finished_ms - RUN_STARTED_MS))
  [ "$empty_duration" -ge 0 ] || empty_duration=0
  empty_rc=0
  printf 'FM_TEST_SUMMARY total=0 failed=0 skipped_gate=0 duration_ms=%s\n' "$empty_duration"
  # The budget covers the whole invocation, so a selection phase that outran it
  # still fails - reporting zero work is not the same as reporting no time.
  if [ -n "$MAX_WALL_MS" ]; then
    printf 'FM_TEST_BUDGET max_wall_ms=%s duration_ms=%s\n' "$MAX_WALL_MS" "$empty_duration"
    if [ "$empty_duration" -gt "$MAX_WALL_MS" ]; then
      log "wall-clock budget exceeded: ${empty_duration}ms > ${MAX_WALL_MS}ms for $SELECTION_DESC"
      empty_rc=1
    fi
  fi
  if [ -n "$JSON_PATH" ]; then
    empty_rec=$(mktemp)
    empty_fam=$(mktemp)
    : >"$empty_rec"
    : >"$empty_fam"
    empty_finished_iso=$(now_iso)
    mkdir -p "$(dirname "$JSON_PATH")"
    write_json_artifact "$JSON_PATH" "$RUN_STARTED_ISO" "$empty_finished_iso" \
      "fm-test-run-${RUN_STARTED_MS}-$$" 0 0 0 "$empty_duration" \
      "$SELECTION_DESC" "$empty_rec" "$empty_fam"
    rm -f "$empty_rec" "$empty_fam"
  fi
  exit "$empty_rc"
fi

# Verify selected scripts exist before starting.
for s in "${SCRIPTS[@]}"; do
  [ -f "$s" ] || die "test script not found: $s"
  [ -x "$s" ] || [ -r "$s" ] || die "test script not readable: $s"
done

# Plain --changed and a plain list of script paths both use the bounded
# representative-suite scheduler; numeric --jobs retains the strict all-script
# admission rule below. Naming scripts is how a local verification round asks
# for exactly those subjects, so it gets bounded concurrency rather than a
# serial chain of separate runs.
# The curated selections stay untouched: --lane composes CI shards whose serial
# lane must stay strictly serial, --family is what the required Herdr lane runs,
# and --all is a deliberate complete regression.
AUTO_CONCURRENCY=0
if { [ "$MODE" = changed ] || [ "$MODE" = scripts ]; } && [ "$JOBS_EXPLICIT" -eq 0 ]; then
  if [ "$MODE" = changed ] && [ "${#SCRIPTS[@]}" -gt 0 ] && [ "$PER_SCRIPT_TIMEOUT_SECS" -eq 0 ]; then
    PER_SCRIPT_TIMEOUT_SECS=$CHANGED_DEFAULT_TIMEOUT_SECS
    CHANGED_TIMEOUT_AUTOMATIC=1
  fi
  auto_admissible=0
  for s in "${SCRIPTS[@]}"; do
    automatic_concurrency_allowed "$s" && auto_admissible=$((auto_admissible + 1))
  done
  if [ "$auto_admissible" -gt 1 ]; then
    JOBS=$(cpu_count)
    [ "$JOBS" -le 4 ] || JOBS=4
    [ "$JOBS" -ge 1 ] || JOBS=1
    [ "$JOBS" -eq 1 ] || AUTO_CONCURRENCY=1
  fi
fi
if [ "$JOBS" -gt 1 ] || [ "$MODE" = changed ] || [ "$MODE" = scripts ]; then
  SELECTION_DESC="${SELECTION_DESC};jobs=$JOBS"
fi

# An explicit --jobs names a concurrency for exactly the selection given, so an
# unproven script in it is a refusal rather than something to schedule around.
if [ "$JOBS" -gt 1 ] && [ "$AUTO_CONCURRENCY" -eq 0 ]; then
  for s in "${SCRIPTS[@]}"; do
    if ! script_allows_concurrency "$s"; then
      die "--jobs $JOBS refused: $s is not in the proven-isolated set (see bin/fm-test-isolation-proof.sh --list) and its family has no recorded concurrent proof. Unproven stateful scripts stay serial."
    fi
    if ! is_proven_isolated_script "$s"; then
      family=$(family_for_basename "${s##*/}")
      family_jobs_max=$(concurrent_safe_family_jobs_max "$family")
      [ "$JOBS" -le "$family_jobs_max" ] \
        || die "--jobs $JOBS refused: family $family is proven only up to $family_jobs_max concurrent workers"
    fi
  done
fi

# Split the run into admitted concurrent phases and an automatic serial
# remainder.
# Individually proven scripts share one phase. Scripts admitted only by a family
# proof get a separate phase per family, because that proof establishes safety
# only among members of that family. Unproven scripts and measured
# platform-constrained scripts run after every concurrent phase, never beside
# another test.
CONCURRENT_SCRIPTS=()
SERIAL_TAIL_SCRIPTS=()
CONCURRENT_PHASE_BREAK=__fm_test_concurrent_phase_break__
if [ "$JOBS" -gt 1 ]; then
  SCHEDULE_TMP=$(mktemp "${TMPDIR:-/tmp}/fm-test-sched.XXXXXX")
  : >"$SCHEDULE_TMP"
  for s in "${SCRIPTS[@]}"; do
    if { [ "$AUTO_CONCURRENCY" -eq 1 ] && automatic_concurrency_allowed "$s"; } \
      || { [ "$AUTO_CONCURRENCY" -eq 0 ] && script_allows_concurrency "$s"; }; then
      if is_proven_isolated_script "$s"; then
        phase=0
      else
        family=$(family_for_basename "${s##*/}")
        phase=1
        while IFS= read -r admitted_family; do
          [ "$family" = "$admitted_family" ] && break
          phase=$((phase + 1))
        done < <(list_concurrent_safe_families)
      fi
      # Longest first within each isolation phase: workers are handed scripts
      # in order, so starting the longest last strands it at the tail.
      printf '%s\t%s\t%s\n' "$phase" "$(portable_serial_weight_for "$s")" "$s" >>"$SCHEDULE_TMP"
    else
      SERIAL_TAIL_SCRIPTS+=("$s")
    fi
  done
  previous_phase=
  while IFS=$'\t' read -r phase _weight s; do
    [ -n "$s" ] || continue
    if [ -n "$previous_phase" ] && [ "$phase" != "$previous_phase" ]; then
      CONCURRENT_SCRIPTS+=("$CONCURRENT_PHASE_BREAK")
    fi
    CONCURRENT_SCRIPTS+=("$s")
    previous_phase=$phase
  done < <(LC_ALL=C sort -t"$(printf '\t')" -k1,1n -k2,2nr -k3,3 "$SCHEDULE_TMP")
  rm -f "$SCHEDULE_TMP"
fi

if [ "$PER_SCRIPT_TIMEOUT_SECS" -gt 0 ]; then
  [ -r "$ROOT/bin/fm-timeout-lib.sh" ] || die "per-script timeout helper not found: bin/fm-timeout-lib.sh"
  # shellcheck source=bin/fm-timeout-lib.sh
  . "$ROOT/bin/fm-timeout-lib.sh"
fi

RUN_TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-test-run.XXXXXX")
RECORDS="$RUN_TMP/records.tsv"
FAMILIES_TSV="$RUN_TMP/families.tsv"
: >"$RECORDS"
declare -a WORKER_PIDS=()
declare -a WORKER_IDX=()
declare -a WORKER_SCRIPTS=()

# Invoked indirectly by the EXIT trap below.
# shellcheck disable=SC2329
cleanup_run() {
  rm -rf "$RUN_TMP"
}

trap cleanup_run EXIT

RUN_ID="fm-test-run-${RUN_STARTED_MS}-$$"
TOTAL=0
FAILED=0
SKIPPED_GATE=0
AGG_RC=0

# Family accumulators as TSV lines updated in-memory via temp files.
# family -> count, duration_ms, failed
family_bump() {
  local fam=$1 dur=$2 failed_delta=$3
  local line name count duration failed_count rest
  local found=0
  local tmp="$RUN_TMP/families.new"
  : >"$tmp"
  if [ -s "$FAMILIES_TSV" ]; then
    while IFS= read -r line; do
      name=${line%%$'\t'*}
      rest=${line#*$'\t'}
      count=${rest%%$'\t'*}
      rest=${rest#*$'\t'}
      duration=${rest%%$'\t'*}
      failed_count=${rest#*$'\t'}
      if [ "$name" = "$fam" ]; then
        count=$((count + 1))
        duration=$((duration + dur))
        failed_count=$((failed_count + failed_delta))
        found=1
      fi
      printf '%s\t%s\t%s\t%s\n' "$name" "$count" "$duration" "$failed_count" >>"$tmp"
    done <"$FAMILIES_TSV"
  fi
  if [ "$found" -eq 0 ]; then
    printf '%s\t%s\t%s\t%s\n' "$fam" 1 "$dur" "$failed_delta" >>"$tmp"
  fi
  mv "$tmp" "$FAMILIES_TSV"
}

record_script_result() {
  local script=$1 rc=$2 duration=$3 out=$4 end_iso=$5
  local base family expected gate_skip gate_reason fail_delta
  base=${script##*/}
  family=$(family_for_basename "$base")
  expected=$(expected_gate_skip_for_family "$family")

  if [ -n "$FAIL_ON_GATE_SKIP" ] && detect_gate_skip_token "$out" "$FAIL_ON_GATE_SKIP"; then
    log "required gate skip token seen in $script: skip: $FAIL_ON_GATE_SKIP"
    rc=1
  fi

  gate_skip=false
  gate_reason=
  if [ "$rc" -eq 0 ] && detect_gate_skip "$out"; then
    gate_skip=true
    gate_reason=$(gate_skip_reason "$out")
    SKIPPED_GATE=$((SKIPPED_GATE + 1))
    # A capability skip is the runner's only record of what this host could not
    # exercise, so name it rather than leaving a silent green.
    log "gate skip: $script: ${gate_reason:-<no reason given>}"
  fi

  printf 'FM_TEST_END %s %s exit=%s duration_ms=%s gate_skip=%s\n' \
    "$end_iso" "$script" "$rc" "$duration" "$gate_skip"

  fail_delta=0
  if [ "$rc" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    fail_delta=1
    AGG_RC=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$script" "$family" "$expected" "$rc" "$duration" "$gate_skip" "$gate_reason" >>"$RECORDS"
  family_bump "$family" "$duration" "$fail_delta"
  TOTAL=$((TOTAL + 1))
}

# Run <script>, capturing output to <out>. <stream> 1 also echoes it live.
# <id> only has to be unique within this run. When PER_SCRIPT_TIMEOUT_SECS is
# positive, a script that outruns it is terminated and reported as exit 124: a
# hung script must become a bounded failure rather than an unbounded suite,
# because an unbounded suite is what silently outruns its caller's budget.
run_script_bounded() {  # <script> <out> <stream> <id>
  local script=$1 out=$2 stream=$3 id=$4
  local rc timeout_secs=$PER_SCRIPT_TIMEOUT_SECS
  if [ "$CHANGED_TIMEOUT_AUTOMATIC" -eq 1 ]; then
    timeout_secs=$(automatic_changed_timeout_secs_for "$script")
  fi
  : "$id"
  set +e
  if [ "$stream" -eq 1 ]; then
    if [ "$timeout_secs" -gt 0 ]; then
      # Expansion is intentionally deferred to the child bash passed to -c.
      # shellcheck disable=SC2016
      fm_run_timed "$timeout_secs" bash -c \
        'bash "$1" 2>&1 | tee "$2"; exit "${PIPESTATUS[0]}"' _ "$script" "$out"
      rc=$?
    else
      bash "$script" 2>&1 | tee "$out"
      rc=${PIPESTATUS[0]}
    fi
  elif [ "$timeout_secs" -gt 0 ]; then
    fm_run_timed "$timeout_secs" bash "$script" >"$out" 2>&1
    rc=$?
  else
    bash "$script" >"$out" 2>&1
    rc=$?
  fi
  if [ "$timeout_secs" -gt 0 ] && [ "$rc" -eq 124 ]; then
    printf 'not ok - %s exceeded the per-script bound of %ss and was terminated\n' \
      "$script" "$timeout_secs" >>"$out"
    [ "$stream" -eq 1 ] && tail -1 "$out"
  fi
  return "$rc"
}

run_one_serial() {
  local script=$1
  local base family expected out begin_iso begin_ms end_ms end_iso duration rc
  base=${script##*/}
  family=$(family_for_basename "$base")
  expected=$(expected_gate_skip_for_family "$family")
  out="$RUN_TMP/out.$TOTAL"
  begin_iso=$(now_iso)
  begin_ms=$(now_ms)

  printf 'FM_TEST_BEGIN %s %s family=%s expected_gate_skip=%s\n' \
    "$begin_iso" "$script" "$family" "$expected"

  set +e
  # Stream live output while retaining a copy for gate-skip detection.
  run_script_bounded "$script" "$out" 1 "s$TOTAL"
  rc=$?
  set -e
  : "${rc:=1}"

  end_ms=$(now_ms)
  end_iso=$(now_iso)
  duration=$((end_ms - begin_ms))
  if [ "$duration" -lt 0 ]; then
    duration=0
  fi
  record_script_result "$script" "$rc" "$duration" "$out" "$end_iso"
}

if [ "$JOBS" -eq 1 ]; then
  for script in "${SCRIPTS[@]}"; do
    run_one_serial "$script"
  done
else
  # Bounded concurrent execution for admitted scripts. Each worker gets a
  # private mode-0700 TMPDIR so mktemp roots cannot collide. Native Windows
  # Bash layers report synthetic POSIX modes, so retain chmod there but enforce
  # its observed mode only where the host reports real POSIX permissions.
  # Retries are never used as a green strategy.
  worker_n=0
  active_workers=0

  wait_one_job_worker() {
    local slot=$1 pid idx work script rc duration mode out end_iso
    pid=${WORKER_PIDS[$slot]}
    idx=${WORKER_IDX[$slot]}
    script=${WORKER_SCRIPTS[$slot]}
    set +e
    wait "$pid"
    set -e
    unset 'WORKER_PIDS[slot]'
    unset 'WORKER_IDX[slot]'
    unset 'WORKER_SCRIPTS[slot]'
    active_workers=$((active_workers - 1))
    work="$RUN_TMP/w$idx"
    rc=$(cat "$work/exit" 2>/dev/null || echo 1)
    duration=$(cat "$work/duration_ms" 2>/dev/null || echo 0)
    out="$work/output"
    end_iso=$(now_iso)
    # Replay captured output after the worker finishes so markers stay ordered.
    if [ -s "$out" ]; then
      cat "$out"
    fi
    if ! worker_directory_private "$work"; then
      mode=$(stat -c %a "$work" 2>/dev/null || /usr/bin/stat -f %Lp "$work" 2>/dev/null || echo unknown)
      log "isolation failure: worker root is not private (reported mode $mode; $work)"
      rc=1
    fi
    record_script_result "$script" "$rc" "$duration" "$out" "$end_iso"
  }

  worker_pid_is_running() {
    local want=$1 running inventory="$RUN_TMP/running-pids"
    # Keep `jobs` in this shell. A process substitution runs it in a subshell
    # without this shell's job table on Bash 3.2/5.x, falsely reporting every
    # worker complete and making the scheduler wait for the oldest PID.
    jobs -r -p >"$inventory"
    while IFS= read -r running; do
      [ "$running" = "$want" ] && return 0
    done <"$inventory"
    return 1
  }

  wait_one_completed_job_worker() {
    local slot work
    while :; do
      for slot in "${!WORKER_PIDS[@]}"; do
        work="$RUN_TMP/w${WORKER_IDX[$slot]}"
        if [ -f "$work/exit" ] || ! worker_pid_is_running "${WORKER_PIDS[$slot]}"; then
          wait_one_job_worker "$slot"
          return
        fi
      done
      sleep 0.01
    done
  }

  for script in "${CONCURRENT_SCRIPTS[@]+"${CONCURRENT_SCRIPTS[@]}"}"; do
    if [ "$script" = "$CONCURRENT_PHASE_BREAK" ]; then
      while [ "$active_workers" -gt 0 ]; do
        wait_one_completed_job_worker
      done
      continue
    fi
    while [ "$active_workers" -ge "$JOBS" ]; do
      wait_one_completed_job_worker
    done
    worker_n=$((worker_n + 1))
    work="$RUN_TMP/w$worker_n"
    mkdir -p "$work/tmp"
    chmod 0700 "$work" "$work/tmp" || die "could not chmod 0700 worker root $work"
    base=${script##*/}
    family=$(family_for_basename "$base")
    expected=$(expected_gate_skip_for_family "$family")
    printf 'FM_TEST_BEGIN %s %s family=%s expected_gate_skip=%s\n' \
      "$(now_iso)" "$script" "$family" "$expected"
    (
      trap - EXIT HUP INT TERM
      set +e
      export TMPDIR="$work/tmp"
      export TMP="$work/tmp"
      unset FM_HOME FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_ROOT_OVERRIDE \
        FM_PROJECTS_OVERRIDE FM_CONFIG_OVERRIDE FM_BACKEND 2>/dev/null || true
      cd "$ROOT" || exit 1
      begin_ms=$(now_ms)
      set +e
      run_script_bounded "$script" "$work/output" 0 "w$worker_n"
      rc=$?
      set -e
      end_ms=$(now_ms)
      duration=$((end_ms - begin_ms))
      if [ "$duration" -lt 0 ]; then
        duration=0
      fi
      printf '%s\n' "$duration" >"$work/duration_ms"
      printf '%s\n' "$rc" >"$work/exit"
      exit 0
    ) &
    worker_pid=$!
    WORKER_PIDS[worker_n]=$worker_pid
    WORKER_IDX[worker_n]=$worker_n
    WORKER_SCRIPTS[worker_n]=$script
    active_workers=$((active_workers + 1))
  done
  while [ "$active_workers" -gt 0 ]; do
    wait_one_completed_job_worker
  done
  # Unproven remainder, after every concurrent worker has finished.
  for script in "${SERIAL_TAIL_SCRIPTS[@]+"${SERIAL_TAIL_SCRIPTS[@]}"}"; do
    run_one_serial "$script"
  done
fi

RUN_FINISHED_ISO=$(now_iso)
RUN_FINISHED_MS=$(now_ms)
RUN_DURATION=$((RUN_FINISHED_MS - RUN_STARTED_MS))
if [ "$RUN_DURATION" -lt 0 ]; then
  RUN_DURATION=0
fi

printf 'FM_TEST_SUMMARY total=%s failed=%s skipped_gate=%s duration_ms=%s\n' \
  "$TOTAL" "$FAILED" "$SKIPPED_GATE" "$RUN_DURATION"

if [ -s "$FAMILIES_TSV" ]; then
  # Stable family summary order by name.
  sort -t$'\t' -k1,1 "$FAMILIES_TSV" | while IFS=$'\t' read -r name count duration failed_count; do
    printf 'FM_TEST_SUMMARY_FAMILY family=%s count=%s duration_ms=%s failed=%s\n' \
      "$name" "$count" "$duration" "$failed_count"
  done
fi

# Slowest scripts (top 15) from records.
if [ -s "$RECORDS" ]; then
  rank=1
  sort -t$'\t' -k5,5nr "$RECORDS" | head -n 15 | while IFS=$'\t' read -r path _family _expected _rc duration _gate; do
    printf 'FM_TEST_SLOWEST rank=%s script=%s duration_ms=%s\n' \
      "$rank" "$path" "$duration"
    rank=$((rank + 1))
  done
fi

if [ -n "$JSON_PATH" ]; then
  mkdir -p "$(dirname "$JSON_PATH")"
  # Families file may be unsorted; write_json reads as-is (deterministic sort in python).
  if [ -s "$FAMILIES_TSV" ]; then
    sort -t$'\t' -k1,1 "$FAMILIES_TSV" -o "$FAMILIES_TSV"
  else
    : >"$FAMILIES_TSV"
  fi
  set +e
  write_json_artifact "$JSON_PATH" \
    "$RUN_STARTED_ISO" "$RUN_FINISHED_ISO" "$RUN_ID" \
    "$TOTAL" "$FAILED" "$SKIPPED_GATE" "$RUN_DURATION" \
    "$SELECTION_DESC" "$RECORDS" "$FAMILIES_TSV"
  json_rc=$?
  set -e
  if [ "$json_rc" -eq 0 ]; then
    log "wrote timing artifact: $JSON_PATH"
  else
    log "timing artifact finalization failed: $JSON_PATH"
    AGG_RC=1
  fi
fi

if [ -n "$MAX_WALL_MS" ]; then
  printf 'FM_TEST_BUDGET max_wall_ms=%s duration_ms=%s\n' "$MAX_WALL_MS" "$RUN_DURATION"
  if [ "$RUN_DURATION" -gt "$MAX_WALL_MS" ]; then
    log "wall-clock budget exceeded: ${RUN_DURATION}ms > ${MAX_WALL_MS}ms for $SELECTION_DESC"
    AGG_RC=1
  fi
fi

exit "$AGG_RC"

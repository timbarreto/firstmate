#!/usr/bin/env bash
# Task-scoped paired busy-event evidence, not a production benchmark runner.
# Derived from the frozen windows-workflow-baseline/run.sh fixture builder.
# Usage: bash run.sh BASE_CODE_ROOT CANDIDATE_CODE_ROOT NEW_OUTPUT_DIR
# WF_WARMUPS=3 WF_SAMPLES=20; WF_TRACE=1 is one separate attribution pair.
# WF_ONLY selects a named smoke scenario; only complete 3/20 batches qualify.
# Setup, fixture reset, assertions, and cleanup stay outside operation timers.
set -eu
BASE=$(cd "$1" && pwd)
CANDIDATE=$(cd "$2" && pwd)
[ ! -e "$3" ] || { printf 'Use a new output directory: %s\n' "$3" >&2; exit 2; }
mkdir -p "$3"
OUT=$(cd "$3" && pwd)
ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUN=$(mktemp -d "$OUT/fixture.XXXXXX")
export TMPDIR="$RUN/tmp" HOME="$RUN/user-home"
mkdir -p "$TMPDIR" "$HOME" "$RUN/unused-home/state"
export USERPROFILE
USERPROFILE=$(cygpath -w "$HOME")
for key in ${!FM_@} ${!TASKS_AXI_@}; do unset "$key"; done
unset CLAUDECODE PI_CODING_AGENT FM_PI_HARNESS GROK_AGENT COPILOT_CLI \
  COPILOT_LOADER_PID COPILOT_AGENT_SESSION_ID HERDR_ENV HERDR_PANE_ID \
  HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SESSION HERDR_SOCKET_PATH TMUX BASH_ENV
export FM_HOME="$RUN/unused-home" FM_ROOT_OVERRIDE="$BASE" FM_BACKEND=tmux
export FM_TEST_SKIP_ORPHAN_REAP=1 FM_LIVE=0
. "$BASE/tests/lib.sh"
. "$BASE/tests/harness-helpers.sh"
cleanup_comparison() {
  fm_test_cleanup
  rm -rf -- "$RUN"
}
trap cleanup_comparison EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Reuse the baseline's real arm + public adapter renderer. Both versions share
# each harness's state path; per-operation resets are performed by measure.mjs.
for harness in pi copilot; do
  home="$RUN/$harness"
  mkdir -p "$home/state" "$home/config" "$home/data"
  gen=$("$BASE/bin/fm-busy-event.sh" arm "$home/state" task)
  native_state=$(cygpath -m "$home/state")
  for version in base candidate; do
    code=$BASE
    [ "$version" != candidate ] || code=$CANDIDATE
    native_code=$(cygpath -m "$code")
    suffix=json
    [ "$harness" != pi ] || suffix=ts
    bash -c '
      . "$1/bin/fm-harness-lib.sh" || exit $?
      fm_harness_owned_wiring "$2" render "$1" "$3" task "$4" "$3/task.turn-ended"
    ' _ "$native_code" "$harness" "$native_state" "$gen" > "$home/$version.$suffix"
  done
  mkdir -p "$OUT/generated/$harness"
  cp "$home/base.$suffix" "$home/candidate.$suffix" "$OUT/generated/$harness/"
done
export WF_FIXTURE_ROOT
WF_FIXTURE_ROOT=$(cygpath -m "$RUN")
node "$ASSETS/measure.mjs" "$(cygpath -m "$BASE")" "$(cygpath -m "$CANDIDATE")" "$(cygpath -m "$OUT")"

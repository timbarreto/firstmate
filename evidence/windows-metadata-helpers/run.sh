#!/usr/bin/env bash
# Task-scoped paired reporting evidence, derived from the frozen baseline packet:
# https://github.com/timbarreto/firstmate/tree/82fe66d0f349e520c8bd91617e49934f0b7bb1bb/evidence/windows-workflow-baseline
# Usage: bash run.sh BASE_CODE_ROOT CANDIDATE_CODE_ROOT NEW_OUTPUT_DIR
# Use sibling code roots with equal-length paths to avoid a source-path bias.
# WF_WARMUPS=3 WF_SAMPLES=20; WF_ONLY limits smoke checks to named scenarios.
# WF_TRACE=1 records one separate attribution pair, never qualification timings.
# Preparation, verification, and cleanup remain outside the operation timers.
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
  HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SESSION HERDR_SOCKET_PATH TMUX
export FM_HOME="$RUN/unused-home" FM_ROOT_OVERRIDE="$BASE" FM_BACKEND=tmux
export FM_TEST_SKIP_ORPHAN_REAP=1 FM_LIVE=0
# Use the same existing fixture writer and isolation setup as the baseline.
. "$BASE/tests/lib.sh"
cleanup_comparison() {
  fm_test_cleanup
  rm -rf -- "$RUN"
}
trap cleanup_comparison EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for shape in empty small; do
  home="$RUN/$shape"
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects"
  printf 'manual\n' > "$home/config/backlog-backend"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  if [ "$shape" = small ]; then
    for i in 1 2 3; do
      harness=copilot
      [ "$i" != 2 ] || harness=pi
      fm_write_meta "$home/state/task-$i.meta" \
        'kind=ship' "harness=$harness" 'mode=direct-PR' "spawn_gen=gen-$i" \
        "worktree=$home/projects/absent-$i" 'project=literal="data"' \
        "pr=https://github.com/example/repo/pull/$i"
      printf 'needs-decision [key=choice]: preserve "quoted" notes\nworking: unrelated progress\n' \
        > "$home/state/task-$i.status"
    done
  fi
done
export WF_FIXTURE_ROOT
WF_FIXTURE_ROOT=$(cygpath -m "$RUN")
node "$ASSETS/measure.mjs" "$(cygpath -m "$BASE")" "$(cygpath -m "$CANDIDATE")" "$(cygpath -m "$OUT")"

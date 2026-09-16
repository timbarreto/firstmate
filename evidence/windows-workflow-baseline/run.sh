#!/usr/bin/env bash
# Throwaway, task-scoped baseline fixture preparation, not a production benchmark runner.
# Usage: bash evidence/windows-workflow-baseline/run.sh CODE_ROOT OUTPUT_DIR FAMILY
# FAMILY: reporting | startup | copilot | pi | relaunch
# WF_SAMPLES=20 WF_WARMUPS=3; WF_ONLY limits a smoke run to one named scenario.
# Fixture construction and destruction happen outside measure.mjs's operation timers.
set -u
CODE=$(cd "$1" && pwd) || exit 1
mkdir -p "$2" || exit 1
OUT=$(cd "$2" && pwd) || exit 1
FAMILY=${3:?select a family}
ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
RUN=$(mktemp -d "$OUT/fixture.XXXXXX") || exit 1
export TMPDIR="$RUN/tmp" HOME="$RUN/user-home"
mkdir -p "$TMPDIR" "$HOME" "$RUN/unused-home/state" || exit 1
export USERPROFILE
USERPROFILE=$(cygpath -w "$HOME")
# Never inherit another home's state, a worker marker, a live backend, or a backlog override.
for key in ${!FM_@} ${!TASKS_AXI_@}; do unset "$key"; done
unset CLAUDECODE PI_CODING_AGENT FM_PI_HARNESS GROK_AGENT COPILOT_CLI \
  COPILOT_LOADER_PID COPILOT_AGENT_SESSION_ID HERDR_ENV HERDR_PANE_ID \
  HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SESSION HERDR_SOCKET_PATH TMUX
export FM_HOME="$RUN/unused-home" FM_ROOT_OVERRIDE="$CODE" FM_BACKEND=tmux
export FM_TEST_SKIP_ORPHAN_REAP=1 FM_LIVE=0
. "$CODE/tests/lib.sh" || exit 1
# Load the existing suite's fixture functions, not its registered test walk.
fm_test_run_cases() { :; }
TASK_TMPS=()
cleanup_baseline() {
  local path
  for path in "${TASK_TMPS[@]:-}"; do
    case "$path" in /tmp/fm-wfwin-*) rm -rf -- "$path" ;; esac
  done
  fm_test_cleanup
  rm -rf -- "$RUN"
}

case "$FAMILY" in
  reporting)
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
    printf 'needs-decision [key=choice]: choose the release\n' > "$RUN/routine.status"
    for ((i=0; i<200; i++)); do
      printf 'working: progress %s; prose mentions blocked: and resolved: but is not a decision\n' "$i" \
        >> "$RUN/routine.status"
    done
    ;;
  startup)
    . "$CODE/tests/fm-session-start.test.sh" >/dev/null || exit 1
    for harness in pi copilot; do
      for shape in empty small; do
        rec=$(new_world "$harness-$shape") || exit 1
        IFS='|' read -r root home fakebin <<< "$rec"
        make_fake_toolchain "$fakebin"
        make_fake_ps_harness "$fakebin" "$harness"
        fm_fake_exit0 "$fakebin" copilot pi
        printf 'manual\n' > "$home/config/backlog-backend"
        printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
        if [ "$shape" = small ]; then
          for i in 1 2 3; do
            fm_write_meta "$home/state/task-$i.meta" \
              'kind=ship' "harness=$harness" 'mode=direct-PR' "spawn_gen=gen-$i" \
              "worktree=$home/projects/absent-$i" 'project=fixture'
            printf 'note: synthetic context\nworking: fixture history\n' > "$home/state/task-$i.status"
          done
        fi
        printf '%s|%s|%s|%s\n' "$harness-$shape" "$root" "$home" "$fakebin" >> "$RUN/startup-worlds"
      done
    done
    export WF_FIXTURE_PARENT_PID=$$ WF_STARTUP_BASE_PATH="$BASE_PATH"
    ;;
  copilot)
    . "$CODE/tests/fm-copilot-harness.test.sh" >/dev/null || exit 1
    for state in healthy repair; do
      dir="$RUN/$state"
      make_fakebin "$dir" >/dev/null
      install_primary_fixture "$dir"
      cp "$CODE/bin/fm-ghcp-hook.ps1" "$CODE/bin/fm-windows-git-bash.ps1" "$dir/bin/"
      : > "$dir/state/task.meta"
    done
    ;;
  pi)
    . "$CODE/tests/harness-helpers.sh" || exit 1
    . "$CODE/bin/fm-harness-lib.sh" || exit 1
    mkdir -p "$RUN/pi/state" "$RUN/pi/config" "$RUN/pi/data"
    gen=$("$CODE/bin/fm-busy-event.sh" arm "$RUN/pi/state" task) || exit 1
    native_code=$(cygpath -m "$CODE")
    native_state=$(cygpath -m "$RUN/pi/state")
    fm_harness_owned_wiring pi render "$native_code" "$native_state" task "$gen" \
      "$native_state/task.turn-ended" > "$RUN/pi/generated.ts" || exit 1
    ;;
  relaunch)
    . "$CODE/tests/fm-control-relaunch.test.sh" >/dev/null || exit 1
    for harness in copilot pi; do
      id="wfwin-$$-$harness"
      dir=$(new_case "$id" "$id") || exit 1
      add_ship_task "$dir" "$id" "$harness"
      fm_fake_exit0 "$dir/fakebin" copilot pi
      printf '%s' "$harness" > "$dir/fake/command"
      printf '%s' "$harness" > "$dir/fake/becomes"
      mkdir -p "$dir/user-home" "$dir/home/config"
      printf 'manual\n' > "$dir/home/config/backlog-backend"
      printf '%s|%s|%s\n' "$harness" "$id" "$dir" >> "$RUN/relaunch-worlds"
    done
    ;;
  *) printf 'Unknown family: %s\n' "$FAMILY" >&2; exit 2 ;;
esac
trap cleanup_baseline EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export WF_FIXTURE_ROOT
WF_FIXTURE_ROOT=$(cygpath -m "$RUN")
node "$ASSETS/measure.mjs" "$FAMILY" "$(cygpath -m "$CODE")" "$(cygpath -m "$OUT")"
exit $?

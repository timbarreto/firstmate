#!/usr/bin/env bash
# Wait for a fixture-owned child after shutdown. The caller owns failure reporting.
# fm_remote_job_wait_fixture_child <pid> <seconds> <phase> <stdout> <stderr>
fm_remote_job_wait_fixture_child() {
  local pid=$1 seconds=$2 phase=$3 stdout=$4 stderr=$5 started=$SECONDS file
  printf 'remote-job-fixture: waiting for %s shutdown (pid=%s, bound=%ss)\n' \
    "$phase" "$pid" "$seconds" >&2
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$((SECONDS - started))" -ge "$seconds" ]; then
      printf 'remote-job-fixture: %s did not stop within %ss (pid=%s)\n' "$phase" "$seconds" "$pid" >&2
      printf 'remote-job-fixture: Bash %s\n' "$BASH_VERSION" >&2
      if ! ps -o pid=,ppid=,stat=,wchan=,args= -p "$pid" >&2; then
        ps -f -p "$pid" >&2 || printf 'remote-job-fixture: process snapshot unavailable\n' >&2
      fi
      for file in "$stdout" "$stderr"; do
        printf 'remote-job-fixture: last output from %s\n' "$file" >&2
        if [ -f "$file" ]; then tail -n 20 -- "$file" >&2; fi
      done
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.05
  done
  wait "$pid" 2>/dev/null || true
}

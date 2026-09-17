# Separate attribution runs only. Never enabled for the latency samples.
if [ -n "${WF_TRACE_LOG:-}" ]; then
  exec 9>> "$WF_TRACE_LOG"
  printf 'WFBOOT|%s|%s\n' "$BASHPID" "$0" >&9
  BASH_XTRACEFD=9
  PS4='WFTRACE|${BASHPID}|${BASH_SUBSHELL}|${BASH_SOURCE[0]:-command}|${LINENO}| '
  export PS4
  set -x
fi

#!/usr/bin/env bash
# Shared session-lock harness identity.
#
# ONE owner of the "which verified-harness process holds this home's session
# lock, and does the current process descend from that same harness?" decision.
# bin/fm-lock.sh uses it to acquire and inspect state/.lock;
# bin/fm-claude-stop-autoarm.sh uses it to prove a Stop hook fires inside the
# lock-owning primary session before it may arm or rewake.
# This file is sourced by scripts and has no side effects on source.

# Cursor process identity is NOT expressible as a command-name pattern and is
# deliberately not added to the tables below: Cursor's installed names are
# cursor-agent and the far-too-generic legacy alias `agent`, and it runs as a
# bundled node script. bin/fm-cursor-lib.sh is the fleet's single owner of that
# decision, so this file delegates to it rather than widening the name match.
_FM_SESSION_LOCK_LIB_DIR=$(dirname -- "${BASH_SOURCE[0]}")
# shellcheck source=bin/fm-cursor-lib.sh
. "$_FM_SESSION_LOCK_LIB_DIR/fm-cursor-lib.sh"
# shellcheck source=bin/fm-platform-process-lib.sh
. "$_FM_SESSION_LOCK_LIB_DIR/fm-platform-process-lib.sh" || return 1
# shellcheck source=bin/fm-harness-lib.sh
. "$_FM_SESSION_LOCK_LIB_DIR/fm-harness-lib.sh" || return 2
unset _FM_SESSION_LOCK_LIB_DIR

fm_session_process_comm() {  # <pid>
  fm_platform_process_comm "$@"
}

fm_session_process_args() {  # <pid>
  fm_platform_process_args "$@"
}

fm_session_process_ppid() {  # <pid>
  fm_platform_process_ppid "$@"
}

# Compatibility names; the adapter owns marker verification and its PID cache.
fm_copilot_windows_pid_matches() {  # <native-windows-pid>
  fm_harness_identify copilot native-pid "$@"
}

fm_copilot_loader_pid() {
  fm_harness_identify copilot loader
}

# True when the process described by command name $1 and full argument string $2
# is a verified harness. Sets FM_HARNESS_IS_CLAUDE for the ancestry walk.
#
# Evidence, in order:
#   1. the basename of the reported command name, against FM_HARNESS_RE.
#   2. an exact harness component in that command path or in argv[0]. Both are
#      needed because the two platforms report different things: macOS reports
#      argv[0] in `ps -o comm=`, while procps on Linux reports the kernel exec
#      name and ignores argv[0] entirely, so a version-named Claude Code binary
#      is identified by its install path on macOS and by argv[0] on Linux.
#   3. a bare interpreter (node, python) running a harness script path.
#   4. Cursor's own structural identity, owned by bin/fm-cursor-lib.sh.
FM_HARNESS_IS_CLAUDE=0
fm_harness_process_matches() {  # <comm> <args>
  local comm=$1 args=$2 base argv0 name
  FM_HARNESS_IS_CLAUDE=0
  base=$(basename -- "$comm")
  if printf '%s' "$base" | grep -qE "$FM_HARNESS_RE"; then
    case "$base" in *claude*) FM_HARNESS_IS_CLAUDE=1 ;; esac
    return 0
  fi
  argv0=${args%% *}
  if name=$(fm_harness_path_name "$comm") || name=$(fm_harness_path_name "$argv0"); then
    case "$name" in claude) FM_HARNESS_IS_CLAUDE=1 ;; esac
    return 0
  fi
  # Bare interpreter (e.g. node): match the harness name in its script path.
  case "$comm" in
    *node*|*python*)
      if printf '%s' "$args" | grep -qE "$FM_HARNESS_RE"; then
        case "$args" in *claude*) FM_HARNESS_IS_CLAUDE=1 ;; esac
        return 0
      fi
      ;;
  esac
  # Cursor: its own owner decides, from Cursor's name or versioned install tree
  # in the command path or argv[0]. Without this a Cursor primary can never
  # locate its own harness in the ancestry, so every session start refuses the
  # fleet lock as read-only and the park can never arm.
  fm_cursor_process_matches "$comm" "$args" "$argv0" && return 0
  return 1
}

# The lock format is a numeric PID shared with existing POSIX/Copilot callers.
# MSYS and Windows can assign that number to different live harnesses. Refuse
# ownership in that ambiguous case; never let a native lookup claim a different
# MSYS session (or vice versa). The subshell preserves the caller's Claude flag.
_fm_harness_pid_namespace_unambiguous() (
  local pid=$1 native_mode=$2 proc_root=${FM_PROC_ROOT_OVERRIDE:-/proc} winpid row other_pid comm args rc
  [ -r "$proc_root/$pid/winpid" ] || return 0
  fm_platform_windows_process_supported || return 0
  winpid=$(<"$proc_root/$pid/winpid")
  case "$winpid" in ''|*[!0-9]*|0|1) return 1 ;; esac
  [ "$winpid" != "$pid" ] || return 0
  if [ "$native_mode" -eq 1 ]; then
    comm=$(fm_session_process_comm "$pid") || return 1
    args=$(fm_session_process_args "$pid")
  elif row=$(fm_platform_windows_process_info "$pid"); then
    IFS=$'\t' read -r other_pid comm args <<< "$row"
    [ "$other_pid" = "$pid" ] && [ -n "$comm" ] || return 1
  else
    rc=$?
    [ "$rc" -eq 1 ]
    return
  fi
  ! fm_harness_process_matches "$comm" "$args"
)

# Claude's Windows hook/tool launcher may exit before its child runs, so even
# the native parent chain can be gone. Claude supplies CLAUDE_PID as a session
# handoff (verified by tests/fm-claude-session-lock-live-e2e.test.sh). Use it only
# after ancestry finds no harness, only with Claude's session markers, and only
# after a fresh native lookup proves that PID still names Claude. Never trust a
# bare environment PID, reinterpret it as MSYS, or accept a different harness.
fm_claude_windows_session_pid() {
  local pid=${CLAUDE_PID:-} session=${CLAUDE_CODE_SESSION_ID:-} row native_pid comm args
  [ "${CLAUDECODE:-}" = 1 ] || return 1
  case "$pid" in ''|*[!0-9]*|0|1) return 1 ;; esac
  [[ "$session" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 1
  row=$(fm_platform_windows_process_info "$pid") || return 1
  IFS=$'\t' read -r native_pid comm args <<< "$row"
  [ "$native_pid" = "$pid" ] && [ -n "$comm" ] || return 1
  fm_harness_process_matches "$comm" "$args" && [ "$FM_HARNESS_IS_CLAUDE" -eq 1 ] || return 1
  _fm_harness_pid_namespace_unambiguous "$pid" 1 || return 2
  printf '%s\n' "$pid"
}

# Walk the current process ancestry (up to 16 hops) and print this session's
# contiguous verified-harness ancestry, innermost pid first.
#
# The walk climbs freely until the first harness match, because the caller is
# normally an ordinary shell several levels below its session. After that first
# match it stops at the first non-harness ancestor, so it can never cross a gap
# into an unrelated harness further up the real process tree - for example the
# live session that launched a test as its own subprocess.
#
# For every harness except Claude the innermost match is the session, which is
# where e.g. Pi's shared signed-wrapper ancestry actually holds the lock: a
# "pi-signed" launcher can be the direct parent of the inner "pi" engine pid that
# owns the lock, and the wrapper pid above it is not that owner. Claude Code
# instead runs hooks several levels below the session inside its own nested
# worker chain (hook shell -> claude bg-spare -> claude bg-pty-host -> claude ->
# claude), with no non-harness process between them. Which pid in that run is the
# session cannot be read off the ancestry at all, so the whole contiguous run is
# reported and the callers below decide what they need from it.
# On MSYS/Cygwin the visible tree can end at PPID 1 below a native Windows
# parent. Cross that edge once using the platform's native snapshot, keeping
# native PIDs in their own lookup path rather than feeding them to POSIX ps.
fm_harness_ancestry_pids() {
  local pid=$$ comm args parent row native_rows='' native_mode=0 rc extending=0 printed=0
  if pid=$(fm_copilot_loader_pid 2>/dev/null); then
    printf '%s\n' "$pid"
    return 0
  fi
  pid=$$
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    if [ "$native_mode" -eq 0 ]; then
      if comm=$(fm_session_process_comm "$pid"); then
        args=$(fm_session_process_args "$pid")
      else
        # Some MSYS versions expose winpid but not the POSIX status/ps fields.
        if native_rows=$(fm_platform_windows_parent_processes "$pid"); then
          native_mode=1
        else
          rc=$?
          [ "$rc" -eq 1 ] || return 2
          break
        fi
      fi
    fi
    if [ "$native_mode" -eq 1 ]; then
      [ -n "$native_rows" ] || break
      row=${native_rows%%$'\n'*}
      case "$native_rows" in
        *$'\n'*) native_rows=${native_rows#*$'\n'} ;;
        *) native_rows='' ;;
      esac
      IFS=$'\t' read -r pid comm args <<< "$row"
      case "$pid" in ''|*[!0-9]*|0|1) return 2 ;; esac
      [ -n "$comm" ] || return 2
    fi
    if fm_harness_process_matches "$comm" "$args"; then
      _fm_harness_pid_namespace_unambiguous "$pid" "$native_mode" || return 2
      printf '%s\n' "$pid"
      printed=1
      [ "$FM_HARNESS_IS_CLAUDE" -eq 1 ] || break
      extending=1
    elif [ "$extending" -eq 1 ]; then
      break
    fi
    if [ "$native_mode" -eq 0 ]; then
      parent=$(fm_session_process_ppid "$pid")
      if [ -n "$parent" ] && [ "$parent" -gt 1 ] 2>/dev/null; then
        pid=$parent
      elif native_rows=$(fm_platform_windows_parent_processes "$pid"); then
        native_mode=1
      else
        rc=$?
        [ "$rc" -eq 1 ] || return 2
        break
      fi
    fi
  done
  if [ "$printed" -eq 1 ]; then
    return 0
  fi
  fm_claude_windows_session_pid
}

# Print the one pid that identifies this session when the session lock is being
# WRITTEN: the outermost pid of the contiguous run. That is the pid that lives as
# long as the session - a Claude worker several levels in is reaped when its hook
# returns, and a lock naming it would look stale moments later while the session
# is still running. Every non-Claude harness reports a single pid, so this is its
# innermost match unchanged.
fm_harness_ancestry_pid() {
  local pids pid outermost=''
  pids=$(fm_harness_ancestry_pids) || return 1
  while IFS= read -r pid; do
    [ -n "$pid" ] && outermost=$pid
  done <<EOF
$pids
EOF
  [ -n "$outermost" ] || return 1
  printf '%s\n' "$outermost"
}

# True if $1 is a live process that looks like a verified harness.
# Return 1 for dead/non-harness, 2 when native facts cannot be verified. A caller
# reclaiming a lock must not confuse a failed query with evidence of death.
fm_harness_pid_alive() {
  local pid=$1 comm args row native_pid rc
  case "$pid" in ''|*[!0-9]*|0|1) return 1 ;; esac
  if kill -0 "$pid" 2>/dev/null; then
    comm=$(fm_session_process_comm "$pid") || comm=''
    args=$(fm_session_process_args "$pid")
    if [ -n "$comm" ] && fm_harness_process_matches "$comm" "$args"; then
      return 0
    fi
  elif fm_copilot_windows_pid_matches "$pid"; then
    return 0
  fi
  if row=$(fm_platform_windows_process_info "$pid"); then
    IFS=$'\t' read -r native_pid comm args <<< "$row"
    [ "$native_pid" = "$pid" ] && [ -n "$comm" ] || return 2
    fm_harness_process_matches "$comm" "$args"
  else
    rc=$?
    return "$rc"
  fi
}

# True when state dir $1 holds a session lock whose pid is one of this session's
# verified harness PIDs (live ancestry or the Windows handoff above): this script
# runs inside the session that owns the home. Membership matters because the
# lock owner sits at an unknown depth in a contiguous Claude run - it is the
# outermost pid when the hook fires inside the session's own nested worker chain,
# and an inner pid when a harness-named daemon parents the session. A missing
# lock, a malformed lock, a lock held by a harness outside this ancestry, or an
# ancestry that cannot be resolved all fail closed.
fm_session_lock_owned_by_self() {
  local state=$1 lock_pid pids pid
  lock_pid=$(cat "$state/.lock" 2>/dev/null || true)
  case "$lock_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  pids=$(fm_harness_ancestry_pids) || return 1
  while IFS= read -r pid; do
    [ "$pid" = "$lock_pid" ] && return 0
  done <<EOF
$pids
EOF
  return 1
}

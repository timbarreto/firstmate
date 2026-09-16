#!/usr/bin/env bash
# Nonblocking agentStop backstop for a GitHub Copilot CLI primary.
#
# Normal Copilot supervision runs bin/fm-watch-arm.sh as one harness-tracked
# asynchronous shell task.
# This hook never runs or waits for that task itself.
# It only blocks the stop long enough to tell the model to start the missing
# asynchronous task, with a bounded continuation ledger below Copilot's own
# eight-block override.
set -u
[ "${COPILOT_CLI:-}" = 1 ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
GRACE=${FM_GUARD_GRACE:-300}
CONTINUATION_FILE="$STATE/.turnend-copilot-continuations"
CONTINUATION_LOCK="$STATE/.turnend-copilot-continuations.lock"
LOOP_CEILING=${FM_COPILOT_TURNEND_LOOP_CEILING:-7}
LOCK_ATTEMPTS=${FM_COPILOT_LOCK_ATTEMPTS:-50}
CONTINUATION_LOCK_HELD=0

case "$LOOP_CEILING" in ''|*[!0-9]*|0) LOOP_CEILING=7 ;; esac
case "$LOCK_ATTEMPTS" in ''|*[!0-9]*|0) LOCK_ATTEMPTS=50 ;; esac

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  if [ "$CONTINUATION_LOCK_HELD" = 1 ]; then
    if declare -F fm_lock_release_fast >/dev/null 2>&1; then
      fm_lock_release_fast "$CONTINUATION_LOCK" || true
    else
      fm_lock_release "$CONTINUATION_LOCK" || true
    fi
    CONTINUATION_LOCK_HELD=0
  fi
}
trap cleanup EXIT

# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"

PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

STOP_FIELDS=$(printf '%s' "$PAYLOAD" | jq -er '
  if type != "object" or (.stop_hook_active | type) != "boolean"
    or (.cursor_version | type) == "string"
    or (has("stopHookActive") and (.stopHookActive | type) != "boolean") then error("stop payload")
  else (if (.sessionId | type) == "string" then .sessionId
    elif (.session_id | type) == "string" then .session_id else error("sessionId") end) as $id
    | if ($id | test("^[A-Za-z0-9._-]+$")) then [$id,(.stop_hook_active | tostring)] | @tsv
      else error("sessionId") end
  end
' 2>/dev/null) || exit 0
IFS=$'\t' read -r SESSION_ID STOP_HOOK_ACTIVE <<< "$STOP_FIELDS"
case "$SESSION_ID" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
# The current event, not an inherited marker, supplies session identity. The
# loader/native process is still independently verified before any mutation.
export COPILOT_AGENT_SESSION_ID="$SESSION_ID"

fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0
[ -e "$STATE/.afk" ] && exit 0
# The predicate below is read-only in Copilot mode. Verify session ownership
# once, late and under the continuation lock, before ANY ledger/parent write.

lock_acquire_bounded() {
  local attempt=0
  while [ "$attempt" -lt "$LOCK_ATTEMPTS" ]; do
    if declare -F fm_lock_try_acquire_fast >/dev/null 2>&1; then
      fm_lock_try_acquire_fast "$CONTINUATION_LOCK" && return 0
    else
      fm_lock_try_acquire "$CONTINUATION_LOCK" && return 0
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -lt "$LOCK_ATTEMPTS" ] && sleep 0.1
  done
  return 1
}

continuation_read() {
  local session='' count=''
  LOOP_COUNT=0
  if [ "$STOP_HOOK_ACTIVE" != true ]; then
    rm -f "$CONTINUATION_FILE" 2>/dev/null || true
    return 0
  fi
  {
    IFS= read -r session || true
    IFS= read -r count || true
  } 2>/dev/null < "$CONTINUATION_FILE" || true
  case "$session" in session=*) session=${session#session=} ;; *) session= ;; esac
  case "$count" in count=*) count=${count#count=} ;; *) count= ;; esac
  case "$count" in ''|*[!0-9]*) count=1 ;; esac
  if [ "$session" = "$SESSION_ID" ]; then
    LOOP_COUNT=$count
  else
    LOOP_COUNT=1
  fi
}

continuation_write() {
  local count=$1 tmp="$CONTINUATION_FILE.tmp.$$" status=0
  printf 'session=%s\ncount=%s\n' "$SESSION_ID" "$count" > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$CONTINUATION_FILE" 2>/dev/null \
    || status=1
  rm -f "$tmp" 2>/dev/null || true
  return "$status"
}

mark_parent_busy() {
  local parent_state=${FM_COPILOT_PARENT_STATE:-}
  local parent_id=${FM_COPILOT_PARENT_TASK_ID:-}
  local parent_gen=${FM_COPILOT_PARENT_BUSY_GEN:-}
  if [ -z "$parent_state$parent_id$parent_gen" ]; then
    return 0
  fi
  [ -n "$parent_state" ] && [ -n "$parent_id" ] && [ -n "$parent_gen" ] || return 1
  "$SCRIPT_DIR/fm-busy-event.sh" apply "$parent_state" "$parent_id" busy \
    --gen "$parent_gen" --source copilot-hook --event stop-continuation \
    >/dev/null 2>&1
}

emit_block() {
  local body=$1 count=$2 encoded response
  # shellcheck source=bin/fm-operational-input.sh
  . "$SCRIPT_DIR/fm-operational-input.sh"
  fm_operational_input_encode turn-end-guard "$body" encoded || exit 0
  response=$(jq -n --arg m "$encoded" '{decision:"block",reason:$m}' 2>/dev/null) || exit 0

  # The caller owns the one late-verified read/modify/write transaction.
  if ! mark_parent_busy || ! continuation_write "$count"; then
    exit 0
  fi
  printf '%s\n' "$response" || true
  exit 0
}

GUARD_RC=0
REASON=
fm_supervision_stop_probe "$STATE" "$SCRIPT_DIR/fm-watch.sh" "$GRACE" "$FM_HOME" || GUARD_RC=$?
# A healthy continuation leaves its counter unchanged. A healthy fresh turn
# with no counter has nothing to reset either. These read-only no-ops need no
# mutation lock or ownership query; an existing counter still resets under the
# one late ownership-checked transaction below.
if [ "$GUARD_RC" -eq 0 ]; then
  if [ "$STOP_HOOK_ACTIVE" = true ] \
     || { [ ! -e "$CONTINUATION_FILE" ] && [ ! -L "$CONTINUATION_FILE" ]; }; then
    exit 0
  fi
fi
if [ "$GUARD_RC" -eq 2 ]; then
  REASON=$(fm_supervision_stop_diagnostic "$SCRIPT_DIR" "$STATE" "$CONFIG" 0 copilot) || exit 0
fi
# Read-only healthy continuations need no harness-ownership dependency tree.
# Load it only when the counter or parent record may actually change.
# shellcheck source=bin/fm-session-lock-lib.sh
. "$SCRIPT_DIR/fm-session-lock-lib.sh" || exit 2
lock_acquire_bounded || exit 0
CONTINUATION_LOCK_HELD=1
fm_session_lock_owned_by_self "$STATE" || exit 0
[ -e "$STATE/.afk" ] && exit 0
continuation_read
[ "$GUARD_RC" -eq 2 ] || exit 0

if [ "$LOOP_COUNT" -ge "$LOOP_CEILING" ]; then
  exit 0
fi
if [ "$LOOP_COUNT" -eq "$((LOOP_CEILING - 1))" ]; then
  emit_block "FIRSTMATE SUPERVISION FOLLOW-UP CEILING REACHED - this session has taken $LOOP_COUNT consecutive hook-driven turns without a captain message, so automatic recovery prompts stop here to bound the loop. Queued events remain durable. Run bin/fm-wake-drain.sh, handle them, and run its exact WAKE_ACK_REQUIRED command. A real captain prompt resets the sequence." "$LOOP_CEILING"
fi

[ -n "$REASON" ] || REASON='tasks are in flight but no tracked asynchronous watcher task is active'
emit_block "$REASON" "$((LOOP_COUNT + 1))"

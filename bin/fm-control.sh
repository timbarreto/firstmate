#!/usr/bin/env bash
# fm-control.sh - the CONTROL PLANE for a firstmate-owned agent: allowlisted
# lifecycle verbs addressed to an exact task id.
#
# Usage: fm-control.sh <task-id> inspect [--recover-from <home-local-prior-meta>]
#        fm-control.sh <task-id> interrupt
#        fm-control.sh <task-id> exit
#        fm-control.sh <task-id> relaunch [--harness <name>] [--model <name>]
#                                         [--effort <level>]
#                                         (--note <text> | --note-file <path>)
#                                         [--recover-from <home-local-prior-meta>
#                                          --approve-recovery <inspection-digest>]
#        fm-control.sh --batch-relaunch <task-id>... (--note <text> | --note-file <path>)
#                                         [--harness <name>] [--model <name>]
#                                         [--effort <level>]
#
# --batch-relaunch runs each selected task through the same single-task control
# plane, serially, exactly once. Task ids precede the shared options; the note
# must apply to every selected task. Duplicate/invalid ids and per-task recovery
# approvals are refused before any action. Each task keeps its own recorded
# profile unless a shared override is explicit, and every task prints a
# batch-relaunch result with its original exit code. Ordinary failed/refused or
# unconfirmed results do not skip later tasks. The aggregate is 1 if any task
# failed/refused, otherwise 3 if any launch is unconfirmed, otherwise 0.
# Interruption stops the batch rather than authorizing further lifecycle work.
# Reconcile each unsuccessful task separately; batch execution never retries an
# uncertain launch or transfers an inspection approval to another task.
#
# inspect is read-only, including while another lifecycle action is active.
# With --recover-from it returns a native Windows/Herdr recovery plan for a
# positively missing recorded endpoint and a prior Copilot ship record in this
# task's state/data directory. It verifies the project, exact fm/<task> branch,
# endpoint cwd, both task-held Treehouse leases, and native PID birth identities.
# The recorded copy must be unused; both copies and leases are preserved.
# After explicit approval of that exact plan, relaunch may use its digest to
# rebind the record and run the existing checkpoint/exit/launch transaction.
# The digest is a stale-plan guard, not permission inferred from a record or a
# terminal title. Current PR, steering, delivery, and other durable fields stay.
# Receipts and both prior records live under state/<id>.control-recovery/<digest>.
# Replaying an applied plan never launches or stops another agent: completed
# plans report already-complete; incomplete plans require inspection.
#
# Why this exists, and how it differs from fm-send.sh. bin/fm-send.sh is the
# DATA plane: conversational text for the agent to read, always routing-marked
# for a kind=secondmate target so the reply returns through the status path.
# That marking is right for a message and wrong for a lifecycle command - a
# marked "/quit" arrives as ordinary chat the agent reasons ABOUT instead of
# executing. This script is the control plane: semantic process control with a
# closed verb list, per-harness mechanics owned by an executable adapter
# (bin/fm-control-lib.sh) rather than improvised in agent prose, and a verified
# postcondition for every action. There is deliberately NO arbitrary-text and
# NO generic raw-key entry point here; fm-send remains the only way to send an
# agent something to read.
#
#   interrupt  Deliver the harness's verified interrupt sequence. The agent
#              keeps running. Postcondition: delivery succeeded, the endpoint
#              still exists, and the agent is still alive where the backend can
#              classify that. Cancellation is confirmed only from an adapter-
#              owned acknowledgement and otherwise reported unconfirmed. Busy
#              state is never rewritten as proof of the action.
#   exit       Stop the agent, preserving its terminal endpoint, worktree, and
#              every uncommitted change. Interrupts first when the task reads
#              busy, then submits the harness's exit command. Postcondition:
#              the backend's recovery-grade classifier reports the agent gone.
#              Already-stopped is success (idempotent). An endpoint that reads
#              `missing` is put through the control plane's per-backend absence
#              proof (fm_control_endpoint_absence_verdict) before anything is
#              claimed about it, because `missing` also covers an endpoint that
#              is merely unreachable from this seat. That proof exists only on
#              HERDR, whose reads are scoped to the session the record names:
#              proven gone reports `endpoint-gone` rather than
#              `already-stopped`, because the endpoint this verb normally
#              preserves did not survive; a pane that turns out to be there and
#              idle is the ordinary `already-stopped`; one whose agent is back
#              takes the ordinary interrupt-then-exit path. A tmux `missing`
#              always REFUSES: a task record carries no socket identity for its
#              endpoint, so this verb cannot tell a destroyed window from one on
#              a tmux server it cannot address, and it will not claim a stop it
#              cannot see.
#   relaunch   Transactionally replace the running agent with a new one, in the
#              SAME worktree - and the same endpoint whenever that endpoint
#              still exists - on the same or a newly chosen
#              harness/model/effort - so switching harness is one ordinary use
#              of this verb. When the recorded endpoint is instead proven gone -
#              a Herdr pane or workspace destroyed in churn - the launch owner
#              re-creates one in that worktree, in the herdr session the record
#              names, and the task's record rebinds to it; that is how a task
#              whose terminal was destroyed is reclaimed by the home that owns
#              it, rather than being stranded with a parked approval nobody can
#              answer. Reclaim is HERDR-ONLY for the reason `exit` gives above:
#              a tmux `missing` cannot be proven absent from a task record, so
#              it refuses.
#              An explicit `default` model or effort clears that
#              axis for the replacement. With no explicit axis, a secondmate
#              re-resolves its durable config/secondmate-harness pin (harness
#              plus its optional model and effort tokens) exactly as any other
#              respawn does, while a ship or scout keeps the exact adapter
#              already recorded for it.
#              A prefixed raw-command basename cannot reconstruct its launch
#              command, so relaunch requires an explicit --harness for it.
#              --note is required for a ship or scout, whose replacement
#              inherits the local copy but none of the conversation; a
#              secondmate reconciles its own home's records at startup, so its
#              standing charter is never rewritten.
#              Records a durable checkpoint and that note, exits the old agent,
#              then delegates the launch to its single owner,
#              bin/fm-spawn.sh --relaunch. A failure before publication keeps
#              the prior durable record in place and reports the concrete
#              state; it never leaves a half-transitioned task claiming to be
#              running.
#              A positively missing Herdr ship/scout endpoint may be recreated
#              in its recorded session after project, exact fm/<task> branch,
#              unused task-held Treehouse lease, and competing-record checks.
#              The original copy is never replaced. A server-restored shell is
#              reused; a live or unreadable restored endpoint refuses recovery.
#              Lifecycle, metadata, task-set, and session locks serialize the
#              repair. The journal records recreating and recreate_from before
#              creation; an unconfirmed create with the old binding still in
#              place requires inspection rather than another create attempt.
#              Once published, the fresh exact endpoint binding survives a
#              failed launch and is reused by the ordinary relaunch path.
#              Confirmation accepts either a verified live agent or a complete
#              ship/scout terminal report bound to the new spawn generation
#              (fm-classify-lib.sh owns launch_status=). A reported outcome is
#              not a claim that the agent remains alive.
#              Successful delivery with unreadable confirmation returns 3 and
#              retains phase=launch-unconfirmed, never failed:launching. A
#              repeated relaunch reconciles that same generation without
#              delivering another note or launching another worker; inspect
#              also returns its current launch_report. Positive death without
#              a current report, and failed launch delivery, still return 1.
#
# Teardown and discard are NOT verbs here and never will be. `exit` stops an
# agent and preserves everything else; removing a worktree, killing an
# endpoint, or discarding work stays with bin/fm-teardown.sh, which owns the
# landed-work test.
#
# `resume` is not a verb: it is not deterministic across the verified adapters
# (bin/fm-control-lib.sh's header owns that reasoning). `relaunch` covers the
# same need for every adapter because the brief on disk, not a harness-private
# session, is the durable instruction.
#
# Targeting is EXACT: only a bare task id with a state/<id>.meta record in
# THIS home is accepted, and the record must pass the shared endpoint-identity
# validation (bin/fm-backend.sh's fm_backend_validate_task_endpoint). A legacy
# fm-<id> label, an explicit session:window endpoint, and a bare window name
# are all refused - a lifecycle command delivered to the wrong endpoint is far
# worse than a loud refusal.
#
# A remotely placed secondmate is refused by name: its agent runs on another
# host, so no postcondition this plane verifies could be read for it here.
#
# Fail-closed boundaries:
#   - An unverified harness, or a harness whose control mechanics are unknown,
#     is refused rather than guessed at.
#   - A backend that cannot deliver the harness's interrupt key is refused
#     (Orca's terminal API has no Escape).
#   - `exit` and `relaunch` require a backend with a recovery-grade agent-state
#     classifier (tmux, herdr), because without one the "the agent stopped"
#     postcondition cannot be proven. zellij, orca, and cmux are refused rather
#     than reported as successful blind.
#   - An ambiguous or unreadable endpoint state refuses; only a positively
#     classified state acts.
#   - A composer that visibly holds pending text refuses before an exit command
#     is typed, so existing text is preserved instead of being concatenated.
#
# Environment knobs (all bounded waits, seconds):
#   FM_CONTROL_POLL              poll interval for postcondition waits (0.5)
#   FM_CONTROL_SETTLE_WAIT       adapter acknowledgement wait after interrupt (5)
#   FM_CONTROL_EXIT_WAIT         positive elapsed-time alive->dead bound (30)
#   FM_CONTROL_LAUNCH_WAIT       positive elapsed-time launch confirmation bound (90)
#       Each postcondition bound includes its status queries and poll sleeps.
#       An unfinished query at expiry is unreadable, never proof of agent exit
#       or successful launch. Relaunch then performs one local report read,
#       without another endpoint query. Preparation and delivery are separate.
#   FM_CONTROL_EXIT_RETRIES      Enter retries for the exit command (3)
# Exit codes: 0 verified action/outcome; 1 refused or failed; 2 usage;
# 3 launch delivered but its outcome remains unconfirmed.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"

usage() {
  # The whole leading comment block, ending at the first non-comment line.
  sed -n '2,${/^#/!q;p;}' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# shellcheck source=bin/fm-gate-refuse-lib.sh
. "$SCRIPT_DIR/fm-gate-refuse-lib.sh"
# Fail closed before any fleet mutation: a no-mistakes gate agent must never
# drive a crewmate's lifecycle (see bin/fm-gate-refuse-lib.sh).
fm_refuse_if_gate_agent

if [ -z "${FM_HOME+x}" ] || [ -z "${FM_HOME:-}" ]; then
  echo "error: FM_HOME is not set; fm-control refuses to resolve a task without an explicit firstmate home" >&2
  exit 1
fi
# shellcheck source=bin/fm-path-lib.sh
. "$SCRIPT_DIR/fm-path-lib.sh" || exit 1
fm_path_normalize_context || exit 1
[ -d "$FM_HOME" ] || {
  echo "error: FM_HOME '$FM_HOME' is not a directory" >&2
  exit 1
}
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
[ -d "$STATE" ] || {
  echo "error: state dir '$STATE' is missing; fm-control cannot resolve tasks for FM_HOME '$FM_HOME'" >&2
  exit 1
}

# shellcheck source=bin/fm-backend.sh
. "$SCRIPT_DIR/fm-backend.sh"
# shellcheck source=bin/fm-busy-lib.sh
. "$SCRIPT_DIR/fm-busy-lib.sh" || exit 2
# shellcheck source=bin/fm-classify-lib.sh
. "$SCRIPT_DIR/fm-classify-lib.sh"
# shellcheck source=bin/fm-control-lib.sh
. "$SCRIPT_DIR/fm-control-lib.sh" || exit 2
# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-timeout-lib.sh
. "$SCRIPT_DIR/fm-timeout-lib.sh"

POLL=${FM_CONTROL_POLL:-0.5}
SETTLE_WAIT=${FM_CONTROL_SETTLE_WAIT:-5}
EXIT_WAIT=${FM_CONTROL_EXIT_WAIT:-30}
LAUNCH_WAIT=${FM_CONTROL_LAUNCH_WAIT:-90}
EXIT_RETRIES=${FM_CONTROL_EXIT_RETRIES:-3}

die() {  # <message>
  echo "error: $1" >&2
  exit 1
}

CONTROL_LOCK=
CONTROL_LOCK_HELD=0
RECOVERY_META_LOCK=
RECOVERY_META_LOCK_HELD=0
RECOVERY_SET_LOCK=
RECOVERY_SET_LOCK_HELD=0
RECOVERY_SESSION_LOCK=
RECOVERY_SESSION_LOCK_HELD=0
RELAUNCH_ACTIVE=0
RELAUNCH_PHASE=start

control_cleanup() {
  local status=$?
  if [ "$RELAUNCH_ACTIVE" = 1 ] \
     && declare -F relaunch_rollback >/dev/null 2>&1; then
    relaunch_rollback || true
  fi
  if [ "$RECOVERY_META_LOCK_HELD" = 1 ]; then
    fm_lock_release "$RECOVERY_META_LOCK" || true
    RECOVERY_META_LOCK_HELD=0
  fi
  if [ "$RECOVERY_SET_LOCK_HELD" = 1 ]; then
    fm_lock_release "$RECOVERY_SET_LOCK" || true
    RECOVERY_SET_LOCK_HELD=0
  fi
  if [ "$RECOVERY_SESSION_LOCK_HELD" = 1 ]; then
    fm_lock_release "$RECOVERY_SESSION_LOCK" || true
    RECOVERY_SESSION_LOCK_HELD=0
  fi
  if declare -F fm_control_recovery_cleanup >/dev/null 2>&1; then
    fm_control_recovery_cleanup || true
  fi
  if [ "$CONTROL_LOCK_HELD" = 1 ]; then
    CONTROL_LOCK_HELD=0
    fm_lock_release "$CONTROL_LOCK" || true
  fi
  if declare -F fm_lease_guard_release >/dev/null 2>&1; then
    fm_lease_guard_release || true
  fi
  return "$status"
}

# --- argument parsing -------------------------------------------------------

BATCH_RELAUNCH=0
BATCH_TASKS=()
RAW_ID=${1:-}
VERB=${2:-}
if [ "$RAW_ID" = --batch-relaunch ]; then
  BATCH_RELAUNCH=1
  VERB=relaunch
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in --*) break ;; esac
    BATCH_TASKS+=("$1")
    shift
  done
  [ "${#BATCH_TASKS[@]}" -gt 0 ] || { usage >&2; exit 2; }
else
  [ -n "$RAW_ID" ] && [ -n "$VERB" ] || { usage >&2; exit 2; }
  shift 2
fi

if ! fm_control_verb_allowed "$VERB"; then
  {
    if [ "$VERB" = resume ]; then
      echo "error: 'resume' is not a control verb: resuming an exited agent is not deterministic across the verified adapters (codex and grok need a session id printed at exit, opencode continues the most recent session for the cwd, and claude, copilot, pi, pi-signed, and kimi have no verified pane-resume contract). Use 'relaunch', which carries the brief plus a progress note into a fresh agent on any adapter."
    else
      echo "error: '$VERB' is not a control verb"
    fi
    echo "allowed verbs:"
    fm_control_verbs | sed 's/^/  /'
  } >&2
  exit 2
fi

NEW_HARNESS=
NEW_MODEL=
NEW_EFFORT=
HARNESS_SET=0
MODEL_SET=0
EFFORT_SET=0
NOTE=
NOTE_SET=0
RECOVER_FROM=
APPROVE_RECOVERY=
RECOVER_SET=0
APPROVE_SET=0
control_want_value=
for control_arg in "$@"; do
  if [ -n "$control_want_value" ]; then
    case "$control_arg" in
      --*) die "--$control_want_value requires a value" ;;
    esac
    case "$control_want_value" in
      harness) NEW_HARNESS=$control_arg; HARNESS_SET=1 ;;
      model) NEW_MODEL=$control_arg; MODEL_SET=1 ;;
      effort) NEW_EFFORT=$control_arg; EFFORT_SET=1 ;;
      note) NOTE=$control_arg; NOTE_SET=1 ;;
      recover_from) RECOVER_FROM=$control_arg; RECOVER_SET=1 ;;
      approve_recovery) APPROVE_RECOVERY=$control_arg; APPROVE_SET=1 ;;
      note_file)
        [ -f "$control_arg" ] || die "--note-file '$control_arg' is not a readable file"
        NOTE=$(cat "$control_arg")
        NOTE_SET=1
        ;;
    esac
    control_want_value=
    continue
  fi
  case "$control_arg" in
    --harness) control_want_value=harness ;;
    --harness=*) NEW_HARNESS=${control_arg#--harness=}; HARNESS_SET=1 ;;
    --model) control_want_value=model ;;
    --model=*) NEW_MODEL=${control_arg#--model=}; MODEL_SET=1 ;;
    --effort) control_want_value=effort ;;
    --effort=*) NEW_EFFORT=${control_arg#--effort=}; EFFORT_SET=1 ;;
    --note) control_want_value=note ;;
    --note=*) NOTE=${control_arg#--note=}; NOTE_SET=1 ;;
    --recover-from) control_want_value=recover_from ;;
    --recover-from=*) RECOVER_FROM=${control_arg#--recover-from=}; RECOVER_SET=1 ;;
    --approve-recovery) control_want_value=approve_recovery ;;
    --approve-recovery=*) APPROVE_RECOVERY=${control_arg#--approve-recovery=}; APPROVE_SET=1 ;;
    --note-file) control_want_value=note_file ;;
    --note-file=*)
      [ -f "${control_arg#--note-file=}" ] || die "--note-file '${control_arg#--note-file=}' is not a readable file"
      NOTE=$(cat "${control_arg#--note-file=}")
      NOTE_SET=1
      ;;
    *) die "unexpected argument '$control_arg'" ;;
  esac
done
if [ -n "$control_want_value" ]; then
  [ "$control_want_value" = note_file ] && die "--note-file requires a value"
  die "--$control_want_value requires a value"
fi

if [ "$VERB" != relaunch ]; then
  [ "$HARNESS_SET" = 0 ] && [ "$MODEL_SET" = 0 ] && [ "$EFFORT_SET" = 0 ] && [ "$NOTE_SET" = 0 ] \
    || die "--harness, --model, --effort, and --note apply to 'relaunch' only"
fi
[ "$RECOVER_SET" = 0 ] || [ -n "$RECOVER_FROM" ] || die "--recover-from requires a non-empty path"
[ "$APPROVE_SET" = 0 ] || [ -n "$APPROVE_RECOVERY" ] || die "--approve-recovery requires a non-empty digest"
if [ -n "$RECOVER_FROM" ]; then
  case "$VERB" in inspect|relaunch) ;; *) die "--recover-from applies to inspect or relaunch only" ;; esac
  if [ "$VERB" = relaunch ]; then
    [ -n "$APPROVE_RECOVERY" ] || die "recovery requires the explicitly approved inspection digest"
    [ "$HARNESS_SET" = 0 ] && [ "$MODEL_SET" = 0 ] && [ "$EFFORT_SET" = 0 ] \
      || die "record recovery cannot also change the worker profile"
  fi
fi
if [ -n "$APPROVE_RECOVERY" ]; then
  [ "$VERB" = relaunch ] && [ -n "$RECOVER_FROM" ] || die "--approve-recovery requires relaunch --recover-from"
  case "$APPROVE_RECOVERY" in *[!0-9a-f]*) die "invalid recovery approval digest" ;; esac
  [ "${#APPROVE_RECOVERY}" = 64 ] || die "invalid recovery approval digest"
fi
[ "$HARNESS_SET" = 0 ] || [ -n "$NEW_HARNESS" ] || die "--harness requires a non-empty value"
[ "$MODEL_SET" = 0 ] || [ -n "$NEW_MODEL" ] || die "--model requires a non-empty value"
[ "$EFFORT_SET" = 0 ] || [ -n "$NEW_EFFORT" ] || die "--effort requires a non-empty value"
case "$NEW_EFFORT" in
  ''|default|low|medium|high|xhigh|max|ultra) ;;
  *) die "--effort must be one of default, low, medium, high, xhigh, max, ultra" ;;
esac

# Batch mode owns only iteration and outcome aggregation. Every actual action
# re-enters this executable with one exact task so all fresh observations,
# authority checks, locks, checkpoints and rollback remain single-task owned.
if [ "$BATCH_RELAUNCH" = 1 ]; then
  [ "$RECOVER_SET" = 0 ] && [ "$APPROVE_SET" = 0 ] \
    || die "record recovery is single-task only; each inspection approval binds one task"
  [ "$NOTE_SET" = 1 ] && [ -n "$NOTE" ] \
    || die "--batch-relaunch requires a non-empty note applicable to every selected task"
  batch_seen=' '
  for batch_task in "${BATCH_TASKS[@]}"; do
    fm_task_id_creation_valid "$batch_task" || die "'$batch_task' is not a valid task id"
    case "$batch_seen" in
      *" $batch_task "*) die "duplicate batch task '$batch_task'" ;;
    esac
    batch_seen="$batch_seen$batch_task "
  done
  batch_args=("--note=$NOTE")
  [ "$HARNESS_SET" = 0 ] || batch_args+=("--harness=$NEW_HARNESS")
  [ "$MODEL_SET" = 0 ] || batch_args+=("--model=$NEW_MODEL")
  [ "$EFFORT_SET" = 0 ] || batch_args+=("--effort=$NEW_EFFORT")
  batch_failed=0
  batch_unconfirmed=0
  for batch_task in "${BATCH_TASKS[@]}"; do
    if "$SCRIPT_DIR/fm-control.sh" "$batch_task" relaunch "${batch_args[@]}"; then
      batch_rc=0
    else
      batch_rc=$?
    fi
    case "$batch_rc" in
      0) batch_result=confirmed ;;
      3) batch_result=unconfirmed; batch_unconfirmed=1 ;;
      *) batch_result=failed; batch_failed=1 ;;
    esac
    if [ "$batch_rc" -ge 128 ]; then
      batch_result=interrupted
    fi
    printf 'batch-relaunch: %s result=%s exit=%s\n' "$batch_task" "$batch_result" "$batch_rc"
    [ "$batch_rc" -lt 128 ] || exit "$batch_rc"
  done
  [ "$batch_failed" = 0 ] || exit 1
  [ "$batch_unconfirmed" = 0 ] || exit 3
  exit 0
fi

# --- exact task-id resolution ----------------------------------------------

case "$RAW_ID" in
  *:*) die "'$RAW_ID' is an explicit backend endpoint; fm-control accepts an exact task id only, so a lifecycle command can never land on an endpoint this home does not own" ;;
esac
if ! fm_task_id_creation_valid "$RAW_ID"; then
  die "'$RAW_ID' is not a valid task id"
fi
ID=$RAW_ID
# Supervision lease guard: lifecycle control is overlap territory between the
# two Pi supervision actors; refuse while the OTHER actor holds this task's
# live lease (contract: bin/fm-lease-lib.sh; no-op in homes without leases).
# shellcheck source=bin/fm-lease-lib.sh
. "$SCRIPT_DIR/fm-lease-lib.sh"
CONTROL_LOCK="$STATE/.control-$ID.lock"
trap control_cleanup EXIT
if [ "$VERB" != inspect ]; then
  fm_lease_guard "$ID" "lifecycle control (fm-control)"
  fm_lock_try_acquire "$CONTROL_LOCK" \
    || die "another lifecycle action is already running for task $ID"
  CONTROL_LOCK_HELD=1
fi
META="$STATE/$ID.meta"
if [ ! -f "$META" ]; then
  case "$RAW_ID" in
    fm-*)
      if [ -f "$STATE/${RAW_ID#fm-}.meta" ]; then
        die "'$RAW_ID' is a window label, not a task id; pass the exact task id '${RAW_ID#fm-}'"
      fi
      ;;
  esac
  die "no task '$ID' in $STATE (fm-control resolves an exact task id only)"
fi

# A remotely placed secondmate records its endpoint on ANOTHER host, so every
# postcondition this plane verifies - the agent-state classification, the busy
# verdict, the endpoint's existence - would be read here for an endpoint that
# does not live here. Endpoint validation already refuses such a record, since
# `window=remote:<id>` can never match a local backend's required shape, so
# nothing can be delivered to a wrong endpoint either way. What that refusal
# cannot say is WHY, and "malformed metadata" is the wrong thing to tell an
# operator about a correctly configured remote route. Name the placement
# instead, using the same `remote_host` signal bin/fm-send.sh routes on.
if [ -n "$(fm_meta_get "$META" remote_host)" ]; then
  die "task $ID is a remotely placed secondmate on $(fm_meta_get "$META" remote_host); its agent runs outside this home, so no lifecycle action here could verify that it interrupted, stopped, or came back. Drive its lifecycle on that host, and reconcile it through the secondmate recovery path rather than this plane"
fi

fm_backend_validate_task_endpoint "$META" "$ID" || exit 1
BACKEND=$FM_BACKEND_VALIDATED_BACKEND
T=$FM_BACKEND_VALIDATED_TARGET
LABEL="fm-$ID"
RECORDED_HARNESS=$(fm_meta_get "$META" harness)
KIND=$(fm_meta_get "$META" kind)
WT=$(fm_meta_get "$META" worktree)
[ -n "$KIND" ] || KIND=ship

HARNESS=$(fm_control_harness_family "$RECORDED_HARNESS") \
  || die "task $ID records harness '${RECORDED_HARNESS:-none}', which has no verified control mechanics; fm-control refuses to guess an interrupt key or exit command"
fm_control_harness_supported "$HARNESS" \
  || die "task $ID records harness '${RECORDED_HARNESS:-none}', which has no verified control mechanics; fm-control refuses to guess an interrupt key or exit command"

fm_backend_validate "$BACKEND" || exit 1

# --- shared helpers ---------------------------------------------------------

agent_state() {
  fm_backend_agent_state "$BACKEND" "$T"
}

busy_verdict() {
  fm_busy_classify_meta "$META" "$ID" "$STATE"
}

relaunch_terminal_report() {
  local gen='' boundary='' kind='' transaction='' report verb
  fm_meta_read "$META" spawn_gen gen launch_status boundary kind kind control_relaunch_tx transaction
  case "$kind" in ship|scout) ;; *) return 1 ;; esac
  [ -z "${RELAUNCH_TX:-}" ] || [ "$transaction" = "$RELAUNCH_TX" ] || return 1
  [ -z "${RELAUNCH_SPAWN_GEN:-}" ] || [ "$gen" = "$RELAUNCH_SPAWN_GEN" ] || return 1
  report=$(status_launch_current "$STATE/$ID.status" "$boundary" "$gen") || return 1
  verb=$(status_line_verb "$report")
  case "$verb" in done|failed) printf '%s' "$report" ;; *) return 1 ;; esac
}

# This read-only loop runs inside the timeout owner's isolated process group.
# Publish unreadable before each query so a killed or partially printed query
# cannot leave a previous observation masquerading as its completed result.
wait_agent_state_observe() {  # <wanted>...
  local state want report
  while :; do
    if [ "$1" = launched ] && report=$(relaunch_terminal_report); then
      printf 'reported-%s\n' "$(status_line_verb "$report")"
      return 0
    fi
    printf 'unreadable\n'
    state=$(agent_state) || return 1
    printf '%s\n' "$state"
    if [ "$1" = launched ]; then
      [ "$state" != alive ] || return 0
      if report=$(relaunch_terminal_report); then
        printf 'reported-%s\n' "$(status_line_verb "$report")"
        return 0
      fi
    fi
    for want in "$@"; do
      [ "$state" != "$want" ] || return 0
    done
    sleep "$POLL" || return 1
  done
}

# One elapsed-time deadline covers all queries and sleeps, including a stuck
# query. Prints the last completed observation (or unreadable while a query is
# incomplete); only a match completed before the bound returns success.
wait_agent_state() {  # <timeout> <wanted>...
  local timeout=$1 output rc=0 state
  shift
  if ! awk -v seconds="$timeout" 'BEGIN { exit !(seconds ~ /^([0-9]+([.][0-9]*)?|[.][0-9]+)$/ && seconds + 0 > 0) }'; then
    printf 'unreadable'
    return 1
  fi
  output=$(
    # The parent alone owns lifecycle rollback and lease/lock release. Neither
    # the observer nor its watchdog may inherit that transaction's EXIT trap.
    trap - EXIT
    # The documented Bash mechanism accepts the already-loaded shell function
    # and bounds its descendants without reloading adapters or changing Bash.
    FM_TIMEOUT_MECHANISM_OVERRIDE=bash fm_run_timed "$timeout" wait_agent_state_observe "$@"
  ) || rc=$?
  state=${output##*$'\n'}
  printf '%s' "${state:-unreadable}"
  [ "$rc" -eq 0 ]
}

require_state_verified_backend() {  # <verb>
  fm_control_backend_state_verified "$BACKEND" && return 0
  die "task $ID runs on the $BACKEND backend, which has no recovery-grade agent-state classifier, so '$1' cannot prove the agent actually stopped; refusing rather than reporting an unproven transition as done"
}

# send_interrupt_keys: deliver the harness's interrupt key the verified number
# of times, then the composer-clear key when the adapter needs one. Refuses
# before sending anything when the backend cannot deliver either key, because
# an interrupt that cancels the turn but leaves the restored prompt in the
# composer would make the next submitted line concatenate onto it.
send_interrupt_keys() {
  local key repeat clear i=0
  key=$(fm_control_interrupt_key "$HARNESS")
  repeat=$(fm_control_interrupt_repeat "$HARNESS")
  clear=$(fm_control_interrupt_clear_key "$HARNESS")
  fm_control_backend_supports_key "$BACKEND" "$key" \
    || die "harness $HARNESS interrupts with $key, which the $BACKEND backend cannot deliver; refusing to send a different key"
  [ -z "$clear" ] || fm_control_backend_supports_key "$BACKEND" "$clear" \
    || die "harness $HARNESS needs $clear to clear its composer after an interrupt, which the $BACKEND backend cannot deliver; refusing to leave the cancelled prompt where the next submitted line would concatenate onto it"
  while [ "$i" -lt "$repeat" ]; do
    fm_backend_send_key "$BACKEND" "$T" "$key" "$LABEL" \
      || die "interrupt key $key was not delivered to task $ID on $BACKEND"
    i=$((i + 1))
    [ "$i" -ge "$repeat" ] || sleep 0.2
  done
  [ -z "$clear" ] || fm_backend_send_key "$BACKEND" "$T" "$clear" "$LABEL" \
    || die "interrupt key $key reached task $ID, but $clear did not, so its composer still holds the cancelled prompt; clear it before the next lifecycle action"
}

prepare_interrupt_ack() {
  INTERRUPT_ACK_SOURCE=$(fm_control_interrupt_ack_source "$HARNESS")
  INTERRUPT_ACK_LOG=
  INTERRUPT_ACK_RUN=
  case "$INTERRUPT_ACK_SOURCE" in
    muse-session-terminal)
      INTERRUPT_ACK_LOG=$(fm_busy_muse_session_log "$STATE" "$ID" 2>/dev/null || true)
      [ -n "$INTERRUPT_ACK_LOG" ] || return 0
      INTERRUPT_ACK_RUN=$(fm_busy_muse_active_run_id "$INTERRUPT_ACK_LOG" 2>/dev/null || true)
      ;;
  esac
}

interrupt_cancel_claim() {
  local elapsed=0 terminal=
  case "$INTERRUPT_ACK_SOURCE:$INTERRUPT_ACK_RUN" in
    muse-session-terminal:?*) ;;
    *) printf 'unconfirmed'; return 0 ;;
  esac
  while :; do
    terminal=$(fm_busy_muse_run_terminal "$INTERRUPT_ACK_LOG" "$INTERRUPT_ACK_RUN" 2>/dev/null || true)
    case "$terminal" in
      cancelled) printf 'confirmed'; return 0 ;;
      ?*) printf 'unconfirmed'; return 0 ;;
    esac
    awk -v e="$elapsed" -v t="$SETTLE_WAIT" 'BEGIN{exit !(e < t)}' || break
    sleep "$POLL"
    elapsed=$(awk -v e="$elapsed" -v p="$POLL" 'BEGIN{printf "%.3f", e + p}')
  done
  printf 'unconfirmed'
}

# deliver_interrupt: deliver and observe the strongest adapter-owned
# cancellation claim available after delivery.
deliver_interrupt() {
  local cancel
  prepare_interrupt_ack
  send_interrupt_keys
  cancel=$(interrupt_cancel_claim)
  printf '%s' "$cancel"
}

verify_interrupt_running() {
  local proof after
  fm_backend_target_exists "$BACKEND" "$T" "$LABEL" \
    || die "task $ID's endpoint disappeared while interrupting it; no further control action is safe"
  proof=endpoint
  if fm_control_backend_state_verified "$BACKEND"; then
    # An interrupt cancels a turn; it must never have stopped the agent. This
    # is the postcondition that separates a landed interrupt from an accident.
    after=$(agent_state)
    [ "$after" = alive ] \
      || die "task $ID's agent is '$after' after its interrupt key; an interrupt must leave the agent running"
    proof=agent-alive
  fi
  printf '%s' "$proof"
}

do_interrupt() {
  local proof cancel
  cancel=$(deliver_interrupt) || return $?
  proof=$(verify_interrupt_running) || return $?
  printf '%s cancel=%s' "$proof" "$cancel"
}

retire_busy_incarnation() {
  if [ -f "$STATE/$ID.busy-gen" ]; then
    "$SCRIPT_DIR/fm-busy-event.sh" retire "$STATE" "$ID" --current-gen >/dev/null 2>&1 || true
  fi
}

# do_exit: stop the running agent, preserving endpoint and worktree. Prints
# `already-stopped`, `endpoint-gone`, or `stopped`.
do_exit() {
  local state cmd verdict composer_state cancel absence interrupt_result=not-needed
  require_state_verified_backend exit
  if [ -n "${FM_CONTROL_RECOVERY_EXPECTED_INSTANCES:-}" ]; then
    fm_control_recovery_instances "$T" \
      && [ "$FM_CONTROL_RECOVERY_INSTANCES" = "$FM_CONTROL_RECOVERY_EXPECTED_INSTANCES" ] \
      || die "the approved native process instances changed before exit; preserving the rebound record and all work"
  fi
  state=$(agent_state)
  case "$state" in
    dead)
      printf 'already-stopped'
      return 0
      ;;
    alive) ;;
    missing)
      # `missing` on its own is not a finding about the endpoint: it conflates
      # "destroyed" with "unreachable from this seat". Route it through the
      # control plane's one absence proof - the same one the relaunch gate uses
      # - and report what that proof actually established, never more.
      absence=$(fm_control_endpoint_absence_verdict "$BACKEND" "$T")
      case "${absence%%$'\t'*}" in
        gone)
          # Proven gone, so the agent that lived in it went with it: exit's
          # postcondition already holds and there is nothing to send. Its own
          # outcome rather than `already-stopped`, because the endpoint this
          # verb normally preserves did not survive. The worktree and every
          # uncommitted change are untouched, and `relaunch` re-creates the
          # endpoint from here.
          printf 'endpoint-gone'
          return 0
          ;;
        dead)
          # The endpoint was only unreachable and is there after all, holding
          # no agent - a herdr pane whose session server was merely stopped is
          # the common case. Nothing is gone, so this is the ordinary
          # already-stopped outcome.
          printf 'already-stopped'
          return 0
          ;;
        alive)
          # The agent came back with its endpoint. Fall through to the ordinary
          # alive path: interrupt if busy, then the harness's exit command.
          ;;
        *)
          die "task $ID's endpoint $T reads 'missing', but ${absence#*$'\t'}; exit will not claim an agent stopped at an address it cannot trust, nor send lifecycle input to one"
          ;;
      esac
      ;;
    *) die "task $ID's endpoint reads '$state' rather than a positively classified state; refusing to send a lifecycle command into an unattributed endpoint" ;;
  esac
  # A recovered record may have lost its old busy-generation wiring. Its exact
  # live process was just revalidated, so cancel its turn before sending exit
  # rather than borrowing a replacement generation's idle claim.
  if [ -n "${FM_CONTROL_RECOVERY_EXPECTED_INSTANCES:-}" ]; then verdict=busy;
  else verdict=$(busy_verdict); fi
  # A busy agent is interrupted first before the exit command is submitted.
  case "$verdict" in
    busy*)
      cancel=$(deliver_interrupt) || return $?
      state=$(agent_state)
      case "$state" in
        dead)
          retire_busy_incarnation
          printf 'stopped'
          return 0
          ;;
        alive) interrupt_result="delivered verified=agent-alive cancel=$cancel" ;;
        missing) die "task $ID's recorded endpoint disappeared after interrupt delivery, so exit cannot prove whether the agent stopped" ;;
        *) die "task $ID's endpoint reads '$state' after interrupt delivery rather than a positively classified state; exit cannot prove whether the agent stopped" ;;
      esac
      ;;
  esac
  cmd=$(fm_control_exit_command "$HARNESS")
  composer_state=$(fm_backend_composer_state "$BACKEND" "$T" "$LABEL" 2>/dev/null) \
    || composer_state=unknown
  case "$composer_state" in
    empty) ;;
    pending)
      die "task $ID's composer visibly holds pending text; refusing to type the $cmd exit command because it would concatenate onto that text. Clear or submit the pending text, then retry '$VERB'"
      ;;
    *)
      die "task $ID's composer state is '$composer_state', not proven empty; refusing to type the $cmd exit command because it could concatenate onto existing text. Clear the composer, then retry '$VERB'"
      ;;
  esac
  # The submit verdict is NOT the postcondition here: a successful exit command
  # destroys the composer the verdict is read from, so a post-exit read can
  # legitimately report anything. Only a hard transport failure aborts; the
  # authoritative proof is the agent-state wait below. The retried Enter still
  # matters, because a slash command opens a completion popup on some TUIs that
  # swallows the first Enter.
  verdict=$(fm_backend_send_text_submit "$BACKEND" "$T" "$cmd" "$EXIT_RETRIES" "$POLL" 1.2 "$LABEL") \
    || die "the exit command could not be sent to task $ID on $BACKEND"
  [ "$verdict" != send-failed ] \
    || die "the exit command could not be sent to task $ID on $BACKEND"
  state=$(wait_agent_state "$EXIT_WAIT" dead) || {
    die "exit-delivered $ID interrupt=$interrupt_result exit-command=delivered agent-state=$state exit=unconfirmed; the agent did not stop within ${EXIT_WAIT}s"
  }
  # The incarnation is over: retire its busy wiring so no stale record or
  # orphaned generation survives the agent that produced it.
  retire_busy_incarnation
  printf 'stopped'
}

# --- transactional relaunch -------------------------------------------------
#
# The transaction's durable record is state/<id>.control-relaunch, with the
# prior metadata and brief preserved beside it. Every failure path runs through
# relaunch_rollback (an EXIT trap, so a refusal raised deep inside a shared
# helper is covered too) and leaves either the pre-relaunch durable record or a
# concrete, named partial state. Accepted delivery, a live agent, and a
# terminal work report remain separate claims.

JOURNAL="$STATE/$ID.control-relaunch"
META_PRIOR="$JOURNAL.meta-prior"
BRIEF_PRIOR="$JOURNAL.brief-prior"
NOTE_FILE="$JOURNAL.note"
RELAUNCH_META_PUBLISHED=0
RELAUNCH_AGENT_CONFIRMED=0
RELAUNCH_DELIVERY_ACCEPTED=0
RELAUNCH_OUTCOME=
RELAUNCH_SPAWN_GEN=
RELAUNCH_TX=
RECREATE_FROM=
RELAUNCH_BRIEF=
PRIOR_HARNESS=$HARNESS
PRIOR_RECORDED_HARNESS=$RECORDED_HARNESS
CONFIG_HARNESS=
CONFIG_MODEL=
CONFIG_EFFORT=
PRIOR_MODEL=
PRIOR_EFFORT=
TARGET_HARNESS=$HARNESS
TARGET_MODEL=
TARGET_EFFORT=

journal_write() {  # <phase> [extra-line]...
  local phase=$1
  shift
  if {
    echo "v1"
    echo "task=$ID"
    echo "phase=$phase"
    echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "backend=$BACKEND"
    echo "endpoint=$T"
    echo "worktree=$WT"
    echo "kind=$KIND"
    [ -z "$RECREATE_FROM" ] || echo "recreate_from=$RECREATE_FROM"
    echo "from_harness=$PRIOR_RECORDED_HARNESS"
    echo "from_model=$PRIOR_MODEL"
    echo "from_effort=$PRIOR_EFFORT"
    echo "to_harness=$TARGET_HARNESS"
    echo "to_model=$TARGET_MODEL"
    echo "to_effort=$TARGET_EFFORT"
    [ -z "$RELAUNCH_TX" ] || echo "relaunch_tx=$RELAUNCH_TX"
    [ -z "$RELAUNCH_SPAWN_GEN" ] || echo "spawn_gen=$RELAUNCH_SPAWN_GEN"
    [ -z "$RELAUNCH_OUTCOME" ] || echo "launch_outcome=$RELAUNCH_OUTCOME"
    local line
    for line in "$@"; do
      echo "$line"
    done
  } > "$JOURNAL.tmp" && mv -f "$JOURNAL.tmp" "$JOURNAL"; then
    RELAUNCH_PHASE=$phase
    return 0
  fi
  return 1
}

relaunch_rollback() {
  local state
  [ "$RELAUNCH_ACTIVE" = 1 ] || return 0
  [ "$RELAUNCH_PHASE" != complete ] || return 0
  RELAUNCH_ACTIVE=0
  case "$RELAUNCH_PHASE" in
    recreating)
      journal_write "failed:recreating" || true
      echo "error: replacement endpoint creation for $ID did not complete; inspect $JOURNAL and the task record before retrying; its work is preserved at $WT" >&2
      ;;
    checkpoint|noted)
      # The old agent was never touched. Restore the instructions byte-exact so
      # a refused relaunch leaves nothing behind.
      if [ -n "$RELAUNCH_BRIEF" ] && [ -f "$BRIEF_PRIOR" ]; then
        cp -p "$BRIEF_PRIOR" "$RELAUNCH_BRIEF" 2>/dev/null || true
      fi
      journal_write "failed:$RELAUNCH_PHASE" "rollback=instructions-restored" || true
      echo "error: relaunch of $ID was refused before its agent was touched; nothing changed" >&2
      ;;
    stopping)
      state=$(agent_state 2>/dev/null || printf unknown)
      case "$state" in
        alive)
          if [ -n "$RELAUNCH_BRIEF" ] && [ -f "$BRIEF_PRIOR" ]; then
            cp -p "$BRIEF_PRIOR" "$RELAUNCH_BRIEF" 2>/dev/null || true
          fi
          journal_write "failed:$RELAUNCH_PHASE" "rollback=instructions-restored-agent-alive" || true
          echo "error: relaunch of $ID failed while stopping the old agent, which is still running; its original instructions were restored" >&2
          ;;
        dead)
          journal_write "failed:$RELAUNCH_PHASE" "rollback=prior-record-kept-agent-dead" || true
          echo "error: $ID's agent stopped but relaunch did not reach replacement launch; no agent is running, and its work plus progress note are preserved at $WT" >&2
          ;;
        *)
          # The old agent was NOT proven stopped, so no replacement is coming
          # and the agent that may still be reading these instructions is the
          # original one. The note exists to brief a replacement; leaving it in
          # a possibly-live agent's brief would be an unrequested edit to a
          # running task. Restore byte-exact, exactly as the alive case does.
          if [ -n "$RELAUNCH_BRIEF" ] && [ -f "$BRIEF_PRIOR" ]; then
            cp -p "$BRIEF_PRIOR" "$RELAUNCH_BRIEF" 2>/dev/null || true
          fi
          journal_write "failed:$RELAUNCH_PHASE" "rollback=instructions-restored-agent-state-$state" || true
          echo "error: relaunch of $ID failed while stopping the old agent and its state is '$state', so it was not proven stopped; its original instructions were restored and the durable record was retained for recovery" >&2
          ;;
      esac
      ;;
    exited|launching|launch-unconfirmed)
      if [ "$RELAUNCH_AGENT_CONFIRMED" = 1 ]; then
        journal_write "failed:$RELAUNCH_PHASE" "rollback=none-new-agent-confirmed" || true
        echo "error: $ID's replacement is running on $TARGET_HARNESS, but transaction completion could not be persisted; its published record was retained for reconciliation" >&2
      elif [ "$RELAUNCH_DELIVERY_ACCEPTED" = 1 ]; then
        journal_write "failed:$RELAUNCH_PHASE" "rollback=none-new-record-kept" || true
        echo "error: $ID's replacement launch was delivered but its outcome could not be persisted or confirmed; inspect its current report and preserved work at $WT before any retry" >&2
      elif [ "$RELAUNCH_META_PUBLISHED" = 1 ] \
         || { [ -n "$RELAUNCH_TX" ] \
              && [ "$(fm_meta_get "$META" control_relaunch_tx)" = "$RELAUNCH_TX" ]; }; then
        # The launch owner published the new incarnation's record. Leaving it
        # in place is the honest state: the task is now recorded on the new
        # harness with no agent confirmed, which is exactly what recovery
        # reconciles. Rewriting it back to the old harness would be a second,
        # worse inaccuracy.
        journal_write "failed:$RELAUNCH_PHASE" "rollback=none-new-record-kept" || true
        echo "error: $ID was relaunched on $TARGET_HARNESS but no running agent could be confirmed; its work is preserved at $WT" >&2
      else
        journal_write "failed:$RELAUNCH_PHASE" "rollback=prior-record-kept" || true
        echo "error: $ID's agent was stopped but the replacement did not launch; no agent is running, and its work plus the recorded progress note are preserved at $WT" >&2
      fi
      ;;
  esac
  return 0
}

resolve_relaunch_profile() {
  PRIOR_HARNESS=$HARNESS
  PRIOR_RECORDED_HARNESS=$RECORDED_HARNESS
  PRIOR_MODEL=$(fm_meta_get "$META" model)
  PRIOR_EFFORT=$(fm_meta_get "$META" effort)
  [ -n "$PRIOR_MODEL" ] || PRIOR_MODEL=default
  [ -n "$PRIOR_EFFORT" ] || PRIOR_EFFORT=default
  if [ "$HARNESS_SET" = 0 ] \
     && [ "$PRIOR_RECORDED_HARNESS" != "$PRIOR_HARNESS" ]; then
    die "task $ID records harness '$PRIOR_RECORDED_HARNESS', whose original launch command cannot be reconstructed from its recorded basename; relaunching without --harness would substitute the canonical adapter '$PRIOR_HARNESS' for the command actually running. Pass an explicit --harness to choose the replacement runtime deliberately"
  fi
  CONFIG_HARNESS=
  CONFIG_MODEL=
  CONFIG_EFFORT=
  if [ "$KIND" = secondmate ]; then
    # A secondmate's harness, model, and effort are a durable configured pin
    # that every respawn re-resolves (the secondmate-provisioning contract), so
    # a relaunch with no explicit harness picks up a newly configured one
    # instead of freezing whatever this incarnation happens to run. Crewmates
    # and scouts deliberately do NOT resolve config here: their harness comes
    # from firstmate's own dispatch-profile judgment at intake, and silently
    # re-resolving it would bypass that consultation.
    CONFIG_HARNESS=$("$SCRIPT_DIR/fm-harness.sh" secondmate 2>/dev/null || true)
    CONFIG_MODEL=$("$SCRIPT_DIR/fm-harness.sh" secondmate-model 2>/dev/null || true)
    CONFIG_EFFORT=$("$SCRIPT_DIR/fm-harness.sh" secondmate-effort 2>/dev/null || true)
    case "$CONFIG_EFFORT" in
      ''|low|medium|high|xhigh|max|ultra) ;;
      *)
        echo "warning: config/secondmate-harness effort token '$CONFIG_EFFORT' is not one of low, medium, high, xhigh, max, ultra; ignoring" >&2
        CONFIG_EFFORT=
        ;;
    esac
  fi
  if [ "$HARNESS_SET" = 1 ]; then
    fm_control_harness_supported "$NEW_HARNESS" \
      || die "'$NEW_HARNESS' is not a verified harness; fm-control refuses to relaunch onto an adapter with no verified control or launch mechanics"
    TARGET_HARNESS=$NEW_HARNESS
  elif [ "$HARNESS_SET" = 0 ] && [ -n "$CONFIG_HARNESS" ]; then
    fm_control_harness_supported "$CONFIG_HARNESS" \
      || die "the configured secondmate harness '$CONFIG_HARNESS' is not verified; fm-control refuses to relaunch onto an adapter with no verified control or launch mechanics"
    TARGET_HARNESS=$CONFIG_HARNESS
  else
    TARGET_HARNESS=$PRIOR_HARNESS
  fi
  # The launch owner refuses an adapter that cannot run this task's kind, but it
  # is only reached after the old agent has been stopped. Asking the same
  # capability table here keeps that refusal on the pre-stop side of the
  # transaction, where nothing has changed yet.
  fm_control_harness_supports_kind "$TARGET_HARNESS" "$KIND" \
    || die "'$TARGET_HARNESS' is not verified to run a $KIND task, so relaunching $ID onto it would stop the running agent for a launch that must be refused; choose an adapter verified for this kind"
  # A model or effort chosen for the previous harness does not transfer to a
  # different one, so an explicit harness change resets both axes unless the
  # caller names them too.
  if [ "$MODEL_SET" = 1 ]; then
    TARGET_MODEL=$NEW_MODEL
  elif [ "$HARNESS_SET" = 0 ] && [ -n "$CONFIG_HARNESS" ]; then
    TARGET_MODEL=${CONFIG_MODEL:-default}
  elif [ "$TARGET_HARNESS" = "$PRIOR_HARNESS" ]; then
    TARGET_MODEL=$PRIOR_MODEL
  else
    TARGET_MODEL=default
  fi
  if [ "$EFFORT_SET" = 1 ]; then
    TARGET_EFFORT=$NEW_EFFORT
  elif [ "$HARNESS_SET" = 0 ] && [ -n "$CONFIG_HARNESS" ]; then
    TARGET_EFFORT=${CONFIG_EFFORT:-default}
  elif [ "$TARGET_HARNESS" = "$PRIOR_HARNESS" ]; then
    TARGET_EFFORT=$PRIOR_EFFORT
  else
    TARGET_EFFORT=default
  fi
  if [ "$TARGET_EFFORT" = ultra ]; then
    "$SCRIPT_DIR/fm-harness.sh" validate-native-effort "$TARGET_HARNESS" "$TARGET_MODEL" "$TARGET_EFFORT" || return 1
  fi
}

# safe_checkpoint: prove, before anything is stopped, that the work a relaunch
# must preserve is actually there and recoverable afterwards. Fills
# CHECKPOINT_LINES with the journal lines describing what it proved, and
# refuses outright when any of it cannot be established.
CHECKPOINT_LINES=()
safe_checkpoint() {
  local wt_real wt_top wt_top_real wt_git_path head head_ref head_ref_status status_output dirty children marker child_meta
  CHECKPOINT_LINES=()
  [ -n "$WT" ] || die "task $ID has no recorded worktree; refusing to relaunch without a recorded local copy to preserve"
  [ -d "$WT" ] || die "task $ID's recorded worktree $WT is missing; refusing to relaunch and lose track of its work"
  wt_real=$(cd "$WT" 2>/dev/null && pwd -P) || die "task $ID's recorded worktree $WT cannot be resolved"
  fm_path_native_argument "$wt_real" wt_git_path || die "task $ID's Git directory argument cannot be resolved"
  wt_top=$(git -C "$wt_git_path" rev-parse --show-toplevel 2>/dev/null) \
    || die "task $ID's recorded worktree $WT is not a git worktree; refusing to relaunch without a checkout whose unlanded work can be accounted for"
  wt_top_real=$(cd "$wt_top" 2>/dev/null && pwd -P) || wt_top_real=$wt_top
  fm_platform_same_directory "$wt_real" "$wt_top_real" \
    || die "task $ID's recorded worktree $WT is not a worktree root (root is $wt_top); refusing to relaunch against an ambiguous checkout"
  if head=$(git -C "$wt_git_path" rev-parse --verify HEAD 2>/dev/null); then
    :
  elif head_ref=$(git -C "$wt_git_path" symbolic-ref -q HEAD 2>/dev/null); then
    if git -C "$wt_git_path" show-ref --verify --quiet "$head_ref" 2>/dev/null; then
      die "task $ID's worktree HEAD exists but cannot be resolved; refusing to relaunch from an unreadable checkout"
    else
      head_ref_status=$?
      [ "$head_ref_status" -eq 1 ] \
        || die "task $ID's worktree HEAD cannot be inspected; refusing to relaunch from an unreadable checkout"
      head=unborn
    fi
  else
    die "task $ID's worktree HEAD cannot be inspected; refusing to relaunch from an unreadable checkout"
  fi
  status_output=$(git -C "$wt_git_path" status --porcelain 2>/dev/null) \
    || die "task $ID's worktree status cannot be inspected; refusing to relaunch without accounting for local changes"
  if [ -n "$status_output" ]; then
    dirty=yes
  else
    dirty=no
  fi
  CHECKPOINT_LINES+=("worktree_head=$head" "worktree_dirty=$dirty")
  if [ "$KIND" = secondmate ]; then
    # A secondmate's own crewmates outlive its relaunch: they run in their own
    # endpoints, and the relaunched secondmate reconciles them from its home's
    # durable records at startup. The checkpoint proves those records are
    # readable BEFORE the agent stops, so a relaunch can never strand child
    # work behind an unreadable home.
    marker=$(cat "$WT/.fm-secondmate-home" 2>/dev/null || true)
    [ "$marker" = "$ID" ] \
      || die "task $ID's home $WT is not marked as its own seeded secondmate home (marker: ${marker:-none}); refusing to relaunch"
    [ -d "$WT/state" ] \
      || die "secondmate $ID's home has no readable state directory, so its child work cannot be accounted for; refusing to relaunch"
    find "$WT/state" -mindepth 1 -maxdepth 1 -print >/dev/null 2>&1 \
      || die "secondmate $ID's child records cannot be traversed; refusing to relaunch"
    children=0
    for child_meta in "$WT/state"/*.meta; do
      if [ ! -e "$child_meta" ] && [ ! -L "$child_meta" ]; then
        continue
      fi
      if [ ! -f "$child_meta" ] || [ -L "$child_meta" ] \
         || ! cat "$child_meta" >/dev/null 2>&1; then
        die "secondmate $ID's child record $child_meta is not a readable regular file; refusing to relaunch"
      fi
      children=$((children + 1))
    done
    CHECKPOINT_LINES+=("children=$children")
  fi
}

# record_note: put the required progress note somewhere durable, and - for a
# ship or scout, whose only record of the interrupted reasoning is the
# conversation about to be discarded - into the instructions the replacement
# actually reads. A secondmate's charter is a durable standing document and is
# never rewritten: a secondmate reconciles its own home's records at startup,
# so the note stays parent-side audit evidence.
record_note() {
  local stamp
  [ -n "$NOTE" ] || return 0
  stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' "$NOTE" > "$NOTE_FILE"
  case "$KIND" in
    ship|scout)
      cp -p "$RELAUNCH_BRIEF" "$BRIEF_PRIOR" \
        || die "could not preserve task $ID's instructions before recording the progress note"
      {
        echo
        echo "## Progress note ($stamp)"
        echo
        echo "This task was relaunched. Continue from here; the local copy and every"
        echo "uncommitted change are exactly as the previous worker left them."
        echo
        echo "First, check your instruction inbox: list $STATE/$ID.inbox/*.msg, act on"
        echo "each message in numeric order, then mv each handled file into"
        echo "$STATE/$ID.inbox/handled/. A steer sent before the relaunch survives there."
        echo
        printf '%s\n' "$NOTE"
      } >> "$RELAUNCH_BRIEF" \
        || die "could not append the progress note to task $ID's instructions"
      ;;
  esac
}

confirm_relaunch() {  # <result-prefix> [journal-lines...]
  local prefix=$1 state report=
  shift
  state=$(wait_agent_state "$LAUNCH_WAIT" launched) || {
    # A report may arrive while the final endpoint query is stuck. Reconcile
    # local durable evidence once after that query's deadline, without another
    # endpoint query or another launch attempt.
    if report=$(relaunch_terminal_report); then
      state="reported-$(status_line_verb "$report")"
    else
      case "$state" in
        dead|missing)
          RELAUNCH_OUTCOME=exited-without-report
          die "the replacement agent for $ID exited without a current terminal report (endpoint reads '$state'); its work is preserved at $WT"
          ;;
        *)
          RELAUNCH_OUTCOME=unconfirmed
          journal_write launch-unconfirmed "$@" "delivery=accepted" "observation=$state"
          RELAUNCH_ACTIVE=0
          echo "relaunch-unconfirmed $ID delivery=accepted endpoint_state=$state; inspect the current report before retrying; worktree=$WT"
          return 3
          ;;
      esac
    fi
  }
  RELAUNCH_OUTCOME=$state
  [ "$state" != alive ] || RELAUNCH_AGENT_CONFIRMED=1
  journal_write complete "$@" "delivery=accepted"
  RELAUNCH_ACTIVE=0
  echo "$prefix $ID harness=$TARGET_HARNESS from=$PRIOR_RECORDED_HARNESS model=$TARGET_MODEL effort=$TARGET_EFFORT backend=$BACKEND endpoint=$T worktree=$WT outcome=$state"
  if [ "$state" != alive ]; then
    [ -n "$report" ] || report=$(relaunch_terminal_report) || report=
    [ -z "$report" ] || printf 'report: %s\n' "$report"
  fi
}

do_relaunch() {
  local exit_result note_line prior_tx prior_gen
  local -a spawn_args

  require_state_verified_backend relaunch
  resolve_relaunch_profile
  case "$(fm_meta_get "$JOURNAL" phase)" in
    launch-unconfirmed)
      prior_tx=$(fm_meta_get "$JOURNAL" relaunch_tx)
      prior_gen=$(fm_meta_get "$JOURNAL" spawn_gen)
      [ -n "$prior_tx" ] && [ -n "$prior_gen" ] \
        && [ "$(fm_meta_get "$META" control_relaunch_tx)" = "$prior_tx" ] \
        && [ "$(fm_meta_get "$META" spawn_gen)" = "$prior_gen" ] \
        || die "the unconfirmed launch binding changed; inspect $JOURNAL and the task record before another lifecycle action"
      [ "$TARGET_HARNESS" = "$PRIOR_HARNESS" ] \
        && [ "$TARGET_MODEL" = "$PRIOR_MODEL" ] && [ "$TARGET_EFFORT" = "$PRIOR_EFFORT" ] \
        || die "the previous launch is unconfirmed; inspect it before choosing another replacement profile"
      RELAUNCH_TX=$prior_tx
      RELAUNCH_SPAWN_GEN=$prior_gen
      RELAUNCH_META_PUBLISHED=1
      RELAUNCH_DELIVERY_ACCEPTED=1
      RELAUNCH_PHASE=launch-unconfirmed
      RELAUNCH_ACTIVE=1
      confirm_relaunch relaunch-reconciled "new_note_delivered=false"
      return
      ;;
    recreating|failed:recreating)
      [ "$(fm_meta_get "$JOURNAL" recreate_from)" != "$T" ] \
        || die "the prior endpoint creation is unconfirmed; inspect $JOURNAL before creating another terminal"
      ;;
  esac

  case "$KIND" in
    ship|scout)
      RELAUNCH_BRIEF="$DATA/$ID/brief.md"
      [ -f "$RELAUNCH_BRIEF" ] \
        || die "task $ID has no instructions at $RELAUNCH_BRIEF; refusing to relaunch a worker with nothing to work from"
      [ "$NOTE_SET" = 1 ] && [ -n "$NOTE" ] \
        || die "relaunch of a $KIND task requires --note (or --note-file): the replacement worker inherits the local copy but none of the conversation, so it must be told what happened"
      ;;
    secondmate)
      # The charter in the secondmate's own home is its instruction source and
      # stays untouched.
      RELAUNCH_BRIEF=
      ;;
    *)
      die "task $ID records kind '$KIND', which has no defined relaunch shape"
      ;;
  esac

  if [ -n "$NOTE" ]; then
    note_line="note_file=$NOTE_FILE"
  else
    note_line="note=none"
  fi
  safe_checkpoint
  cp -p "$META" "$META_PRIOR" || die "could not preserve task $ID's durable record before relaunching"
  RELAUNCH_ACTIVE=1
  journal_write checkpoint "${CHECKPOINT_LINES[@]}" "$note_line"

  record_note
  journal_write noted "${CHECKPOINT_LINES[@]}" "$note_line"

  if [ "$BACKEND" = herdr ] && [ "$KIND" != secondmate ] \
     && [ "$(agent_state)" = missing ]; then
    fm_control_recreate_endpoint || die "the missing endpoint could not be recovered safely"
    if [ -n "$RECREATE_FROM" ]; then
      exit_result="endpoint-gone $ID (missing endpoint recovered)"
    else
      exit_result="already-stopped $ID (recorded endpoint restored)"
    fi
  else
    journal_write stopping "${CHECKPOINT_LINES[@]}" "$note_line"
    exit_result=$(do_exit)
  fi
  journal_write exited "${CHECKPOINT_LINES[@]}" "$note_line" "exit_result=$exit_result"

  # The launch owner (fm-spawn --relaunch) clears the previous incarnation's
  # per-task harness wiring before arming the new one, so nothing to do here.
  RELAUNCH_TX="${BASHPID:-$$}.$(date -u +%Y%m%dT%H%M%SZ).$RANDOM"
  journal_write launching "${CHECKPOINT_LINES[@]}" "$note_line"
  spawn_args=("$ID" --relaunch --harness "$TARGET_HARNESS")
  [ "$TARGET_MODEL" = default ] || spawn_args+=(--model "$TARGET_MODEL")
  [ "$TARGET_EFFORT" = default ] || spawn_args+=(--effort "$TARGET_EFFORT")
  if FM_CONTROL_RELAUNCH_TX="$RELAUNCH_TX" \
      "$SCRIPT_DIR/fm-spawn.sh" "${spawn_args[@]}" >/dev/null; then
    RELAUNCH_META_PUBLISHED=1
    RELAUNCH_DELIVERY_ACCEPTED=1
    RELAUNCH_SPAWN_GEN=$(fm_meta_get "$META" spawn_gen)
    # $T was resolved from the record before the launch. When the recorded
    # endpoint was gone, the launch owner created a fresh one and republished
    # the record pointing at it, so every postcondition below must be read from
    # the endpoint the task now HAS, not the one it had. Re-resolving through
    # the same shared validation is what makes that safe: a record that no
    # longer passes it refuses here rather than leaving this transaction
    # polling an address nothing owns.
    # stdout is dropped (it is only the resolved target), but the refusal on
    # stderr names the exact row that failed - and in this one branch the record
    # was just rewritten by the launch owner, so that row is the whole
    # diagnostic. Let it through rather than dying with nothing to act on.
    if fm_backend_validate_task_endpoint "$META" "$ID" >/dev/null \
       && [ -n "$FM_BACKEND_VALIDATED_TARGET" ]; then
      T=$FM_BACKEND_VALIDATED_TARGET
    else
      die "the replacement agent for $ID was launched, but task $ID's republished record no longer passes endpoint validation (the refusal above names the row), so this transaction cannot say which endpoint to confirm it on; reconcile $META before any further control action"
    fi
  else
    [ "$(fm_meta_get "$META" control_relaunch_tx)" != "$RELAUNCH_TX" ] \
      || RELAUNCH_META_PUBLISHED=1
    die "the replacement agent for $ID could not be launched on $TARGET_HARNESS"
  fi

  confirm_relaunch relaunched "${CHECKPOINT_LINES[@]}" "$note_line" "exit_result=$exit_result"
}

# --- inspection and explicitly approved record recovery ----------------------

if [ -n "$RECOVER_FROM" ] || [ "$VERB" = inspect ] || [ "$VERB" = relaunch ]; then
  # shellcheck source=bin/fm-control-recovery-lib.sh
  . "$SCRIPT_DIR/fm-control-recovery-lib.sh"
fi

if [ "$VERB" = inspect ]; then
  recovery=null
  recovered_token=$(fm_meta_get "$META" control_recovery_token)
  if [ -n "$recovered_token" ]; then
    recovery=$(fm_control_recovery_read_receipt "$STATE" "$ID" "$FM_HOME" "$recovered_token") \
      || die "the bound recovery receipt cannot be read safely"
  elif [ -n "$RECOVER_FROM" ]; then
    fm_control_recovery_plan "$META" "$RECOVER_FROM" "$ID" "$STATE" "$DATA" "$FM_HOME" \
      || die "no safe record-recovery plan could be proven"
    recovery=$FM_CONTROL_RECOVERY_PLAN
    if [ -e "$STATE/$ID.control-recovery/$FM_CONTROL_RECOVERY_TOKEN/receipt.json" ]; then
      attempt=$(fm_control_recovery_read_receipt "$STATE" "$ID" "$FM_HOME" "$FM_CONTROL_RECOVERY_TOKEN") \
        || die "the prior recovery attempt cannot be read safely"
      recovery=$(printf '%s' "$recovery" | jq --argjson attempt "$attempt" '. + {previous_attempt:$attempt}')
    fi
  fi
  in_progress=false
  [ ! -e "$CONTROL_LOCK" ] && [ ! -L "$CONTROL_LOCK" ] || in_progress=true
  launch_report=$(relaunch_terminal_report) || launch_report=
  jq -n --arg task "$ID" --arg backend "$BACKEND" --arg endpoint "$T" \
    --arg worktree "$WT" --arg harness "$HARNESS" --arg state "$(agent_state)" \
    --arg phase "$(fm_meta_get "$JOURNAL" phase)" --argjson progress "$in_progress" \
    --argjson recovery "$recovery" --arg report "$launch_report" \
    '{schema:"fm-control-inspection.v1",task:$task,backend:$backend,endpoint:$endpoint,worktree:$worktree,harness:$harness,agent_state:$state,transaction_phase:$phase,action_in_progress:$progress,recovery:$recovery,launch_report:$report}'
  exit 0
fi

if [ -n "$RECOVER_FROM" ]; then
  [ "$NOTE_SET" = 1 ] && [ -n "$NOTE" ] || die "record recovery requires a progress note"
  prior_receipt="$STATE/$ID.control-recovery/$APPROVE_RECOVERY/receipt.json"
  if [ -e "$prior_receipt" ] || [ -L "$prior_receipt" ]; then
    if [ "$(fm_meta_get "$META" control_recovery_token)" = "$APPROVE_RECOVERY" ] \
       && prior_attempt=$(fm_control_recovery_read_receipt "$STATE" "$ID" "$FM_HOME" "$APPROVE_RECOVERY") \
       && printf '%s' "$prior_attempt" | jq -e '.phase == "complete"' >/dev/null; then
      echo "recovery-already-complete $ID receipt=$prior_receipt"
      exit 0
    fi
    die "this recovery was already attempted; inspect $prior_receipt and the current transaction instead of relaunching again"
  fi
  RECOVERY_META_LOCK=$(fm_meta_lock_path "$META") || exit 1
  fm_lock_try_acquire "$RECOVERY_META_LOCK" || die "task metadata is busy; inspect again after its writer finishes"
  RECOVERY_META_LOCK_HELD=1
  RECOVERY_SET_LOCK=$(fm_task_set_lock_path "$STATE") || exit 1
  fm_lock_try_acquire "$RECOVERY_SET_LOCK" || die "the task set is changing; inspect again after it settles"
  RECOVERY_SET_LOCK_HELD=1
  fm_control_recovery_plan "$META" "$RECOVER_FROM" "$ID" "$STATE" "$DATA" "$FM_HOME" \
    || die "the approved record-recovery conditions no longer hold"
  [ "$FM_CONTROL_RECOVERY_TOKEN" = "$APPROVE_RECOVERY" ] \
    || die "recovery plan changed since approval; inspect the new evidence before any mutation"
  for other_meta in "$STATE/"*.meta; do
    [ "$other_meta" = "$META" ] && continue
    [ -e "$other_meta" ] || [ -L "$other_meta" ] || continue
    [ -f "$other_meta" ] && [ ! -L "$other_meta" ] || die "another task record is unreadable"
    other_target=$(fm_backend_meta_exact_value "$other_meta" window) || die "another task's endpoint claim is ambiguous"
    other_wt=$(fm_backend_meta_exact_value "$other_meta" worktree) || die "another task's worktree claim is ambiguous"
    candidate_wt=$(fm_meta_get "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" worktree)
    if [ "$other_target" = "$FM_CONTROL_RECOVERY_TARGET" ] \
       || fm_platform_same_directory "$other_wt" "$candidate_wt"; then
      die "another task record claims the proposed endpoint or worktree"
    fi
  done
  fm_control_recovery_apply "$META" "$STATE" "$ID" || die "record recovery could not be published; inspect the retained receipt"
  fm_backend_validate_task_endpoint "$META" "$ID" || exit 1
  BACKEND=$FM_BACKEND_VALIDATED_BACKEND
  T=$FM_BACKEND_VALIDATED_TARGET
  fm_meta_read "$META" worktree WT harness RECORDED_HARNESS kind KIND
  HARNESS=$(fm_control_harness_family "$RECORDED_HARNESS") || exit 1
  fm_lock_release "$RECOVERY_META_LOCK"
  RECOVERY_META_LOCK_HELD=0
  fm_lock_release "$RECOVERY_SET_LOCK"
  RECOVERY_SET_LOCK_HELD=0
fi

# --- verbs ------------------------------------------------------------------

case "$VERB" in
  interrupt)
    state=$(agent_state)
    case "$state" in
      alive) ;;
      unverified)
        # No recovery-grade classifier on this backend. Interrupt is
        # non-destructive and its endpoint-existence postcondition is still
        # real, so it proceeds - the printed proof names exactly what was
        # verified rather than implying more.
        ;;
      dead|missing) die "no agent is running at task $ID's recorded endpoint (state: $state); there is nothing to interrupt" ;;
      *) die "task $ID's endpoint reads '$state' rather than a positively classified state; refusing to send a lifecycle key into an unattributed endpoint" ;;
    esac
    proof=$(do_interrupt)
    echo "interrupt-delivered $ID harness=$HARNESS backend=$BACKEND verified=$proof"
    ;;
  exit)
    result=$(do_exit)
    echo "$result $ID harness=$HARNESS backend=$BACKEND endpoint=$T worktree=$WT"
    ;;
  relaunch)
    do_relaunch
    if [ -n "$RECOVER_FROM" ]; then
      fm_control_recovery_receipt_phase complete \
        || die "the recovered worker is running but its completion receipt could not be written"
      echo "recovery-complete $ID receipt=$FM_CONTROL_RECOVERY_RECEIPT prior-copy-and-lease=preserved"
    fi
    ;;
esac

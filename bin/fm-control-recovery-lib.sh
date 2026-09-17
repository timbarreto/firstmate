#!/usr/bin/env bash
# Internal record-recovery implementation consumed only by fm-control.sh.
# The public inspect/relaunch interface, authority, and transaction belong there.
# Recovery is deliberately narrow: an absent Herdr endpoint, a home-local prior
# record, the same project/profile, and an exact task-held Treehouse lease.
# The proposed Windows endpoint must really be in that copy. Native root/agent
# PID birth identities and both lease IDs bind the approval, not process names
# or terminal labels alone. Nothing here closes a pane or returns a lease.
# Current task fields not describing the endpoint/incarnation survive repair.
# Inspection writes only private temporary snapshots; apply requires the
# caller's control and metadata locks and a freshly recomputed approval digest.

FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT=
FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT=
FM_CONTROL_RECOVERY_PLAN=
FM_CONTROL_RECOVERY_TOKEN=
FM_CONTROL_RECOVERY_RECEIPT=
FM_CONTROL_RECOVERY_EXPECTED_INSTANCES=
FM_CONTROL_RECOVERY_TARGET=
FM_CONTROL_RECOVERY_CURRENT_HASH=
FM_CONTROL_RECOVERY_CANDIDATE_HASH=

fm_control_recovery_error() {
  printf 'error: record recovery refused: %s\n' "$1" >&2
  return 1
}

fm_control_recovery_cleanup() {
  [ -z "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT" ] || rm -f -- "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT"
  [ -z "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" ] || rm -f -- "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT"
  FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT=
  FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT=
}

fm_control_recovery_snapshot() {  # <source> <output-variable>
  local source=$1 destination=$2 tmp before after
  [ -f "$source" ] && [ ! -L "$source" ] && [ "$(fm_pr_file_link_count "$source")" = 1 ] \
    || return 1
  before=$(fm_pr_file_identity "$source") || return 1
  tmp=$(umask 077; mktemp "${TMPDIR:-/tmp}/fm-control-record.XXXXXX") || return 1
  if ! fm_pr_private_file_secure "$tmp" 600 || ! cat -- "$source" > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  after=$(fm_pr_file_identity "$source") || after=
  if [ "$before" != "$after" ] || [ -L "$source" ] || ! cmp -s "$source" "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  printf -v "$destination" '%s' "$tmp"
}

fm_control_recovery_record_shape() {  # generation/profile fields must be unambiguous
  awk -F= '
    BEGIN { split("harness kind mode yolo busy_gen spawn_gen", fields, " "); for (i in fields) wanted[fields[i]]=1 }
    $1 in wanted { count[$1]++; if (NF != 2 || $2 == "" || $2 ~ /[^A-Za-z0-9._:-]/) bad=1 }
    END { for (field in wanted) if (count[field] != 1) bad=1; exit bad ? 1 : 0 }
  ' "$1"
}

fm_control_recovery_instances() {  # <Herdr target>; native identity, no action
  local target=$1 info shell_pid rows pid birth name args signature='' agents=0 family
  fm_platform_windows_process_supported || return 1
  fm_backend_herdr_parse_target "$target" || return 1
  info=$(fm_backend_herdr_cli "$FM_BACKEND_HERDR_SESSION" pane process-info --pane "$FM_BACKEND_HERDR_PANE") || return 1
  shell_pid=$(printf '%s' "$info" | jq -er --arg pane "$FM_BACKEND_HERDR_PANE" '
    select(.result.type == "pane_process_info" and .result.process_info.pane_id == $pane)
    | .result.process_info.shell_pid | select(type == "number" and . > 1 and floor == .)
  ') || return 1
  rows=$(fm_platform_windows_descendant_processes "$shell_pid") || return 1
  [ "${rows%%$'\t'*}" = "$shell_pid" ] || return 1
  while IFS=$'\t' read -r pid birth name args; do
    case "$pid:$birth" in *[!0-9:]*|:*|*:) return 1 ;; esac
    [ -n "$name" ] || return 1
    if [ "$pid" = "$shell_pid" ]; then
      signature="$pid:$birth"
    elif [ "$(fm_agent_process_classify "$name" "$name" "$args")" = agent ]; then
      name=${name##*/}
      family=$(fm_control_harness_family "$name") || return 1
      [ "$family" = copilot ] || return 1
      signature="$signature"$'\n'"$pid:$birth"
      agents=$((agents + 1))
    fi
  done <<< "$rows"
  [ -n "$signature" ] || return 1
  FM_CONTROL_RECOVERY_INSTANCES=$(printf '%s\n' "$signature" | LC_ALL=C sort -t: -k1,1n)
  FM_CONTROL_RECOVERY_AGENT_COUNT=$agents
}

fm_control_recovery_pool_binding() {  # <pool-json> <copy> <task> <must-be-unused>
  local pool=$1 copy=$2 task=$3 unused=$4 rows path status lease holder count found=0
  FM_CONTROL_RECOVERY_LEASE=
  rows=$(printf '%s' "$pool" | jq -er '
    (if type == "array" then . elif (.worktrees | type) == "array" then .worktrees else error("pool") end)
    | .[]
    | if type == "object" and (.path | type) == "string" and (.status | type) == "string"
      and ((.lease_id // "") | type) == "string" and ((.lease_holder // "") | type) == "string"
      and (.processes | type) == "array" then . else error("pool record") end
    | [.path,.status,(.lease_id // ""),(.lease_holder // ""),(.processes | length | tostring)]
    | if any(.[]; test("[[:cntrl:]]")) then error("pool field") else join("\u001f") end
  ') || return 1
  while IFS=$'\x1f' read -r path status lease holder count; do
    fm_platform_same_directory "$path" "$copy" || continue
    found=$((found + 1))
    [ "$status" = leased ] && [ "$holder" = "$task" ] && [ -n "$lease" ] || return 1
    [ "$unused" != 1 ] || [ "$count" = 0 ] || return 1
    FM_CONTROL_RECOVERY_LEASE=$lease
  done <<< "$rows"
  [ "$found" = 1 ]
}

fm_control_recovery_plan() {  # <current-meta> <prior-record> <task> <state> <data> <home>
  local meta=$1 candidate=$2 task=$3 state=$4 data=$5 home=$6
  local candidate_dir candidate_path state_real data_real current_target candidate_target
  local current_project current_wt current_harness current_kind current_mode current_yolo
  local candidate_project candidate_wt candidate_harness candidate_kind candidate_mode candidate_yolo
  local current_common candidate_common current_lease candidate_lease pool cwd top branch head dirty
  local git_project git_worktree
  local current_state candidate_state bindings token
  fm_control_recovery_cleanup
  fm_path_absolute "$candidate" candidate || return 1
  [ -f "$candidate" ] && [ ! -L "$candidate" ] || fm_control_recovery_error "candidate must be a regular home-local record" || return 1
  candidate_dir=$(cd -- "${candidate%/*}" 2>/dev/null && pwd -P) || return 1
  candidate_path="$candidate_dir/${candidate##*/}"
  state_real=$(cd "$state" && pwd -P) || return 1
  data_real=$(cd "$data" && pwd -P) || return 1
  case "$candidate_path" in
    "$state_real/$task."*|"$data_real/$task/"*) ;;
    *) fm_control_recovery_error "candidate is outside this task's records in the selected home"; return 1 ;;
  esac
  if ! fm_control_recovery_snapshot "$meta" FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT \
     || ! fm_control_recovery_snapshot "$candidate_path" FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT; then
    fm_control_recovery_error "record identity changed or could not be captured"
    return 1
  fi
  if ! fm_control_recovery_record_shape "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT" \
     || ! fm_control_recovery_record_shape "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT"; then
    fm_control_recovery_error "profile or generation fields are missing, malformed, or duplicated"
    return 1
  fi
  fm_backend_validate_task_endpoint "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT" "$task" || return 1
  [ "$FM_BACKEND_VALIDATED_BACKEND" = herdr ] || { fm_control_recovery_error "record recovery requires Herdr"; return 1; }
  current_target=$FM_BACKEND_VALIDATED_TARGET
  fm_backend_validate_task_endpoint "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" "$task" || return 1
  [ "$FM_BACKEND_VALIDATED_BACKEND" = herdr ] || return 1
  candidate_target=$FM_BACKEND_VALIDATED_TARGET
  # Load the adapter in this frame, not only inside a state command substitution.
  fm_backend_source herdr || return 1
  [ "$current_target" != "$candidate_target" ] || { fm_control_recovery_error "the candidate is already the recorded endpoint"; return 1; }
  fm_meta_read "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT" project current_project worktree current_wt \
    harness current_harness kind current_kind mode current_mode yolo current_yolo
  fm_meta_read "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" project candidate_project worktree candidate_wt \
    harness candidate_harness kind candidate_kind mode candidate_mode yolo candidate_yolo
  [ -z "$(fm_meta_get "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" remote_host)" ] \
    || { fm_control_recovery_error "remote placement cannot be recovered locally"; return 1; }
  [ "$current_harness" = copilot ] && [ "$candidate_harness" = copilot ] \
    && [ "$current_kind" = ship ] && [ "$candidate_kind" = ship ] \
    && [ "$current_mode" = "$candidate_mode" ] && [ "$current_yolo" = "$candidate_yolo" ] \
    || { fm_control_recovery_error "candidate changes the task kind, harness, or delivery authority"; return 1; }
  fm_platform_same_directory "$current_project" "$candidate_project" \
    || { fm_control_recovery_error "candidate belongs to another project"; return 1; }
  fm_path_native_argument "$(CDPATH='' cd -- "$current_project" && pwd -P)" git_project || return 1
  fm_path_native_argument "$(CDPATH='' cd -- "$candidate_wt" && pwd -P)" git_worktree || return 1
  current_common=$(git -C "$git_project" rev-parse --path-format=absolute --git-common-dir) || return 1
  candidate_common=$(git -C "$git_worktree" rev-parse --path-format=absolute --git-common-dir) || return 1
  top=$(git -C "$git_worktree" rev-parse --show-toplevel) || return 1
  if ! fm_platform_same_directory "$current_common" "$candidate_common" \
     || ! fm_platform_same_directory "$candidate_wt" "$top"; then
    fm_control_recovery_error "candidate is not an exact worktree of the recorded project"
    return 1
  fi
  branch=$(git -C "$git_worktree" symbolic-ref --quiet --short HEAD) || return 1
  [ "$branch" = "fm/$task" ] || { fm_control_recovery_error "candidate branch does not name this exact task"; return 1; }
  current_state=$(fm_backend_agent_state herdr "$current_target") || return 1
  [ "$current_state" = missing ] || { fm_control_recovery_error "recorded endpoint is not positively missing"; return 1; }
  candidate_state=$(fm_backend_agent_state herdr "$candidate_target") || return 1
  case "$candidate_state" in alive|dead) ;; *) fm_control_recovery_error "candidate process state is not proven"; return 1 ;; esac
  cwd=$(fm_backend_herdr_current_path "$candidate_target") || return 1
  fm_platform_same_directory "$cwd" "$candidate_wt" \
    || { fm_control_recovery_error "candidate endpoint is not in the preserved copy"; return 1; }
  fm_control_recovery_instances "$candidate_target" \
    || { fm_control_recovery_error "native process instances cannot be pinned"; return 1; }
  [ "$candidate_state" != alive ] || [ "$FM_CONTROL_RECOVERY_AGENT_COUNT" -gt 0 ] \
    || { fm_control_recovery_error "no exact Copilot process supports the live verdict"; return 1; }
  command -v treehouse >/dev/null 2>&1 || return 1
  pool=$(cd "$current_project" && treehouse status --json) || return 1
  fm_control_recovery_pool_binding "$pool" "$candidate_wt" "$task" 0 \
    || { fm_control_recovery_error "candidate has no unique task-held lease"; return 1; }
  candidate_lease=$FM_CONTROL_RECOVERY_LEASE
  # A second copy is preserved, never silently returned or discarded. Its pool
  # must also prove it belongs to this task and has no process left using it.
  fm_control_recovery_pool_binding "$pool" "$current_wt" "$task" 1 \
    || { fm_control_recovery_error "the recorded copy is not a proven unused task-held lease"; return 1; }
  current_lease=$FM_CONTROL_RECOVERY_LEASE
  [ "$current_lease" != "$candidate_lease" ] || return 1
  FM_CONTROL_RECOVERY_CURRENT_HASH=$(fm_pr_sha256 "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT") || return 1
  FM_CONTROL_RECOVERY_CANDIDATE_HASH=$(fm_pr_sha256 "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT") || return 1
  cmp -s "$meta" "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT" \
    && cmp -s "$candidate_path" "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" || return 1
  bindings=$(jq -cSn --arg task "$task" --arg home "$home" --arg from "$current_target" \
    --arg to "$candidate_target" --arg copy "$candidate_wt" --arg preserved "$current_wt" \
    --arg current "$FM_CONTROL_RECOVERY_CURRENT_HASH" --arg candidate "$FM_CONTROL_RECOVERY_CANDIDATE_HASH" \
    --arg lease "$candidate_lease" --arg prior_lease "$current_lease" --arg instances "$FM_CONTROL_RECOVERY_INSTANCES" \
    '{task:$task,home:$home,from:$from,to:$to,copy:$copy,preserved_copy:$preserved,current_record:$current,candidate_record:$candidate,lease:$lease,preserved_lease:$prior_lease,native_instances:$instances}') || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    token=$(printf '%s' "$bindings" | sha256sum) || return 1
  else
    token=$(printf '%s' "$bindings" | shasum -a 256) || return 1
  fi
  FM_CONTROL_RECOVERY_TOKEN=${token%% *}
  head=$(git -C "$git_worktree" rev-parse --verify HEAD) || return 1
  dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$git_worktree" status --porcelain) || return 1
  # shellcheck disable=SC2034 # Same-process outputs consumed by fm-control.sh.
  FM_CONTROL_RECOVERY_TARGET=$candidate_target
  # shellcheck disable=SC2034 # Revalidated by the caller immediately before exit.
  FM_CONTROL_RECOVERY_EXPECTED_INSTANCES=$FM_CONTROL_RECOVERY_INSTANCES
  FM_CONTROL_RECOVERY_PLAN=$(jq -cn --argjson bindings "$bindings" --arg token "$FM_CONTROL_RECOVERY_TOKEN" \
    --arg state "$candidate_state" --arg branch "$branch" --arg head "$head" --arg dirty "$dirty" \
    '{schema:"fm-control-recovery-plan.v1",approval:$token,bindings:$bindings,candidate_state:$state,branch:$branch,observed_head:$head,dirty:($dirty != ""),preserves_other_copy:true,returns_no_lease:true}') || return 1
}

fm_control_recovery_apply() {  # <meta> <state> <task>; caller holds serialization locks
  local meta=$1 state=$2 task=$3 dir tmp key line value
  dir="$state/$task.control-recovery/$FM_CONTROL_RECOVERY_TOKEN"
  [ ! -e "$dir" ] && [ ! -L "$dir" ] || { fm_control_recovery_error "this plan was already attempted; inspect its receipt before retrying"; return 1; }
  [ ! -L "$state/$task.control-recovery" ] || return 1
  (umask 077; mkdir -p "$dir") || return 1
  FM_CONTROL_RECOVERY_RECEIPT="$dir/receipt.json"
  for key in current candidate; do
    tmp="$dir/$key.meta"
    (umask 077; : > "$tmp") || return 1
    fm_pr_private_file_secure "$tmp" 600 || return 1
    if [ "$key" = current ]; then cat "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT" > "$tmp";
    else cat "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" > "$tmp"; fi || return 1
  done
  (umask 077; : > "$FM_CONTROL_RECOVERY_RECEIPT") || return 1
  fm_pr_private_file_secure "$FM_CONTROL_RECOVERY_RECEIPT" 600 || return 1
  printf '%s' "$FM_CONTROL_RECOVERY_PLAN" | jq '. + {phase:"prepared"}' > "$FM_CONTROL_RECOVERY_RECEIPT" || return 1
  tmp=$(umask 077; mktemp "$state/.fm-control-recovery.XXXXXX") || return 1
  if ! fm_pr_private_file_secure "$tmp" 600; then rm -f -- "$tmp"; return 1; fi
  printf 'control_recovery_token=%s\n' "$FM_CONTROL_RECOVERY_TOKEN" > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    key=${line%%=*}
    case "$key" in
      control_recovery_token) continue ;;
      window|endpoint_task_id|worktree|backend|herdr_session|herdr_workspace_id|herdr_tab_id|herdr_pane_id|busy_gen|spawn_gen)
        value=$(fm_meta_get "$FM_CONTROL_RECOVERY_CANDIDATE_SNAPSHOT" "$key")
        [ -z "$value" ] || printf '%s=%s\n' "$key" "$value" >> "$tmp"
        ;;
      *) printf '%s\n' "$line" >> "$tmp" ;;
    esac
  done < "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT"
  if ! fm_backend_validate_task_endpoint "$tmp" "$task" \
     || [ -L "$meta" ] || [ "$(fm_pr_file_link_count "$meta")" != 1 ] \
     || ! cmp -s "$meta" "$FM_CONTROL_RECOVERY_CURRENT_SNAPSHOT" \
     || ! mv -f -- "$tmp" "$meta"; then
    rm -f -- "$tmp"
    return 1
  fi
  # A prepared receipt plus the metadata token proves that binding occurred
  # even if interruption prevents this phase update. Retrying never restarts a
  # replacement merely because the initiating shell wait ended.
  fm_control_recovery_receipt_phase bound
}

fm_control_recovery_read_receipt() {  # <state> <task> <home> <approval>
  local state=$1 task=$2 home=$3 token=$4 file record bound_home
  case "$token" in *[!0-9a-f]*) return 1 ;; esac
  [ "${#token}" = 64 ] || return 1
  file="$state/$task.control-recovery/$token/receipt.json"
  [ ! -L "$state/$task.control-recovery" ] && [ ! -L "${file%/*}" ] \
    && [ -f "$file" ] && [ ! -L "$file" ] && [ "$(fm_pr_file_link_count "$file")" = 1 ] || return 1
  record=$(jq -ce --arg task "$task" --arg token "$token" '
    select(.schema == "fm-control-recovery-plan.v1" and .approval == $token
      and .bindings.task == $task and (.bindings.home | type) == "string"
      and (.phase == "prepared" or .phase == "bound" or .phase == "complete"))
  ' "$file") || return 1
  bound_home=$(printf '%s' "$record" | jq -er '.bindings.home | select(length > 0 and (explode | all(. >= 32 and . != 127)))') || return 1
  # Receipts retain their original bound bytes; a path spelling change
  # must not strand them or authorize a different physical home.
  fm_platform_same_directory "$bound_home" "$home" || return 1
  printf '%s\n' "$record"
}

fm_control_recovery_receipt_phase() {  # <phase>
  local phase=$1 tmp
  [ -n "$FM_CONTROL_RECOVERY_RECEIPT" ] || return 1
  tmp=$(umask 077; mktemp "${FM_CONTROL_RECOVERY_RECEIPT%/*}/.receipt.XXXXXX") || return 1
  if fm_pr_private_file_secure "$tmp" 600 \
     && jq --arg phase "$phase" '.phase=$phase' "$FM_CONTROL_RECOVERY_RECEIPT" > "$tmp" \
     && mv -f -- "$tmp" "$FM_CONTROL_RECOVERY_RECEIPT"; then return 0; fi
  rm -f -- "$tmp"
  return 1
}

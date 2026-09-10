#!/usr/bin/env bash
# Copilot implementation of the closed harness interface; no lifecycle imports.

fm_harness_copilot_describe() {
  local capability=${1:-}
  shift
  case "$capability" in
    kind-supported|busy-kind|remote-supported|launch-template)
      _fm_harness_argument_count "copilot $capability" 1 "$#" || return 2 ;;
    effort-option|native-effort)
      _fm_harness_argument_count "copilot $capability" 2 "$#" || return 2 ;;
    *) _fm_harness_argument_count "copilot $capability" 0 "$#" || return 2 ;;
  esac
  case "$capability" in
    control-supported|kind-supported|busy-kind) return 0 ;;
    remote-supported) [ "${1:-}" = launch ] ;;
    interrupt-key) printf C-c ;;
    interrupt-repeat) printf 1 ;;
    interrupt-clear-key) ;;
    interrupt-ack-source) printf none ;;
    exit-command) printf /exit ;;
    supervision) printf 'autoarm\n' ;;
    busy-source) printf copilot-hook ;;
    model-option) printf -- --model ;;
    effort-option)
      case "${2:-}" in low|medium|high|xhigh|max) printf -- --effort ;; esac
      ;;
    native-effort) [ "${2:-}" != ultra ] ;;
    profile) printf '%s' '{"bootstrap":true,"efforts":["low","medium","high","xhigh","max"],"nativeEffortPrefix":null}' ;;
    launch-template)
      # shellcheck disable=SC2016 # Expansion happens in the launched pane.
      printf '%s' 'env -u CLAUDECODE -u PI_CODING_AGENT -u GROK_AGENT -u FM_PI_HARNESS -u CURSOR_AGENT -u CURSOR_INVOKED_AS __COPILOTBIN__ --allow-all --no-ask-user __MODELFLAG____EFFORTFLAG__--interactive "$(__OPINPUT__ encode launch-brief < __BRIEF__)"'
      ;;
    launch-environment) printf '%s' 'env -u CURSOR_AGENT -u CURSOR_INVOKED_AS -u GEMINI_CLI' ;;
    *) _fm_harness_error "copilot has no capability: $capability" ;;
  esac
}

_FM_COPILOT_WINPID=
_FM_COPILOT_WINPID_RC=

fm_harness_copilot_identify() {
  local stage=${1:-} pid session comm args argv0 name
  shift
  case "$stage" in
    native-pid|command|interpreter)
      _fm_harness_argument_count "copilot $stage" 1 "$#" || return 2 ;;
    *) _fm_harness_argument_count "copilot $stage" 0 "$#" || return 2 ;;
  esac
  case "$stage" in
    native-pid)
      pid=${1:-}
      case "$pid" in ''|*[!0-9]*) return 1 ;; esac
      if [ "$pid" = "${_FM_COPILOT_WINPID:-}" ]; then
        return "${_FM_COPILOT_WINPID_RC:-1}"
      fi
      _FM_COPILOT_WINPID=$pid
      _FM_COPILOT_WINPID_RC=1
      if fm_platform_windows_pid_matches "$pid" copilot.exe; then
        _FM_COPILOT_WINPID_RC=0
        return 0
      fi
      return 1
      ;;
    loader)
      pid=${COPILOT_LOADER_PID:-}
      session=${COPILOT_AGENT_SESSION_ID:-}
      [ "${COPILOT_CLI:-}" = 1 ] || return 1
      case "$pid" in ''|*[!0-9]*) return 1 ;; esac
      case "$session" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
      if kill -0 "$pid" 2>/dev/null; then
        comm=$(fm_platform_process_comm "$pid") || return 1
        args=$(fm_platform_process_args "$pid")
        argv0=${args%% *}
        name=
        case "$(basename -- "$comm")" in copilot|copilot.exe) name=copilot ;; esac
        if [ -z "$name" ]; then
          name=$(fm_harness_path_name "$comm" 2>/dev/null || \
            fm_harness_path_name "$argv0" 2>/dev/null || true)
        fi
        case "$name" in copilot|copilot.exe) ;; *) return 1 ;; esac
      else
        fm_harness_copilot_identify native-pid "$pid" || return 1
      fi
      printf '%s\n' "$pid"
      ;;
    command)
      case "${1:-}" in copilot|copilot.exe) printf 'copilot\n' ;; *) return 1 ;; esac
      ;;
    interpreter)
      case "${1:-}" in */copilot|*/copilot.exe|*\\copilot.exe*) printf 'copilot\n' ;; *) return 1 ;; esac
      ;;
    *) _fm_harness_error "copilot has no identity stage: $stage" ;;
  esac
}

# shellcheck disable=SC2034 # Prepared fields are consumed by the lifecycle caller.
fm_harness_copilot_prepare_launch() {  # <kind> <template-or-raw-command>
  FM_HARNESS_LAUNCH=${2:-}
  FM_HARNESS_EXECUTABLE=$(fm_platform_resolve_executable copilot) || {
    echo "error: copilot executable not found on PATH; install GitHub Copilot CLI or select a different verified harness" >&2
    return 1
  }
  FM_HARNESS_EXECUTABLE_TOKEN=__COPILOTBIN__
}

fm_harness_copilot_owned_wiring() {
  local operation=${1:-} wt state id root gen turnend busy_cmd hook_ps ps_cmd
  local j_submit_bash j_stop_bash j_end_bash j_submit_ps j_stop_ps j_end_ps
  shift
  case "$operation" in
    paths)
      _fm_harness_argument_count 'copilot paths' 3 "$#" || return 2
      wt=${1:-} state=${2:-} id=${3:-}
      [ -n "$state" ] && [ -n "$id" ] || { _fm_harness_error "copilot paths require state and id"; return 2; }
      [ -z "$wt" ] || fm_harness_copilot_owned_wiring hook-path "$wt" "$id"
      fm_harness_copilot_owned_wiring submission-marker "$state" "$id"
      printf '\n'
      ;;
    hook-path)
      _fm_harness_argument_count 'copilot hook-path' 2 "$#" || return 2
      printf '%s/.github/hooks/zz-firstmate-%s.json\n' "$1" "$2"
      ;;
    exclusion)
      _fm_harness_argument_count 'copilot exclusion' 0 "$#" || return 2
      printf '%s' '.github/hooks/zz-firstmate-*.json'
      ;;
    submission-marker)
      _fm_harness_argument_count 'copilot submission-marker' 2 "$#" || return 2
      [ -n "${1:-}" ] && [ -n "${2:-}" ] || { _fm_harness_error "copilot submission marker requires state and id"; return 2; }
      printf '%s/%s.copilot-prompt-submitted' "$1" "$2"
      ;;
    parent-environment)
      _fm_harness_argument_count 'copilot parent-environment' 3 "$#" || return 2
      state=$1 id=$2 gen=$3
      printf 'FM_COPILOT_PARENT_STATE=%s FM_COPILOT_PARENT_TASK_ID=%s FM_COPILOT_PARENT_BUSY_GEN=%s' \
        "$(fm_platform_shell_quote "$state")" "$(fm_platform_shell_quote "$id")" "$(fm_platform_shell_quote "$gen")"
      ;;
    inherited-environment)
      _fm_harness_argument_count 'copilot inherited-environment' 0 "$#" || return 2
      if [ -n "${FM_COPILOT_PARENT_STATE:-}${FM_COPILOT_PARENT_TASK_ID:-}${FM_COPILOT_PARENT_BUSY_GEN:-}" ]; then
        printf '%s' 'env -u FM_COPILOT_PARENT_STATE -u FM_COPILOT_PARENT_TASK_ID -u FM_COPILOT_PARENT_BUSY_GEN'
      fi
      ;;
    render)
      _fm_harness_argument_count 'copilot render' 5 "$#" || return 2
      root=$1 state=$2 id=$3 gen=$4 turnend=$5
      busy_cmd="bash $(fm_platform_shell_quote "$root/bin/fm-ghcp-hook.sh") worker-event $(fm_platform_shell_quote "$state") $(fm_platform_shell_quote "$id") $(fm_platform_shell_quote "$gen")"
      hook_ps="$root/bin/fm-ghcp-hook.ps1"
      if command -v cygpath >/dev/null 2>&1; then
        hook_ps=$(cygpath -w "$hook_ps" 2>/dev/null || printf '%s' "$hook_ps")
      fi
      ps_cmd="& $(fm_platform_powershell_quote "$hook_ps") worker-event $(fm_platform_powershell_quote "$state") $(fm_platform_powershell_quote "$id") $(fm_platform_powershell_quote "$gen")"
      j_submit_bash=$(fm_platform_json_escape "$busy_cmd busy user-prompt-submitted -")
      j_stop_bash=$(fm_platform_json_escape "$busy_cmd idle agent-stop $(fm_platform_shell_quote "$turnend")")
      j_end_bash=$(fm_platform_json_escape "$busy_cmd idle session-end $(fm_platform_shell_quote "$turnend")")
      j_submit_ps=$(fm_platform_json_escape "$ps_cmd busy user-prompt-submitted -")
      j_stop_ps=$(fm_platform_json_escape "$ps_cmd idle agent-stop $(fm_platform_powershell_quote "$turnend")")
      j_end_ps=$(fm_platform_json_escape "$ps_cmd idle session-end $(fm_platform_powershell_quote "$turnend")")
      cat <<EOF
{"version":1,"hooks":{"userPromptSubmitted":[{"type":"command","bash":"$j_submit_bash","powershell":"$j_submit_ps","timeoutSec":10}],"agentStop":[{"type":"command","bash":"$j_stop_bash","powershell":"$j_stop_ps","timeoutSec":10}],"sessionEnd":[{"type":"command","bash":"$j_end_bash","powershell":"$j_end_ps","timeoutSec":10}]}}
EOF
      ;;
    *) _fm_harness_error "copilot has no wiring operation: $operation" ;;
  esac
}

#!/usr/bin/env bash
# Pi-only implementation. pi-signed and OMP deliberately retain legacy dispatch.

fm_harness_pi_describe() {
  local capability=${1:-}
  shift
  case "$capability" in
    kind-supported|busy-kind|remote-supported|launch-template)
      _fm_harness_argument_count "pi $capability" 1 "$#" || return 2 ;;
    effort-option|native-effort)
      _fm_harness_argument_count "pi $capability" 2 "$#" || return 2 ;;
    *) _fm_harness_argument_count "pi $capability" 0 "$#" || return 2 ;;
  esac
  case "$capability" in
    control-supported|kind-supported) return 0 ;;
    remote-supported) case "${1:-}" in launch|relaunch) return 0 ;; *) return 1 ;; esac ;;
    busy-kind) [ "${1:-}" != secondmate ] ;;
    interrupt-key) printf Escape ;;
    interrupt-repeat) printf 1 ;;
    interrupt-clear-key) ;;
    interrupt-ack-source) printf none ;;
    exit-command) printf /quit ;;
    supervision) printf 'extension\n' ;;
    busy-source) printf pi-ext ;;
    model-option) printf -- --model ;;
    effort-option)
      case "${2:-}" in
        ultra)
          fm_harness_pi_describe native-effort "${1:-}" ultra || {
            echo "error: ultra effort requires pi or pi-signed with an explicit codex-native/<model> model" >&2
            return 1
          }
          printf -- --codex-effort
          ;;
        low|medium|high|xhigh|max) printf -- --thinking ;;
      esac
      ;;
    native-effort)
      [ "${2:-}" = ultra ] || return 0
      case "${1:-}" in codex-native/?*) return 0 ;; esac
      return 1
      ;;
    profile) printf '%s' '{"bootstrap":true,"efforts":["low","medium","high","xhigh","max"],"nativeEffortPrefix":"codex-native/"}' ;;
    launch-template)
      # shellcheck disable=SC2016 # Expansion happens in the launched pane.
      {
        printf '%s' '__PIBIN____PITUIMODE__'
        if [ "${1:-ship}" = secondmate ]; then
          printf '%s' ' __MODELFLAG____EFFORTFLAG__-e __PITURNEND__ -e __PIWATCH__ "$(__OPINPUT__ encode launch-brief < __BRIEF__)"'
        else
          printf '%s' ' __MODELFLAG____EFFORTFLAG__-e __PIEXT__ "$(__OPINPUT__ encode launch-brief < __BRIEF__)"'
        fi
      }
      ;;
    launch-environment) printf '%s' 'env -u CURSOR_AGENT -u CURSOR_INVOKED_AS -u GEMINI_CLI -u COPILOT_CLI -u COPILOT_AGENT_SESSION_ID -u COPILOT_LOADER_PID' ;;
    *) _fm_harness_error "pi has no capability: $capability" ;;
  esac
}

fm_harness_pi_identify() {
  local stage=${1:-}
  shift
  case "$stage" in
    command|interpreter) _fm_harness_argument_count "pi $stage" 1 "$#" || return 2 ;;
    *) _fm_harness_argument_count "pi $stage" 0 "$#" || return 2 ;;
  esac
  case "$stage" in
    marker)
      [ "${PI_CODING_AGENT:-}" = true ] && [ "${FM_PI_HARNESS:-}" != pi-signed ] || return 1
      printf 'pi\n'
      ;;
    command)
      [ "${1:-}" = pi ] || return 1
      printf 'pi\n'
      ;;
    interpreter)
      case "${1:-}" in *" pi "*|*/pi) printf 'pi\n' ;; *) return 1 ;; esac
      ;;
    *) _fm_harness_error "pi has no identity stage: $stage" ;;
  esac
}

fm_harness_pi_prepare_launch() {  # <kind> <template-or-raw-command>
  local tui_mode=
  FM_HARNESS_LAUNCH=${2:-}
  FM_HARNESS_EXECUTABLE=$(fm_platform_resolve_executable pi) || {
    echo "error: pi executable not found on PATH; install it or select a different verified harness" >&2
    return 1
  }
  if fm_platform_command_supports_option "$FM_HARNESS_EXECUTABLE" --tui-mode; then
    tui_mode=' --tui-mode regular'
  fi
  FM_HARNESS_LAUNCH=${FM_HARNESS_LAUNCH//__PITUIMODE__/$tui_mode}
  FM_HARNESS_LAUNCH="FM_PI_HARNESS=pi $FM_HARNESS_LAUNCH"
  # shellcheck disable=SC2034 # Prepared field consumed by the lifecycle caller.
  FM_HARNESS_EXECUTABLE_TOKEN=__PIBIN__
}

fm_harness_pi_owned_wiring() {
  local operation=${1:-} root state id gen turnend
  shift
  case "$operation" in
    paths)
      _fm_harness_argument_count 'pi paths' 3 "$#" || return 2
      [ -n "${2:-}" ] && [ -n "${3:-}" ] || { _fm_harness_error "pi paths require state and id"; return 2; }
      printf '%s/%s.pi-ext.ts\n' "$2" "$3"
      ;;
    primary-turnend|primary-watch)
      _fm_harness_argument_count "pi $operation" 1 "$#" || return 2
      case "$operation" in
        primary-turnend) printf '%s/.pi/extensions/fm-primary-turnend-guard.ts\n' "$1" ;;
        primary-watch) printf '%s/.pi/extensions/fm-primary-pi-watch.ts\n' "$1" ;;
      esac
      ;;
    render)
      _fm_harness_argument_count 'pi render' 5 "$#" || return 2
      root=$(fm_platform_json_escape "$1") state=$(fm_platform_json_escape "$2")
      id=$(fm_platform_json_escape "$3") gen=$(fm_platform_json_escape "$4")
      turnend=$(fm_platform_json_escape "$5")
      cat <<EOF
// Firstmate semantic busy-state events + turn-end notification; written by
// fm-spawn under the contract owned by bin/fm-busy-lib.sh.
// Semantic state: "agent_start" -> busy when a low-level agent run begins;
// "agent_settled" -> idle only when ctx.isIdle() confirms Pi will not
// continue automatically - auto-retries, auto-compaction retries, tool
// loops, and queued continuations all keep the run un-settled, and a settle
// that raced another extension's fresh run keeps state busy via isIdle().
// "turn_end" fires at every inner turn boundary (one LLM response plus its
// tool calls) and stays a wake NOTIFICATION touch for the watcher, never
// current-state truth.
import { execFile } from "node:child_process";
const busyEvent = (state: string, event: string) =>
  new Promise<void>((resolve) => {
    execFile("bash", ["$root/bin/fm-busy-event.sh",
      "apply", "$state", "$id", state,
      "--gen", "$gen", "--source", "pi-ext", "--event", event,
    ], () => resolve());
  });
export default function (pi: any) {
  pi.on("agent_start", () => busyEvent("busy", "agent-start"));
  pi.on("agent_settled", (_event: any, ctx: any) => {
    if (ctx && typeof ctx.isIdle === "function" && !ctx.isIdle()) return;
    return busyEvent("idle", "agent-settled");
  });
  pi.on("turn_end", () => execFile("touch", ["$turnend"]));
  // A native harness can make progress inside one Pi turn. This separate
  // marker prevents false wedge alarms without fabricating a completed turn.
  let lastProgress = 0;
  pi.events?.on?.("codex-native:progress", () => {
    const now = Date.now();
    if (now - lastProgress < 1000) return;
    lastProgress = now;
    execFile("$root/bin/fm-busy-event.sh", [
      "progress", "$state", "$id", "--gen", "$gen",
    ]);
  });
}
EOF
      ;;
    *) _fm_harness_error "pi has no wiring operation: $operation" ;;
  esac
}

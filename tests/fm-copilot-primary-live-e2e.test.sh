#!/usr/bin/env bash
# Native Windows Copilot supervision through the real hook registration and
# real PowerShell/Git Bash transports. A local deterministic provider spends no
# model tokens. Only the watcher body, wake drain, and startup digest are fixture
# ports; lock acquisition, ownership, arm confirmation, Stop and notification
# policies remain real. All Herdr operations use a guarded non-default lab.
# FM_COPILOT_PRIMARY_LIVE_E2E=1 makes unavailable prerequisites a hard failure.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate default-on FM_COPILOT_PRIMARY_LIVE_E2E herdr copilot node jq cygpath

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *)
    [ "${FM_COPILOT_PRIMARY_LIVE_E2E:-${FM_LIVE:-0}}" != 1 ] || fail "Windows is required for this native Copilot guard"
    printf 'skip: live: Windows is required for the native Copilot primary guard\n'
    exit 0
    ;;
esac
if [ "${HERDR_ENV:-}" != 1 ]; then
  [ "${FM_COPILOT_PRIMARY_LIVE_E2E:-${FM_LIVE:-0}}" != 1 ] || fail "a running Herdr session is required for the lab tripwire"
  printf 'skip: live: Herdr caller context is required for the isolated primary guard\n'
  exit 0
fi

TMP_ROOT=$(fm_test_tmproot fm-copilot-primary-live)
COPILOT_BIN=${FM_COPILOT_BIN:-$(command -v copilot)}
FM_COPILOT_TEST_ROOT=$(cygpath -w "$ROOT") || fail "could not convert test code root"
FM_COPILOT_TEST_LAB=$(cygpath -w "$TMP_ROOT") || fail "could not convert test lab root"
FM_COPILOT_TEST_BASH=$(cygpath -w "$(command -v bash)") || fail "could not resolve native Git Bash"
FM_COPILOT_TEST_BIN=$(cygpath -w "$COPILOT_BIN") || fail "could not resolve native Copilot"
export FM_COPILOT_TEST_ROOT FM_COPILOT_TEST_LAB FM_COPILOT_TEST_BASH FM_COPILOT_TEST_BIN
node "$ROOT/tests/fm-copilot-primary-live-e2e.mjs" || fail "native Copilot primary supervision failed"

#!/usr/bin/env bash
# Opt-in native Copilot management proof with a local deterministic provider.
# Uses only a guarded non-default Herdr lab and a synthetic home/profile. No
# credentials, running fleet, live lease, or project operation is involved.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_live_gate opt-in FM_COPILOT_MANAGEMENT_LIVE_E2E herdr copilot node jq cygpath
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) fail "native Windows is required for the Copilot management guard" ;;
esac
[ "${HERDR_ENV:-}" = 1 ] || fail "run from a Herdr caller so the isolated lab has a default-session tripwire"
TMP_ROOT=$(fm_test_tmproot fm-copilot-management-live)
FM_COPILOT_TEST_ROOT=$(cygpath -w "$ROOT") || exit 1
FM_COPILOT_TEST_LAB=$(cygpath -w "$TMP_ROOT") || exit 1
FM_COPILOT_TEST_BASH=$(cygpath -w "$(command -v bash)") || exit 1
FM_COPILOT_TEST_BIN=$(cygpath -w "${FM_COPILOT_BIN:-$(command -v copilot)}") || exit 1
export FM_COPILOT_TEST_ROOT FM_COPILOT_TEST_LAB FM_COPILOT_TEST_BASH FM_COPILOT_TEST_BIN
node "$ROOT/tests/fm-copilot-management-live-e2e.mjs" || fail "native Copilot management contract failed"

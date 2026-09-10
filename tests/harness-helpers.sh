#!/usr/bin/env bash
# Install the tracked dependency closure in an isolated repository-shaped root.
# shellcheck source=tests/process-helpers.sh
. "$ROOT/tests/process-helpers.sh"

fm_test_install_harness_modules() {
  fm_test_install_process_module "$1" || return 1
  mkdir -p "$1/bin/harnesses" || return 1
  cp "$ROOT/bin/fm-harness-lib.sh" "$1/bin/" || return 1
  cp "$ROOT/bin/harnesses/copilot.sh" "$ROOT/bin/harnesses/pi.sh" "$1/bin/harnesses/"
}

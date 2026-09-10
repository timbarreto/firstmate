#!/usr/bin/env bash
# Install shared process dependencies in a repository-shaped isolated fixture.
fm_test_install_process_module() {
  mkdir -p "$1/bin/platform" || return 1
  cp "$ROOT/bin/fm-platform-process-lib.sh" "$1/bin/" || return 1
  cp "$ROOT/bin/platform/process.mjs" "$ROOT/bin/platform/process.d.mts" \
    "$ROOT/bin/platform/windows-process.ps1" "$1/bin/platform/"
}

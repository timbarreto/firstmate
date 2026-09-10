#!/usr/bin/env bash
# Install the complete tracked native private-path dependency in a fixture root.
fm_test_install_private_paths() {
  mkdir -p "$1/bin/platform" || return 1
  cp "$ROOT/bin/fm-private-path-lib.sh" "$1/bin/" || return 1
  cp "$ROOT/bin/platform/windows-private-path.ps1" "$1/bin/platform/"
}

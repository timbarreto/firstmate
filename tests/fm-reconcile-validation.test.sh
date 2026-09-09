#!/usr/bin/env bash
# Portable behavior checks for bounded reconciliation plans and case selection.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "not ok - node is required for reconciliation validation tests" >&2; exit 1; }
exec node --test "$ROOT/tests/fm-reconcile-validation.test.mjs"

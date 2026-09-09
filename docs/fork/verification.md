# Fork compatibility verification

## CI ownership

[Fork CI](../../.github/workflows/fork-ci.yml) owns the Windows updater, focused Windows reconciliation, and pinned package-compatibility jobs.
Their expanded check names remain `Windows self-update entry point`, `Windows reconciliation (core)`, `Windows reconciliation (copilot-launch)`, `Windows reconciliation (legacy-rollback)`, and `Harness package compatibility`.
The workflow owns exact subjects, named-case selectors, package pins, timeouts, and live-test gates.
The non-credentialed package job detects package API drift and missing runner CLIs without vendor credentials.

[Shared CI](../../.github/workflows/ci.yml) retains lint, coverage, portable parallel and serial shards, real Herdr, timing aggregation, stock macOS Bash, and repository invariants.
The two workflows together produce 18 automatic checks, with one producer for each check name.
Both use the same main-branch push and pull-request triggers and read-only permissions, with workflow-qualified concurrency groups so neither cancels the other.
The [Windows Herdr experiment](../../.github/workflows/windows-herdr-spike.yml) remains manual.

## Repeatable checks

Run `bin/fm-lint-workflows.sh` to validate all workflow files with pinned actionlint, including the fork workflow.
Run `FM_TEST_ONLY=test_fork_workflow_selects_its_contracts bin/fm-test-run.sh tests/fm-test-run.test.sh` to exercise the fork workflow's changed-test routing.
The mapping selects the lint/runner contract family and every relocated subject without selecting unrelated live families.
Use `bin/fm-test-run.sh --list --changed --base <pr-base>` to inspect the complete change selection, and `bin/fm-test-run.sh --check-coverage` to verify the lane partition.
The runner header and [contributor guide](../../CONTRIBUTING.md#development) own invocation details and local validation policy.

Before moving jobs, inspect current branch rules and required check names without changing settings.
Compare the complete job definitions with the PR base, including permissions, matrices, actions, gates, artifacts, and dependencies, then verify check producers on the exact published head.
A previous head's green checks, a local mock, or an optional skip is not proof that the new head passed native-platform or package checks.
Keep commands, timings, exact base/head identifiers, and deferred-check outcomes in PR or session evidence rather than this stable ownership guide.

Live vendor checks remain separately gated and require explicit authorization in controlled fixtures.
[Runtime backend verification](../verification/runtime-backends.md) owns empirical backend evidence; moving CI jobs does not establish new vendor or native-platform guarantees.

## Catalog compatibility

[Fork architecture](architecture.md) owns the registration seam and its integration patches.
Run `bin/fm-test-run.sh tests/fm-test-catalog.test.sh` for strict metadata, override, dependency, ordered-map, lightweight-listing, and proof-admission contracts.
The existing runner and isolation-proof suites retain scheduler, named-case, JSON, reference-selection, and proof integration coverage.

Before adding new registrations during a metadata extraction, compare old and new listing, family, scheduled-order, lane, and JSON results on identical inventory and metadata inputs.
Include every family's expected gate-skip class; JSON fixtures covering only ungated families cannot establish gate compatibility.
Measure repeated successful lookups as well as parser counts; in-process string matching can still make selection expensive.
After registering new tests, re-run the coverage guard and inspect the five serial shards; legitimate rebalancing is distinct from an identical-input mismatch.
Keep the immutable comparison inputs and exact outputs in session or PR evidence.
Broad runner coverage remains in portable CI, stock Bash parsing remains in the macOS job, and native worker privacy remains in Windows coverage.

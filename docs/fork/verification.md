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

## Serial runtime and stalled fixtures

[Portable shard verification](../fm-test-portable-shards.md) owns duration-hint refresh and balance evidence.
Exclude gated skips from timing samples, preserve unmeasured native-platform hints, and verify the complete five-shard partition after updating fork overrides.
Balanced estimates do not prove that a shutdown race or other intermittent stall has been resolved.

`tests/fm-remote-job.test.sh` bounds the replacement-worker shutdown wait and emits its phase, process snapshot, and recent worker output on failure.
`tests/fm-remote-job-wait.test.sh` exercises that wait with a real child that ignores TERM and verifies bounded failure and cleanup.
The full remote-job suite remains the Linux worker integration check; the focused fixture-wait regression does not establish why a real worker stopped responding.

## Private-path compatibility

Run `bin/fm-test-run.sh tests/fm-private-path.test.sh` for native ACL policy fixtures, public structural refusals, path-data transport, bounded invocation counts, and missing-dependency failures.
The native fixtures cover allowed and foreign Allow principals, Deny entries, null DACLs, FullControl differences, hidden paths, directory inheritance, reparse points, mutation, and replacement.
They run in the existing Windows reconciliation core job; POSIX mode checks run in portable CI and explicitly skip on synthetic Windows filesystems.
Transport fakes establish operation counts and data handling, not native ACL behavior.

The PR publication, X-mode, runner, and Herdr suites retain their existing integration cases.
Windows core coverage also selects the existing PR publication case through the shared named-case runner, without changing the full suite's order.
Use `FM_TEST_ONLY=test_jobs_parallel_scheduler_and_failure_propagation bin/fm-test-run.sh tests/fm-test-run.test.sh` to exercise real runner worker creation through the copied dependency layout.
Stock Bash parsing remains owned by macOS CI, and native execution parses the platform PowerShell file in Windows coverage.
Keep before/after characterization outputs and exact platform limitations in PR evidence.

## Process and transport compatibility

Run `bin/fm-test-run.sh tests/fm-platform-process.test.sh` for compatibility exports, process facts, missing-dependency refusals, call counts, and tracked clone/worktree layouts.
The same suite exercises real native PID translation, graceful TERM, owned descendant termination, foreign-process preservation, and literal PowerShell/Bash transport on Windows.
Only task-owned fixture processes are started or stopped; these cases do not exercise a live vendor or Firstmate fleet.
The Windows reconciliation core job owns native coverage, while the pinned package job runs the shared contracts and strict Pi type checks.

Run `bin/fm-lint.sh tests/fm-platform-process.test.sh bin/fm-platform-process-lib.sh bin/backends/herdr.sh` for focused source-aware lint; the lint owner documents mode selection and test/production source boundaries.

`tests/fm-pi-primary-types.test.sh` compiles the copied repository-shaped extensions and adjacent module declarations against the installed Pi package.
The existing Pi watch and branch suites retain their full case order and additionally support the shared named-case selector in `tests/lib.sh`.
Use their generation/replacement, lock-ownership, process-exit cleanup, OpenCode package-boundary, and stock Pi consumer cases for targeted compatibility work.
The native Copilot identity, nonpilot session ancestry, and Herdr Treehouse suites retain their existing executable coverage.

Run `FM_TEST_ONLY=test_process_modules_select_all_consumers bin/fm-test-run.sh tests/fm-test-run.test.sh` to check routing for the platform implementation, declarations, compatibility wrappers, and fixture helper.
The loader and runner still own coverage and scheduling independently; registering this suite does not expand concurrent admission.
Full portable regression, macOS stock Bash, and real Herdr coverage remain with their existing shared-CI owners.
Neither deterministic process fixtures nor package type checks establish a changed vendor hook or extension-event assumption.

## Pilot harness compatibility

Run `bin/fm-test-run.sh tests/fm-harness-contract.test.sh` for the closed registry, shared caller interface, literal launch arguments, staged identity, owned paths, supervision overrides, and explicit malformed-call or adapter-load failures.
The suite executes the generated Pi artifact to verify literal data transport, settlement gating, notification-only turn ends, and throttled generation-bound progress.
The existing Copilot and process suites retain native loader verification, marker precedence, foreign-process rejection, and per-process query/cache contracts.

Run `bin/fm-lint.sh bin/fm-harness-lib.sh bin/harnesses/copilot.sh bin/harnesses/pi.sh tests/fm-harness-contract.test.sh` for source-aware interface and implementation lint.
Explicit lint roots preserve CI's cross-file analysis; ordinary branch-local lint does not substitute for that check.
The focused adapter suite is registered in the fork catalog without adding it to any concurrent proof admission.

The spawn, busy-wiring, bootstrap, and control-relaunch suites exercise the migrated lifecycle through existing executable entrypoints.
All four support the shared named-case selector without changing their unfiltered case order.
Use their pilot worker/secondmate, native-effort refusal, raw-command, environment-scrubbing, stale-generation, retirement-before-replacement, and failed-launch cases for focused work.
Bootstrap cases retain malformed/null-field behavior, narrower verified support, and aggregate diagnostic ordering; representative Claude, signed Pi, OMP, and other nonpilot cases retain legacy coverage.
Pi watch, primary types, branch, native Codex, and Windows shell suites remain the extension/package integration owners.

Full portable regression, real Herdr, stock macOS Bash, and pinned non-credentialed package coverage stay with the existing CI producers.
No live fleet operation, vendor prompt, workflow gate change, or remote-doctor pin change is needed for this extraction.

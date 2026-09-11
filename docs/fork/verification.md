# Fork compatibility verification

## CI ownership

[Fork CI](../../.github/workflows/fork-ci.yml) owns the Windows updater, focused Windows reconciliation, and pinned package-compatibility jobs.
Their expanded check names remain `Windows self-update entry point`, `Windows reconciliation (core)`, `Windows reconciliation (copilot-launch)`, `Windows reconciliation (legacy-rollback)`, and `Harness package compatibility`.
The workflow owns exact subjects, named-case selectors, package pins, timeouts, and live-test gates.
The non-credentialed package job detects package API drift and missing runner CLIs without vendor credentials.

[Shared CI](../../.github/workflows/ci.yml) retains lint, coverage, portable parallel and serial shards, real Herdr, timing aggregation, stock macOS Bash, and repository invariants.
The real-Herdr job also installs the pinned Pi prerequisite for the non-credentialed agent exit-to-shell regression; an absent Pi is a job failure, not accepted missing coverage.
The two workflows together produce 18 automatic checks, with one producer for each check name.
Both use the same main-branch push and pull-request triggers and read-only permissions, with workflow-qualified concurrency groups so neither cancels the other.
The [Windows Herdr experiment](../../.github/workflows/windows-herdr-spike.yml) remains manual.
These owners apply to every compatibility section below; focused local cases never replace the complete exact-head CI results.

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

## Herdr cleanup compatibility

The backend and teardown suites support the shared named-case selector without changing full-suite order.
Use `test_projection_close_allows_stale_active_tab_without_foreground_client` in `tests/fm-backend-herdr.test.sh` and `test_herdr_projection_teardown_cleans_detached_without_safe_parent` in `tests/fm-teardown.test.sh` for the composed detached-focus boundary.
The same suites retain exact-parent handoff, quiet deferral, unknown attachment, and late-attachment cases.
The presentation E2E suite performs real isolated Herdr mutations; its handoff and deferral fixtures explicitly inject a live-viewer response and are not proof of an actual attached client.
Default detached-client and agent exit-to-shell coverage remains owned by the real-Herdr CI job.
The exit-to-shell fixture waits for Pi's `session_start` readiness marker as well as Herdr's idle registration before submitting `/quit`.

## Catalog compatibility

[Fork architecture](architecture.md) owns the registration seam and its integration patches.
Run `bin/fm-test-run.sh tests/fm-test-catalog.test.sh` for strict metadata, override, dependency, ordered-map, lightweight-listing, and proof-admission contracts.
The existing runner and isolation-proof suites retain scheduler, named-case, JSON, reference-selection, and proof integration coverage.
Shared backend-classifier changes select both backend families, Orca, gated live identity checks, and the fork's native Treehouse contract; selection does not grant concurrent or live execution.
Run `FM_TEST_ONLY=test_changed_shared_fixtures_select_consumers bin/fm-test-run.sh tests/fm-test-run.test.sh` to verify that shared fixtures retain both curated mappings and reference-derived consumer families.
A curated fixture remains mapped without direct references; a fixture with neither a curated mapping nor consumers is still refused.

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
`tests/fm-lint-inventory.test.sh` keeps the complete no-external-sources exclusion audit in the serial lanes, outside the fast lint-contract suite's parallel-lane budget.
Its catalog registration does not grant concurrent admission or reduce the audited root set.

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
`tests/fm-procevent-stop-proof.test.sh` owns named first-signal refusal and same-stop escalation cases in portable serial CI.
Its PGID fault injection targets the fork's Perl `getpgrp` query, while birth-identity injection remains on the existing `ps` boundary.

Run `bin/fm-lint.sh tests/fm-platform-process.test.sh bin/fm-platform-process-lib.sh bin/backends/herdr.sh` for focused source-aware lint; the lint owner documents mode selection and test/production source boundaries.

`tests/fm-pi-primary-types.test.sh` compiles the copied repository-shaped extensions and adjacent module declarations against the installed Pi package.
The existing Pi watch and branch suites retain their full case order and additionally support the shared named-case selector in `tests/lib.sh`.
Use their generation/replacement, lock-ownership, process-exit cleanup, OpenCode package-boundary, and stock Pi consumer cases for targeted compatibility work.
The native Copilot identity, nonpilot session ancestry, and Herdr Treehouse suites retain their existing executable coverage.

Run `FM_TEST_ONLY=test_process_modules_select_all_consumers bin/fm-test-run.sh tests/fm-test-run.test.sh` to check routing for the platform implementation, declarations, compatibility wrappers, and fixture helper.
The loader and runner still own coverage and scheduling independently; registering this suite does not expand concurrent admission.
Neither deterministic process fixtures nor package type checks establish a changed vendor hook or extension-event assumption.

## Pilot harness compatibility

Run `bin/fm-test-run.sh tests/fm-harness-contract.test.sh` for the closed registry, shared caller interface, literal launch arguments, staged identity, owned paths, supervision overrides, and explicit malformed-call or adapter-load failures.
The suite executes the generated Pi artifact to verify literal data transport, settlement gating, notification-only turn ends, and throttled generation-bound progress.
The existing Copilot and process suites retain native loader verification, marker precedence, foreign-process rejection, and per-process query/cache contracts.
The shared tmux/Herdr classifier's Copilot names and adapter-load failure propagation are also exercised through the harness contract suite.

Run `bin/fm-lint.sh bin/fm-harness-lib.sh bin/harnesses/copilot.sh bin/harnesses/pi.sh tests/fm-harness-contract.test.sh` for source-aware interface and implementation lint.
Explicit lint roots preserve CI's cross-file analysis; ordinary branch-local lint does not substitute for that check.
`tests/fm-lint.test.sh` verifies the full inventory, including adapter and platform shell directories, independently of changed-file selection.
The focused adapter suite is registered in the fork catalog without adding it to any concurrent proof admission.

The spawn, busy-wiring, bootstrap, and control-relaunch suites exercise the migrated lifecycle through existing executable entrypoints.
All four support the shared named-case selector without changing their unfiltered case order.
Use their pilot worker/secondmate, native-effort refusal, raw-command, environment-scrubbing, stale-generation, retirement-before-replacement, and failed-launch cases for focused work.
Bootstrap cases retain malformed/null-field behavior, narrower verified support, and aggregate diagnostic ordering; representative Claude, signed Pi, OMP, and other nonpilot cases retain legacy coverage.
Pi watch, primary types, branch, native Codex, and Windows shell suites remain the extension/package integration owners.
The startup-network and sessionstart-nudge suites exercise isolated copied code roots, including the complete harness dependency closure and Pi's bounded large-digest delivery.
Both support the shared named-case selector, as does the lint inventory suite.

No live fleet operation, vendor prompt, workflow gate change, or remote-doctor pin change is needed for this extraction.

## Divergence and locality audit

Record three literal commit identities before comparing: the frozen canonical upstream, the actual PR base, and the final published head.
For a multi-PR series, also retain its original fork baseline; do not confuse that historical baseline with the base used for changed-test selection.
Use the existing bounded reconciliation controller for local validation, with one ledger covering every attempt within each PR-sized allowance.
The [reconciliation skill](../../skills/reconcile-firstmate-upstream/SKILL.md) owns that workflow and its explicit deferral rules.

Keep rename detection disabled so relocation cannot manufacture a lower divergence count:

```sh
git diff --no-renames --name-status <frozen-upstream> <pr-base>
git diff --no-renames --name-status <frozen-upstream> <final-head>
git diff --no-renames --numstat <pr-base> <final-head>
git diff --no-renames --unified=0 <frozen-upstream> <final-head> -- <retained-caller>
```

Separate modified upstream paths from additive modules, deletions, and moved implementation.
Record retained integration hunks and their owner/removal condition from [fork architecture](architecture.md#remaining-integration-patches), including deliberate legacy exceptions.
Identify any existing files that actually return to upstream-equivalent contents rather than counting a renamed implementation as removed divergence.
Keep the commands, path inventories, numeric before/after results, immutable CI identities, and unresolved findings in session or PR evidence rather than copying them into setup documentation.

Check locality through representative behavior and callers, not directory names alone:

| Change example | Owning boundary | Executable evidence |
| --- | --- | --- |
| Pilot hook, launch option, or worker extension | Closed interface and the selected adapter; existing lifecycle consumers | Harness contracts, spawn/control/busy cases, and pilot changed-source routing |
| Ordinary fork test registration | Root-level test and fork catalog; independent concurrency admission | Catalog/runner contracts, unknown-source refusal, and complete lane coverage |
| Native private-path implementation | Shared native policy owner; unchanged caller transaction authority | Native policy cases and PR/X/worker/Herdr integration |
| Shared process or transport implementation | Canonical module and compatibility imports | Export/runtime contracts, copied layouts, strict Pi types, and Windows invocation cases |

Use `test_harness_modules_select_all_consumers` and `test_process_modules_select_all_consumers` from `tests/fm-test-run.test.sh` to refresh shared-owner routing through the named-case selector.
For private paths, inspect the catalog's `route-private-path-modules` selection before the broader process rule, including the explicit X-mode and runner subjects.
For documentation changes, run `bin/fm-doc-audience-check.sh` and `bin/fm-test-run.sh tests/fm-documentation-audiences.test.sh`, then inspect the complete prose diff for audience, ownership, preserved anchors, and unique safety facts.
Neither the structural checker nor a smaller line count proves semantic preservation.

Before closing the implementation series, account for every acceptance criterion in the [approved plan](upstream-plan.md#completion-criteria-and-rollback).
Verify all 18 automatic check names and their single producers against the exact final head, and preserve the manual-only experiment, live-test gates, and package pins.
Separate deterministic fixtures, actual native execution, installed-package checks, and live vendor/backend proof.
A gated skip, an unavailable optional package, or historical vendor evidence is not a new live pass; retain any unresolved requirement explicitly instead of declaring the series complete by inference.

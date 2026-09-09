# Firstmate fork-locality implementation plan

**Status:** Plan approved; implementation has not started. No repository implementation, publication, settings changes, or live Firstmate operations are authorized by this plan alone.

**Repository plan:** `docs\fork\upstream-plan.md`.

**Next step:** Begin `isolation-baseline` after a separate implementation request. All nine implementation todos remain pending.

## Problem and intended outcome

The fork currently carries behavior across many upstream-owned scripts, tests, workflows, and documents.
A single harness or Windows change consequently requires edits in several places, increasing reconciliation effort.

Create deep modules at four practical seams:

1. Copilot/Pi harness adapters behind a small, closed interface.
2. Cohesive process/transport and private-path modules with platform-specific implementations.
3. Declarative test registration separate from the runner engine.
4. Additive fork CI and focused fork documentation.

The goal is locality: future fork changes should normally modify their owning module, fork metadata, and focused tests rather than repeat implementation across upstream files.
An initial extraction can increase the changed-path count.
Do not claim that moving files alone eliminates the fork delta, or that all upstream files can become pristine without upstream accepting the generic seams and fixes.

## Confirmed scope and baseline

The user confirmed the following decisions:

- Pilot the harness interface with **Copilot and Pi only** (`copilot` and `pi`).
  Retain legacy dispatch and lifecycle handling for every other harness, including Claude, `pi-signed`, and OMP.
- Deliver fork-first changes that work independently of upstream acceptance, while keeping generic changes suitable for a later upstream contribution.
- Use separate follow-up PRs, not more changes to reconciliation PR #38.
- Preserve existing behavior, CLI/configuration contracts, Linux/macOS/Windows support, ownership safeguards, and required runtime dependencies.
- Share Pi/OpenCode process implementation through one tracked `.mjs` module with typed compatibility wrappers, rather than generated duplicate implementations.
- Use strictly validated TSV test catalogs consumed with existing Bash/awk facilities.

| Baseline | Recorded value |
| --- | --- |
| Landed reconciliation and current local `main` | `172dc95f0faac04c13eadd7884d2b91be54d2622` |
| Inspected source tree | `69ca15fe307c3bef0ea93bba22fdcdac29f516cb` |
| Earlier inspected PR head, with the identical tree | `e6a9fba8cc7919e9db89646fe336d467f7bbcbba` |
| Frozen canonical upstream comparison | `55d40691ac30a4664217b4e20208287baa88eb21` |
| Fork delta, with rename detection disabled | 149 paths: 123 modified, 23 added, 3 deleted |
| Existing-file modifications in major areas | 42 under `bin`, 46 under `tests`, 18 under `docs` |
| Repository state at the final planning inspection | Clean checkout on `main`; PR #38 already merged |

No additional canonical-upstream fetch is needed to prepare this plan.
At implementation time, pin each follow-up PR's actual base and head.
Use that PR base for changed-test selection; use the frozen upstream commit for divergence comparisons, not as the test-selection base for every follow-up.
Recheck branch rules and required checks before moving workflows.
The planning-time observation was no active rules and disabled branch protection; that observation does not authorize a settings change or prove CI passed.

All repository paths below are relative to `C:\src\firstmate`.
Proposed new paths are implementation targets, not existing interfaces.

### Non-goals

Do not migrate the remaining harnesses, change model/effort defaults, add mandatory dependencies, introduce arbitrary plugin discovery, redesign backend/worktree policy, or change private runtime-state formats.
Do not re-enable the disabled root Claude project-hook policy.
Do not alter live-test gates, broaden CI credentials/permissions, add branch protection, or promote the manual Windows Herdr experiment into automatic CI.
Do not run Firstmate as a supervisor, operate a private fleet, or submit changes upstream as part of this plan.

## Current ownership and integration constraints

| Area | Source owners and relevant behavior |
| --- | --- |
| Harness detection and identity | `bin\fm-harness.sh::detect_own`; `bin\fm-session-lock-lib.sh::fm_copilot_loader_pid`; verified markers, ancestry, and native/MSYS PID handling |
| Dispatch and launch | `bin\fm-bootstrap.sh::crew_dispatch_validate`; `bin\fm-spawn.sh::launch_template`; executable preflight, model/effort arguments, hooks, environment scrubbing, and generation publication |
| Control and supervision | `bin\fm-control-lib.sh`, `bin\fm-control.sh`, `bin\fm-busy-lib.sh`, `bin\fm-wake-lib.sh`; roles, recorded-name normalization, interrupt/exit behavior, busy sources, and owned cleanup |
| Pi extension wiring | `bin\fm-spawn.sh`; generated worker extensions outside the worktree and secondmate loading of `.pi\extensions\fm-primary-turnend-guard.ts` and `.pi\extensions\fm-primary-pi-watch.ts` |
| Existing adapter precedent | `bin\fm-backend.sh` and `bin\backends`; reuse its explicit dispatch style, not a runtime plugin framework |
| Cross-language process behavior | `.pi\extensions\lib\fm-process-ancestry.ts` and `.opencode\plugins\lib\fm-process-ancestry.js`; overlapping implementations, but different exports |
| Private paths | `bin\fm-pr-lib.sh`, `bin\fm-x-lib.sh`, `bin\fm-test-run.sh`, and presentation-lock validation in `bin\backends\herdr.sh` |
| Native transport | `bin\fm-windows-git-bash.ps1::Resolve-FirstmateGitBash`; command construction in `bin\backends\herdr.sh` and `bin\fm-spawn.sh` |
| Test metadata and execution | `bin\fm-test-run.sh`; flat discovery, families, timing hints, changed-path mapping, proof-gated concurrency, and shard composition |
| Isolation authority | `bin\fm-test-isolation-proof.sh`; the runner currently maintains a copied portable allowlist |
| Lint and source-reference inventories | `bin\fm-lint.sh::fm_lint_is_canonical_root`; `bin\fm-test-run.sh::prepare_changed_reference_index`; both enumerate specific directories |
| CI and documentation | `.github\workflows\ci.yml`; `docs\documentation-audiences.json` is the sole prose-classification owner |

### Distribution findings

`bin\fm-home-seed.sh::ensure_home` and `bin\fm-remote-home-provision.sh` create homes from tracked Git checkouts.
`bin\fm-update.sh` delegates tracked-code fast-forwards to `bin\fm-ff-lib.sh`; `bin\fm-update.ps1` is a Git Bash entrypoint.
New tracked modules therefore do not require a new package installer or copy mechanism.
Preserve the existing update/restart behavior rather than treating already-running extensions as automatically reloaded.

`bin\fm-fleet-sync.sh` refreshes project clones; it is not a shared-module distribution hook.
`bin\fm-install-windows.ps1` installs prerequisites; do not add an unnecessary module-deployment layer there.

The real packaging risk is isolated fixtures.
Several Pi/OpenCode tests copy explicit dependency lists, and `tests\fm-pi-primary-types.test.sh` flattens extensions and libraries before strict NodeNext compilation.
Update those layouts to include the complete dependency closure.
Do not solve missing imports with generated duplicate implementations, ambient checkout fallbacks, symlink requirements, or type-safety escapes.

## 1. Harness adapter interface and pilot

### Target module and dependency direction

Add `bin\fm-harness-lib.sh` with an explicit registry and concrete adapters at `bin\harnesses\copilot.sh` and `bin\harnesses\pi.sh`.
Keep current executable entrypoints and compatibility functions.
Only the registered pilots use the new interface; all other harnesses deliberately retain their existing path.
Do not implicitly migrate `pi-signed` or OMP merely because they share some Pi helpers.

The dependency direction is core lifecycle code -> harness interface/adapters -> generic platform helpers.
Adapters must not source `fm-spawn.sh`, `fm-control-lib.sh`, `fm-wake-lib.sh`, or `fm-session-lock-lib.sh` to recover behavior.
Move generic process facts below both identity detection and lifecycle consumers to avoid a circular loader dependency.
Preserve old helper names as thin compatibility functions where existing callers require them.

Use four conceptual operations, not a callback for every existing branch:

| Operation | Interface responsibility |
| --- | --- |
| Describe capabilities | Immutable, operation-specific support: dispatch validation, supported roles, model/effort handling, interrupt/exit/resume policy, supervision model, and busy sources |
| Identify | Verify the pilot's existing identity evidence and return the appropriate process identity at its current detection stage |
| Prepare launch | Resolve required executable information and render validated launch arguments/environment using existing quoting rules, before endpoint allocation |
| Describe owned wiring | Render Copilot hook payloads or Pi extension wiring and exact owned paths for the validated role/generation; let the existing lifecycle transaction publish or retire them |

These are internal operations, not new public CLI commands.
Keep the shared launch context limited to facts callers already validate.
Do not introduce a general command/configuration language, infer capabilities from filenames, or grant adapters authority over task selection, worktrees, landed-work decisions, or private fleet state.
A registered adapter that is missing or broken must produce an explicit error, not silently fall back to legacy execution.
An unsupported operation retains its existing refusal behavior.

### Compatibility requirements

- Preserve detection order: verified Copilot loader, Cursor, Gemini, Rovo, verified OMP override, Claude marker, Pi, Grok, then ancestry. Do not run every pilot probe before the legacy probes.
- Keep marker verification and native/MSYS PID translation. `COPILOT_CLI` alone is not proof of identity.
- Preserve Pi's `PI_CODING_AGENT` marker semantics and `FM_PI_HARNESS` discrimination without letting the `pi` adapter claim `pi-signed` or OMP.
- Preserve the distinction between bootstrap-verified profiles and control-supported roles. In particular, do not broaden bootstrap support merely because control handles Gemini.
- Keep configuration structure checks, absent/null/invalid-field behavior, aggregate error ordering, diagnostics, and exit codes.
- Preserve recorded raw-command normalization and raw-launch behavior; retain exact-name treatment for Pi, Pi-signed, and OMP.
- Refuse unsupported secondmate replacements before stopping the current process.
  Keep Copilot Ctrl+C and `/exit`, Pi's single Escape and `/quit`, and the absence of a verified pane-resume contract for both pilots.
- Retain Pi executable resolution, capability-gated `--tui-mode regular`, and the `FM_PI_HARNESS` launch marker.
  Preserve `--model`, ordinary effort through `--thinking`, and model-scoped `ultra` through the existing native-effort validator and `--codex-effort`.
- Keep Copilot secondmate submission hooks and parent state/task/generation markers.
  Preserve Pi's separate role-specific launch wiring: a generated worker extension versus the two existing primary extensions for a secondmate.
- Retain environment scrubbing, including foreign harness markers and inherited parent-Copilot bindings.
- Preserve `<worktree>\.github\hooks\zz-firstmate-<id>.json`, `<state>\<id>.copilot-prompt-submitted`, and `<state>\<id>.pi-ext.ts`, plus existing hook and extension entrypoints.
  Keep Pi's generated worker extension outside the worktree and retain explicit `-e` loading and owned cleanup.
- Preserve Pi's `agent_start` busy event, `agent_settled` idle event with the existing `ctx.isIdle()` guard, notification-only `turn_end`, and generation-bound native-progress marker.
  Do not substitute OMP's different event protocol or treat an inner turn end as a settled Pi run.
- Keep retirement-before-replacement ordering, stale-generation rejection, ownership checks, metadata formats, and launch-failure rollback. Cleanup must target exact owned artifacts, not broad directory globs.
- Preserve `FM_SUPERVISION_MODEL` overrides, Copilot's autoarm supervision, and Pi's extension supervision, including secondmate launches.
  Keep all nonpilot supervision choices unchanged.
- Leave Claude launch settings, conditional `CLAUDE_CONFIG_DIR` forwarding, and `<worktree>\.claude\settings.local.json` on the legacy path.

Migrate each pilot end to end: detection, dispatch validation, launch preparation, hook/extension wiring, busy/supervision queries, control, and cleanup.
Trace guards, sending, restart, and teardown consumers so no second pilot implementation remains behind an old call path.
Keep lifecycle orchestration in its current owners; replace vendor-specific implementation with calls across the new seam.
Pi's adapter owns the selection and rendering of its launch/wiring, while the existing TypeScript modules retain primary/branch supervision behavior and authority.
Do not move those supervision state machines into Bash or force Copilot and Pi to use the same event protocol.

The hash-pinned `bin\fm-remote-doctor.sh` is an intentional exception.
Keep it self-contained and leave its pin in `bin\fm-remote-entrypoint.sh` unchanged.
Document its small static compatibility patch instead of expanding the remote artifact-integrity protocol in this pilot.

### Proof

Add a focused root-level adapter contract suite and exercise both adapters through the same interface callers use.
Characterize marker collisions, stale/foreign identities, invalid multi-profile configurations, raw commands, early refusal, special-character quoting, generation transitions, failed launch rollback, and explicit adapter-load failure.
Retain existing executable regressions in `tests\fm-spawn-dispatch-profile.test.sh`, `tests\fm-control-relaunch.test.sh`, `tests\fm-copilot-harness.test.sh`, and related busy/supervision suites.
Include Pi's worker/secondmate wiring and event-settlement contracts, plus `tests\fm-pi-watch-extension.test.sh`, `tests\fm-pi-primary-types.test.sh`, `tests\fm-pi-branch-extension.test.sh`, `tests\fm-pi-codex-native.test.sh`, and `tests\fm-pi-windows-shell-invocation.test.sh`.
Run representative Claude, `pi-signed`, OMP, and other nonpilot cases to prove their legacy paths remain unchanged.

## 2. Platform modules

### Process identity, owned termination, and native transport

Add a canonical implementation at `bin\platform\process.mjs` with adjacent typed declarations at `bin\platform\process.d.mts`.
Retain the existing Pi `.ts` and OpenCode `.js` import paths as compatibility wrappers.
Preserve the union of their existing exports, including the TypeScript-only `shellVisibleProcessPid` and `pidAlive`.
There must be one implementation of their overlapping process behavior, not two copies maintained through a generator.

Add a Bash-facing owner such as `bin\fm-platform-process-lib.sh` for generic process facts and native transport.
Place shared Windows-native process operations in `bin\platform\windows-process.ps1` where existing Bash and JavaScript callers can use the same operation without an extra bridge process.
Keep POSIX implementations native to the existing runtime.
Bash-only operations must not acquire a Node dependency.

Retain process-ID representations, `/proc` behavior and `FM_PROC_ROOT_OVERRIDE`, POSIX fallbacks, native single-PID queries, and current cache scopes.
Keep ownership tokens and termination checks authoritative; a cached lookup must not become a new authorization shortcut.
Do not add per-poll full-process-table scans or per-item PowerShell round trips.

Reuse `bin\fm-windows-git-bash.ps1` for the PowerShell entrypoints that already depend on it.
Consolidate genuinely shared quoting and native command construction without changing their semantics.
Keep Herdr worktree acquisition, lease ownership, presentation policy, and cleanup decisions in the backend.
Do not replace an inexpensive existing Git Bash lookup with a new PowerShell launch on every operation.

Update the Pi/OpenCode fixture dependency closure and run package/type compatibility checks against the existing installed/pinned versions.
Cover fresh Git clones, worktree-shaped homes, and isolated fixture layouts without invoking live provisioning or self-update against a real fleet.
Leave production clone/update scripts unchanged unless a concrete dependency-closure test demonstrates a required change.

### Private-path validation and publication

Add `bin\fm-private-path-lib.sh` and `bin\platform\windows-private-path.ps1`.
Extract the repeated native validation/securing mechanics from PR data, X-mode state, test-worker temporary roots, and Herdr presentation-lock namespaces.
Keep existing public helper names and caller-specific diagnostics as compatibility functions.

The interface should provide bounded validate/secure operations for explicit path kinds and the existing policy variants.
Capture policy differences before consolidating them; do not flatten them into a permissive universal predicate.
Keep transaction sequencing, atomic publication, lock ownership, and rollback decisions with their current owners.

Preserve owner SID checks, null-DACL refusal, allowed SYSTEM/Administrators principals, reparse/symlink refusal, file/device/link-count checks, POSIX ownership/modes, and refusal when required native verification is unavailable.
Keep batched operations batched.
Pass path data losslessly rather than interpolating untrusted path text into executable PowerShell source.
Do not introduce persistent validation caches or reuse validation after a path has been replaced or mutated.

### Proof and integration coverage

Exercise actual native ACL and process behavior in Windows fixtures, plus portable failure/ownership cases through the public compatibility functions.
Retain relevant coverage in `tests\fm-pr-check-security.test.sh`, `tests\fm-x-mode.test.sh`, `tests\fm-test-run.test.sh`, `tests\fm-session-lock-ancestry.test.sh`, `tests\fm-pi-windows-shell-invocation.test.sh`, and the Herdr treehouse/presentation suites.
Add focused module tests rather than expanding every upstream test file for new coverage.
Any Node test file must have a discoverable root-level `.test.sh` entrypoint and an explicit changed-test mapping.

Include new shell directories in both full and changed-mode lint membership.
Include new `.mjs`, declaration, and `.ps1` files in the relevant syntax/type checks and changed-reference inputs.
Verify stock macOS Bash parsing, Windows path quoting, missing-helper errors, and operation counts on the migrated hot paths.

## 3. Test catalog separate from the runner engine

### Target layout and ownership

Add `bin\fm-test-catalog-lib.sh`, `tests\catalog\core.tsv`, and `tests\catalog\fork.tsv`.
Use a versioned, strictly parsed record schema for family membership, duration hints, and ordered changed-path mappings to existing families/tests/gates.
Keep repository-relative keys, milliseconds, ordering, and matching semantics compatible with the current runner.
Do not evaluate catalog contents as shell code or support arbitrary command records.

Separate shared/generic registrations from actual fork additions and overrides.
These are new fork-introduced catalogs, not an assertion that canonical upstream already provides a catalog interface.
An override must name the existing key and expected prior value/record explicitly; reject duplicate or accidental shadowing.
Missing required files, malformed records, unknown kinds/families/targets, invalid weights, stale overrides, and references to missing tests must fail with actionable diagnostics.
An unregistered newly discovered test still follows the current conservative serial behavior.

Read and validate metadata once per runner invocation and use bulk lookups or in-process cached results.
Do not add Node/jq requirements to lightweight listing or introduce a subprocess per catalog row/test.
Retain the runner's scheduling, timeout/cancellation, temporary-root ownership, JSON reporting, and coverage algorithms.
Keep procedural dependency/reference expansion in the engine where it is genuinely behavioral, rather than encoding shell programs in TSV.

### Isolation and compatibility

`bin\fm-test-isolation-proof.sh` remains the portable admission authority.
Have the runner cache that command's portable `--list` result once instead of maintaining a separate copied allowlist.
Keep that list-only path independent of runner loading to prevent recursion.
Catalog metadata cannot self-declare a test parallel-safe, override proof-required admission, or raise concurrent-family caps.
Do not enlarge the proven set without a new successful concurrent proof archive.

Preserve flat `tests\*.test.sh` discovery, existing script paths, named-case entrypoints, family names, lane names, ordering, exit codes, output/JSON formats, and all five portable serial shards.
Keep the exact coverage union and disjoint partition.
Keep unknown-source refusal, generic fixture-reference handling, and the repaired mail/shared-fixture mappings.

Do not relocate existing tests just to create a fork directory.
Put new fork-facing coverage in additive root-level scripts.
Move an existing fork-only test implementation only when both its whole-script and named-case interfaces can remain intact without duplicate execution.
In particular, retain `test_copilot_threads_model_effort_and_hooks` at its existing executable interface in `tests\fm-spawn-dispatch-profile.test.sh`.
Respect `tests\lib.sh::fm_test_run_cases` consuming selectors before invoking child fixtures.

### Integration and proof

Update synthetic runner fixtures to install the real loader plus minimal valid fixture catalogs and the required proof-list dependency.
Real-tree fixtures must include the complete real dependency closure.
Replace tests that patch moved implementation text with behavioral catalog fixtures and executable-interface assertions.
Do not add production fallbacks merely to keep incomplete fixtures passing.

Add mappings for catalog files, the loader, the fork workflow, harness adapters, platform modules/declarations, and the compatibility wrappers' consumers.
Extend `prepare_changed_reference_index` for new owned directories; explicit shared-module mappings must select every affected consumer family, not only the first importer.

Compare old/new listing, selection, lane, shard, and JSON results on **identical inventory and metadata inputs**.
Then add the new tests and re-prove complete, disjoint coverage and the existing balance bounds.
New tests can legitimately rebalance shard membership; do not mistake that for a failed identical-input parity check.
Include malformed metadata, missing dependencies, invalid overrides, shell metacharacters, unknown changed sources, named-case forwarding, and no-new-dependency list-mode regressions.
Use `tests\fm-test-run.test.sh`, `tests\fm-test-isolation-proof.test.sh`, and the existing coverage guard as the integration surface.

## 4. Fork-specific CI and documentation

### CI split

Create `.github\workflows\fork-ci.yml` and move the existing `windows-update`, `reconciliation-windows`, and `harness-package-compatibility` jobs in one atomic change.
Preserve these five expanded check names:

- `Windows self-update entry point`
- `Windows reconciliation (core)`
- `Windows reconciliation (copilot-launch)`
- `Windows reconciliation (legacy-rollback)`
- `Harness package compatibility`

Preserve one producer per check name and the current 18-check automatic matrix.
Copy the existing push/pull-request triggers, read-only permissions, platforms, matrix subjects, timeouts, command selectors, live gates, action versions, and artifact behavior.
Give the new workflow a distinct name; retain workflow-qualified concurrency groups so it cannot cancel the core workflow.

Preserve Node 24, tasks-axi 0.2.5, and the relocated package lane's Pi 0.84.3, OpenCode 1.18.23, and TypeScript 5.9.3 pins.
Do not make shared CI's existing unpinned package checks silently inherit those fork-lane pins.
Reuse the existing setup/install entrypoints where they fit; do not create shallow setup wrappers for cosmetic deduplication.

Keep portable/Herdr lanes, timing aggregation and its artifact-producing dependencies, macOS stock Bash, lint, coverage, and invariants in `ci.yml`.
Retain necessary shared-CI prerequisite/compiler/action fixes as explicit integration patches.
Do not restore the whole upstream workflow and silently lose coverage.
Leave `.github\workflows\windows-herdr-spike.yml` as its existing manual experiment.

Ensure the new workflow is covered by actionlint and changed-test routing.
Add bounded new platform/adapter cases to appropriate existing owners without dropping old cases or silently raising timeouts.
Use the existing package-compatibility job for Pi's type/extension coverage and the existing Windows core subject for native Pi invocation coverage.
Keep the Copilot launch subject and its named-case interface unchanged.
Verify exact-head check names, subjects, permissions, and artifacts after the split; an old PR's checks are not evidence for the new workflow.

### Documentation consolidation

Add `docs\fork\architecture.md` as `maintainer-architecture` and `docs\fork\verification.md` as `maintainer-verification`.
The architecture page owns the module map, interfaces, legacy exceptions, and remaining upstream integration patches.
The verification page owns repeatable compatibility procedures, current CI ownership, live-proof gates, and instructions for refreshing divergence evidence.
Do not move all platform or operator guidance into maintainer documents.

Review modified operator documents individually.
Move only genuinely fork-specific material to an appropriately classified focused owner when doing so removes duplication.
Keep concise pointers from existing owners, preserve anchors and every unique current safety/verification fact, and retain necessary operator-current guidance at setup destinations.
Use `docs\documentation-audiences.json` for all new classifications and required pointers; do not create a second registry or new audience class.

Update directly related documentation in each implementation PR.
The final documentation PR consolidates ownership and removes remaining duplication; it must not postpone necessary interface documentation until the end.
Keep `CLAUDE.md`'s literal compatibility pointer and do not introduce unsupported automatic instruction imports.
Load the repository's writing-for-agents guidance before any eventual skill or `AGENTS.md`/`CLAUDE.md` edit.

Keep task chronology, branch-specific metrics, temporary paths, and delivery evidence in session/PR artifacts.
Do not turn public product documentation into a reconciliation diary.
Run the existing documentation audience/link checker and semantically review the complete documentation diff.

## Delivery sequence and todos

Use six independently reviewable follow-up PRs, each based on the landed preceding slice.
Separate mechanical extraction from behavioral-equivalence repairs in reviewable commits within a PR, but never publish an incoherent intermediate runtime.
Do not amend or reopen PR #38.

| Todo ID | Work and delivery slice | Depends on | Completion condition |
| --- | --- | --- | --- |
| `isolation-baseline` | Capture compatibility and divergence baseline; preparation, not a separate implementation PR | None | Pinned base/tree, source-owner map, reproducible inventory/selection/check-name evidence, and identified missing characterization cases |
| `isolation-fork-ci` | PR A: move the three job definitions producing five fork checks | `isolation-baseline` | Exactly one producer for every existing check; unchanged triggers, gates, pins, dependencies, and artifacts |
| `isolation-test-catalog` | PR B: introduce TSV loader/catalogs, remove metadata duplication, wire fixtures and routing | `isolation-fork-ci` | Identical-input parity, strict failure cases, proof-owned concurrency, and complete coverage |
| `isolation-private-paths` | PR C: extract private-path mechanics and migrate the four caller groups | `isolation-test-catalog` | Native and portable policy/ownership parity; no weaker validation or new cache lifetime |
| `isolation-process-transport` | PR D: share process implementation, native operations, and transport; fix dependency layouts | `isolation-private-paths` | Existing exports/imports and package checks preserved; owned process semantics and operation counts retained |
| `isolation-harness-contract` | PR E, first phase: define the Copilot/Pi interface, dependency direction, and contract characterization | `isolation-process-transport` | Copilot hooks and Pi extensions prove the seam; no circular dependencies or new core-state authority |
| `isolation-harness-pilot` | PR E, completion: migrate Copilot and Pi across all lifecycle consumers and remove duplicate implementations | `isolation-harness-contract` | Pilot behavior preserved end to end; Claude, `pi-signed`, OMP, and other nonpilot legacy parity demonstrated |
| `isolation-fork-docs` | PR F: consolidate fork documentation and stable ownership/pointers | `isolation-harness-pilot` | Classified, linked, nonduplicative guidance with compatibility facts and anchors retained |
| `isolation-acceptance` | Complete integrated verification and final divergence/locality audit before closing the series | `isolation-fork-docs` | Every acceptance criterion below has evidence or an explicit unresolved blocker |

The sequence intentionally serializes changes to `fm-test-run.sh`, `fm-lint.sh`, `bin\backends\herdr.sh`, and shared test metadata.
Do not split those overlapping edits among simultaneous implementation branches merely to increase parallelism.
Add characterization tests immediately before each concern's extraction, using the existing public entrypoints and isolated fixtures.

## Validation policy

Do not execute implementation tests or live operations merely to approve this plan.
During implementation, use the smallest existing checks covering each change and retain the repository's bounded-validation discipline.

For a PR-sized validation effort, use the existing **40-minute / 2,400-second local default**, with a single ledger covering preflight and all attempts.
Continuation uses only the unspent allowance; an interruption is not a new budget.
Preserve the two-timeout circuit breaker, explicit overrides, production timeouts, and named CI deferrals.
Do not retroactively reclassify the historical 1,200-second reconciliation attempt.
Use the recorded Git-for-Windows Bash, `C:\Program Files\Git\bin\bash.exe`, not ambient `bash`.

| Change | Required evidence |
| --- | --- |
| Harness interface | Copilot/Pi contract suites, executable launch/control regressions, Pi role-specific extension and settlement cases, nonpilot legacy cases, stale/foreign ownership and generation rollback |
| Process/transport | Shared-module runtime tests, strict Pi type checks, OpenCode compatibility fixtures, actual native PID/quoting cases, preserved subprocess/cache behavior |
| Private paths | Native ACL policy cases, POSIX ownership/link/device cases, mutation/replacement refusal, and existing PR/X/worker/Herdr consumers |
| Catalog/runner | Identical-input selection/output parity, malformed-input refusals, single proof owner, complete/disjoint lane and five-shard partition, timing bounds |
| CI | actionlint, distinct concurrency ownership, exact-head expanded check-name/subject inventory, existing artifacts and timing aggregation |
| Documentation | `bin\fm-doc-audience-check.sh`, existing documentation tests, and semantic review of audience, ownership, anchors, and unique current facts |

Route broader portable, macOS, Windows, and Herdr checks to their existing CI owners.
Record a deferred or unavailable check as such, with its named owner and exact head; do not call an optional skip or a mock a real platform/vendor proof.
Keep live vendor/backend checks separately gated and explicitly authorized in controlled fixtures.
If hook discovery/order or other vendor-controlled assumptions change, require the existing live proof before claiming that assumption verified.
For example, `tests\fm-copilot-hooks-live-e2e.test.sh` and `tests\fm-pi-primary-live-e2e.test.sh` are opt-in real-harness guards, not default unit tests.
Use the guard appropriate to the changed assumption; Copilot hook evidence does not prove Pi extension or primary-continuity behavior.

Use existing tooling and dependencies.
Do not add/install tools during planning, expand dependency requirements to simplify metadata parsing, alter host Git signing/hooks/configuration, or touch real fleet state.
Clean up only task-owned, specifically identified test artifacts and processes.

## Completion criteria and rollback

The series is complete only when all of the following hold:

1. Copilot and Pi each have one adapter-owned implementation of the migrated behavior, with core orchestration and existing Pi supervision modules retained and exceptions such as the self-contained doctor documented.
2. The Pi/OpenCode overlapping process implementation has one source, with old exports/import paths intact. Native private-path mechanics have one owner for each policy variant, without weakening checks or multiplying native calls.
3. A normal new fork test can be registered through its test file and fork catalog without editing runner algorithms or upstream test files. Concurrency still requires the existing independent proof.
4. All 18 existing automatic checks still have exactly one producer, their original coverage, and current exact-head evidence. The manual Herdr experiment remains manual.
5. New module paths are included in lint, syntax/type checks, reference discovery, changed-test routing, and every relevant fixture/deployment layout.
6. CLI/configuration, outputs, lifecycle ordering, Windows/macOS/Linux behavior, private-state formats, and current runtime dependencies remain compatible.
7. Fork documentation has clear classified owners and concise upstream-document pointers, without broken anchors, duplicate policy, or lost safety facts.
8. A final before/after report records modified upstream paths, integration hunks, moved implementation, remaining duplicate logic, and the owner/removal condition for retained patches.

Judge locality with representative change-impact checks: a pilot hook/extension-wiring/model change should normally stay in its adapter and focused tests; an ordinary fork test addition in its test/catalog; and a native ACL implementation fix in the platform owner and its tests.
Use call-site and executable evidence, not directory names or source-text assertions alone.
Record which upstream files genuinely return to upstream-equivalent contents and which must retain compatibility calls.
Do not manufacture a lower count through renames, generated copies, deleted tests, or suppressed validation.

Publish each slice as an ordinary follow-up PR only after the relevant evidence is available.
Do not auto-merge or change branch rules as part of this work.
A failed slice is rolled back coherently through a reviewed revert of the module and its callers, including dependent slices if necessary.
Do not use hard resets, mutate private operational state, or hide failures behind legacy fallbacks.

Generic seams and correctness fixes may later be offered upstream as separate, behavior-preserving contributions.
That is an optional subsequent delivery decision, not a dependency or an unrequested action in this plan.

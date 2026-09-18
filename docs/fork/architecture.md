# Fork module architecture

This page owns the fork's module boundaries, change-placement rules, and retained upstream integration patches.
[Fork verification](verification.md) owns compatibility procedures and CI coverage; [product architecture](../architecture.md) and [configuration](../configuration.md) retain their existing lifecycle and operator contracts.
The [implementation plan](upstream-plan.md) records the approved design and acceptance criteria, not a second current module reference.

## Module map

| Concern | Implementation owner | Boundary retained by callers |
| --- | --- | --- |
| Copilot/Pi policy | `bin/fm-harness-lib.sh`, `bin/harnesses/copilot.sh`, `bin/harnesses/pi.sh` | Detection order, profile selection, lifecycle transactions, and every nonpilot path |
| Process/directory identity and native transport | `bin/platform/process.mjs`, its `.d.mts` declarations, `bin/fm-platform-process-lib.sh`, `bin/platform/windows-process.ps1` | Ownership, generation checks, escalation, and backend leases |
| Backend harness-process classification | `bin/fm-agent-process-lib.sh` | tmux and Herdr retain recovery, busy-state, and close-authority decisions |
| Bash/native path spelling | `bin/fm-path-lib.sh` | Explicit home/code context initialization; filesystem identity and authorization remain with callers |
| Native private paths | `bin/fm-private-path-lib.sh`, `bin/platform/windows-private-path.ps1` | Caller-specific POSIX policy, transaction ordering, publication, and rollback |
| Azure PR identity and observation | `bin/fm-pr-poll.sh`, consumed through `bin/fm-pr-lib.sh` | Canonical private registration, notification, merge authority, and landed-work proof |
| Test metadata | `bin/fm-test-catalog-lib.sh`, `tests/catalog/core.tsv`, `tests/catalog/fork.tsv` | Runner execution and reference expansion; independent proof admission |
| Fork CI | `.github/workflows/fork-ci.yml` | Shared-CI regression and artifact dependencies; manual-only Windows Herdr experiment |

Lifecycle callers depend on the harness interface, which depends on generic platform helpers; adapters never import lifecycle owners.
The existing `bin/fm-windows-git-bash.ps1` remains the PowerShell entrypoints' Git Bash resolver, not a new module distribution mechanism.

## Copilot and Pi harness seam

`bin/fm-harness-lib.sh` owns the closed, exact-name `copilot` and `pi` registry.
Its header owns the four internal operations, prepared launch fields, and refusal contract.
`bin/harnesses/copilot.sh` and `bin/harnesses/pi.sh` own their capability facts, staged identity checks, executable preparation, and rendered launch wiring.
They depend only on the interface's shared name facts and generic platform helpers, never on lifecycle scripts.
Missing or incomplete registered adapters report an error rather than selecting a legacy implementation; loading a different root cannot borrow previously loaded implementation functions.

`bin/fm-harness.sh` owns marker-versus-ancestry arbitration while the pilot adapters retain their staged identity mechanics.
Core callers retain configuration structure and diagnostic ordering, recorded-name normalization, and the lifecycle transaction.
Bootstrap verification, typed dispatch profile validation, local control, and remote launch/relaunch support consume the pilot capabilities without making their operation-specific support interchangeable.
The interface does not introduce a resume contract or broaden the existing remote Copilot relaunch restriction.
Spawn retains role/profile resolution, generation allocation, exact-file publication, worktrees, endpoint delivery, and rollback.
Control, sending, restart, and teardown consume the same pilot-owned mechanics and artifact paths rather than reproducing them.
Adapters describe paths and content but never create, retire, or remove task state.

The Pi adapter selects worker versus primary extension wiring, while the existing TypeScript extensions retain primary and branch supervision authority.
Its generated worker preserves settlement, continuation, notification, and generation-bound progress semantics; embedded path values are escaped as data.
Generated busy and progress callbacks invoke their tracked Bash owner through Bash, including under native Windows Node.
Copilot retains its hook entrypoints and native PID-result cache, with session-lock compatibility functions delegating identity checks.
Explicit supervision overrides remain authoritative before detection, while an adapter-load failure is not reinterpreted as an unknown primary.

Every nonpilot retains legacy dispatch, including `pi-signed` and OMP.
The signed Pi worker renderer and its primary-extension paths deliberately remain in spawn instead of silently sharing the pilot implementation.
The hash-pinned `bin/fm-remote-doctor.sh` retains intentional static harness-compatibility facts rather than importing the pilot registry.
It sources the remote job, tasks-axi, and Herdr ownership libraries; copied fixtures must carry those dependencies.
Any doctor-byte change requires recalculating its entrypoint hash without changing the integrity protocol.

## Test registration seam

`bin/fm-test-catalog-lib.sh` owns parsing and validating `tests/catalog/core.tsv` and `tests/catalog/fork.tsv`.
Its header owns the versioned record schema and the `fm_test_catalog_load`, `fm_test_catalog_get`, and `fm_test_catalog_maps` interface.
Core holds shared registrations; fork holds additions and explicit overrides that name the expected prior value.
Both catalogs are introduced by this fork, not interfaces already supplied by canonical upstream.

The catalog supplies classification, expected gate-skip classes, separate serial and parallel-lane duration hints, and ordered changed-path registrations.
`bin/fm-test-run.sh` retains flat discovery, procedural reference expansion, scheduling, timeouts, worker privacy, coverage, and reporting.
Add a root-level test file and its fork registration rather than editing runner algorithms for an ordinary new test.
Add changed-source mappings when the test introduces or covers a new source owner, and retain unknown-source refusal rather than supplying a permissive fallback.
For shared test fixtures and helpers, curated mappings supplement reference-derived consumer families rather than replacing them.

Registration does not confer concurrency permission.
`bin/fm-test-isolation-proof.sh` owns portable candidates and frozen family admissions; the runner consumes those results once per invocation and retains its family caps.
A new test can be classified into an existing family while remaining serial until it has the required proof.
Changes to a family assignment cannot reuse admission recorded for a different family.
[Isolation verification](../fm-test-isolation-proof.md) owns the evidence needed to change admissions.

The loader validates once with Bash and awk, then serves in-memory lookups without evaluating metadata as shell code.
Validated keys are encoded into Bash 3.2-compatible scalar entries, so lookups do not repeatedly scan or trim the complete TSV snapshot.
Each successful load replaces the prior cache, including entries no longer present.
Parallel-lane hint overrides do not change serial scheduling weights or concurrency admission.
Missing dependencies or invalid records stop selection explicitly.
`.gitattributes` preserves the catalogs' LF format on Windows.

## Path spelling and directory identity

`bin/fm-path-lib.sh` owns Bash path spelling, declared context initialization, and explicit path arguments for native consumers.
Its header owns supported forms and refusal mechanics.
Control, send, spawn, and PR/check registration initialize their selected home/code paths before using them; source-only helpers do not implicitly rewrite a caller's environment.
Native Git receives explicit native directory arguments instead of relying on MSYS heuristics for paths containing spaces, Unicode, or glob metacharacters.
Spelling conversion preserves unexamined components and does not confer filesystem permission, resolve a symbolic link as authorization, or cache an identity verdict.
The existing `fm_platform_same_directory` predicate remains the identity owner used by isolation and recovery checks.
Retained recovery receipts are not rewritten merely to change their home spelling; inspection checks that the bound home identifies the same existing directory.

## Private-path seam

`bin/fm-private-path-lib.sh` owns bounded native dispatch, path-data transport, batching, and retries through the interface in its header.
`bin/platform/windows-private-path.ps1` is the native ACL implementation owner; its header identifies the deliberately different PR, X, worker, and Herdr policies.
The Bash module caches only the converted location of that tracked PowerShell code, never a target's identity, permissions, or validation result.
The helper is loaded in the existing native invocation, without a second PowerShell bridge or per-item native calls for PR batches.

`bin/fm-pr-lib.sh`, `bin/fm-x-lib.sh`, `bin/fm-test-run.sh`, and `bin/backends/herdr.sh` retain their public helper names and platform detection.
They still own POSIX modes, ownership where required, device and link checks, publication ordering, lock identity, worker allocation, and rollback.
Extraction does not make their policies interchangeable or move transaction authority into the platform module.
Native failures remain refusals; a missing tracked dependency is not permission to reuse an earlier verdict or fall back to synthetic Windows modes.

## Process and native transport seam

`bin/platform/process.mjs` owns the overlapping Pi/OpenCode process implementation, with its typed interface in `bin/platform/process.d.mts`.
The existing `.pi/extensions/lib/fm-process-ancestry.ts` and `.opencode/plugins/lib/fm-process-ancestry.js` paths re-export their original export sets.
Pi retains `shellVisibleProcessPid` and `pidAlive`; OpenCode does not acquire those additional exports.
Both wrappers use the same functions rather than generated implementations, while lifecycle decisions remain in their extension/plugin callers.

The module retains per-instance Windows ancestry caching, verifies native liveness on every ancestry query, and takes fresh process rows for ordinary PID liveness.
`bin/platform/windows-process.ps1` owns bounded native process-fact queries, watch-arm root discovery, and batched descendant termination.
Graceful cleanup still finds the owned MSYS root and sends TERM through Bash before callers choose their existing escalation path.
Forced cleanup preserves the existing direct-PID TERM fallback after a native operation fails; this is not authority to terminate an arbitrary process, and callers must retain their owned-child and generation checks.
A missing tracked native helper throws explicitly before any native operation or direct-PID fallback.

`bin/fm-platform-process-lib.sh` owns generic Bash process facts, directory identity, single-PID image queries, and literal PowerShell command rendering without a Node dependency.
Its directory predicate compares existing filesystem objects rather than raw Git/Git Bash path spellings or unconditional case folding.
`bin/fm-fleet-sync.sh` uses that predicate for the clone-root assertion and managed-project name resolution, so path aliases cannot lose a registered local-only posture.
Dirty, diverged, and nested-directory safeguards remain in the refresh owner; branch pruning uses Git's merged-branch guard rather than treating upstream deletion as proof of landing.
`bin/fm-session-lock-lib.sh` retains ownership and ancestry orchestration, delegating Copilot marker verification and PID-result caching through the harness interface.
Its Windows ancestry bridge and verified Claude session-PID handoff use the shared native process facts without adding a Node dependency to Bash callers; the library header owns their precedence and numeric-PID ambiguity rules.
Native lookup failures remain distinct from verified process absence, so `bin/fm-lock.sh` refuses rather than reclaiming an unverified owner.
`bin/backends/herdr.sh` retains leases, worktree acquisition, presentation, and rollback; its public transport functions and spawn's quoting function delegate to the shared module.
Git Bash callers retain their inexpensive PATH/cygpath lookup, while existing PowerShell entrypoints continue using `bin/fm-windows-git-bash.ps1`.

## Startup and reporting cost

The startup and reporting cost guarantees are intentional fork behavior, including optimizations in files still shared with upstream.
They limit repeated command launches and filesystem reads on Windows rather than merely preserving the report's output.
`bin/fm-backend.sh` owns metadata access, while `bin/fm-backlog-transition-lib.sh` owns path validation and the in-flight lookup consumed by `bin/fm-bootstrap.sh`.
`bin/fm-classify-lib.sh` owns in-process status parsing and fresh file-fact snapshots; `bin/fm-crew-state.sh` and `bin/fm-fleet-snapshot.sh` retain current-state and captured-generation semantics.
`bin/fm-wake-lib.sh` owns lock and recovery-record checks, while `bin/fm-session-start.sh` owns streaming completed diagnostics without treating an unfinished stage as ready.
`bin/fm-herdr-session-cleanup.sh` owns the conservative orphan-candidate filter and retains full cleanup validation for any remaining candidate.
Their headers own the exact access, fallback, and composition mechanics.

Retire or replace these optimizations only with evidence of equivalent outputs, freshness, safety refusals, and equivalent or better cost on comparable Windows inputs.
Use [Startup and Bearings verification](verification.md#startup-and-bearings) to retain the cost and safety regressions and their native-platform CI routing, or provide equivalent coverage for a different implementation.
Compare matched workloads in isolated fixtures; output equality alone or increased deadlines do not establish cost preservation.
Record replacement evidence in the reconciliation PR rather than treating a conflict-free merge as proof.

## Windows management cost

The startup/reporting replacement conditions above also apply to Windows management optimizations, with the checks routed through [Windows management verification](verification.md#windows-management).
`bin/fm-home-summary-refresh.sh` owns coalesced publication requests; spawn requests that work without waiting while the existing watcher owns execution and retry.
A pending request never certifies fresh summary data, and publication retains atomic replacement and the prior document's original timestamp until success.

`bin/fm-ghcp-hook.ps1` routes native command checks through `bin/fm-copilot-command-check.mjs`, which imports the existing arm/cd policies rather than duplicating their parser or decisions.
The Copilot Stop owner parses and binds its event once, shares the read-only supervision predicate in process, and applies one late ownership-checked continuation transaction only when a record must change.
Short Windows continuation locks may use the batched owner-link mechanics in `bin/fm-lock-fast.pl` through `bin/fm-wake-lib.sh`; their publication, ownership, stale recovery, and cross-version lock protocol remain unchanged.
The Git Bash resolver preserves candidate precedence while returning before unused fallbacks are enumerated.
Removing repeated work is not permission to disable a check or enlarge its deadline.
`bin/fm-pr-lib.sh` owns invocation-local reuse of pure Azure URL parsing and fresh single-query file facts; ACL setup batches only one private staging cohort before payload is written.
Neither optimization caches permissions, filesystem authorization, or remote PR observations across operations or publication phases.

`bin/fm-control.sh` retains lifecycle authority, with read-only inspection, guarded missing-terminal recreation, and approved record-recovery mechanics in `bin/fm-control-recovery-lib.sh`.
The recovery plan binds exact native process birth identities and task-held leases, preserves both copies, and enters the existing relaunch transaction only after fresh approval verification.
`bin/platform/windows-process.ps1` owns native descendant facts; the Herdr adapter interprets them and refuses to equate a missing Windows registration with an exited process.
The verified POSIX restore path remains unchanged.

## PR identity and observation seam

`bin/fm-pr-poll.sh` owns Azure URL and response validation as well as the explicit-organization native read.
Keeping that codec in the static program preserves the self-contained copied-check contract without duplicating URL rules or adding state-local executable dependencies.
`bin/fm-pr-lib.sh` exposes the shared reader and requires persisted identities to already be canonical; registration may resolve input aliases before publication.
Private artifact binding, notification-before-marker ordering, replay, and source retirement retain their existing owners.
Teardown and review consume the validated Azure source head without manufacturing GitHub pull refs, and `bin/fm-backlog-transition-lib.sh` preserves unsupported Azure row links at its tasks-axi representation boundary, including retention, answer-time artifacts, and interrupted cleanup replay.
[Configuration](../configuration.md#azure-devops-pr-completion) owns prerequisites and supported limits; observation does not grant merge or cleanup authority.

## Tracked layout and fixture boundaries

Normal Git clones, linked worktrees, and tracked-code fast-forwards carry the modules and catalogs.
No installer copy step, generated duplicate, ambient-checkout fallback, symlink requirement, or automatic reload of already-running extensions is introduced.
The existing update and restart owners retain their authority.

| Fixture owner | Dependency closure |
| --- | --- |
| `tests/harness-helpers.sh` | Harness interface, both registered adapters, and process dependencies |
| `tests/process-helpers.sh` | Bash process helpers, canonical module and declarations, and native process implementation |
| `tests/private-path-helpers.sh` | Shared path spelling, Bash private-path interface, and native ACL implementation |
| `tests/catalog-helpers.sh` | Real catalog loader, valid fixture catalogs, and the required proof-list dependency |

Synthetic catalogs may describe a minimal test world; they are not another production registry.
Pi type checks preserve repository-relative module depth rather than flattening libraries, including the Claude-owned Calm sprite and text-preservation targets reached by Pi symlinks; the Calm rendering fixture keeps the same layout.
Copied startup and hook fixtures must install the complete dependency closure even when the exercised case does not launch either pilot.
Missing tracked code remains an explicit error rather than permission to continue with a partially loaded fixture.

## Change placement

A Copilot hook or Pi worker-extension change belongs in the corresponding adapter and focused executable tests.
Shared lifecycle policy still belongs in its existing owner; a new capability or caller contract may legitimately require an interface and integration change.
An ordinary fork test addition belongs in a root-level `tests/*.test.sh` file and the fork catalog, with any required changed-source mapping; it does not require editing runner algorithms.
A native ACL implementation change belongs in the private-path owner and its policy fixtures, not duplicated native code in each caller.
Registration never substitutes for concurrency proof, and a policy difference must not be flattened merely to reduce changed-file counts.

## Remaining integration patches

The fork remains dependent on explicit compatibility patches until upstream accepts equivalent seams and behavior.
The removal conditions below are design boundaries, not authorization to revert working integration or submit upstream.

| Retained patch | Current owner and reason | Removal condition |
| --- | --- | --- |
| Pilot calls and source-error propagation | Detection, bootstrap, spawn, control, sending, busy/supervision, restart, and teardown retain orchestration while calling the closed interface | Upstream supplies equivalent pilot capabilities and failure semantics across those callers |
| Pi/OpenCode import compatibility | The existing extension/plugin import paths re-export their original public sets from the canonical process module | Consumers and supported package layouts adopt an equivalent shared import contract |
| Native policy and transport calls | PR, X-mode, runner-worker, Herdr, and spawn callers preserve their public helpers and transaction-specific policy | Upstream provides equivalent native mechanics without changing ownership, privacy, or subprocess bounds |
| Startup, reporting, and Windows management cost | The [startup/reporting owners](#startup-and-reporting-cost) and [management owners](#windows-management-cost) retain cost guarantees alongside output, freshness, and safety contracts | A replacement satisfies the cost-preservation conditions and preserves approved recovery identity and replay safeguards |
| Catalog and proof integration | Runner compatibility functions delegate metadata queries; reference expansion and execution remain in the runner, while proof lists remain independent | Upstream supports compatible metadata loading, reference selection, and proof-owned admission |
| Module discovery and fixture closure | Lint and changed-reference discovery include new directories and file types; copied fixtures install complete dependencies | Equivalent upstream discovery and fixture layouts include the owning modules |
| Fork workflow and shared-CI compatibility | The dedicated workflow owns fork checks; shared CI retains its prerequisite, compiler, action, and artifact integration | Equivalent upstream checks preserve every required subject, gate, and producer |
| Legacy and integrity exceptions | Nonpilots, including the signed Pi renderer, stay legacy; the remote doctor's harness facts remain static and its entrypoint remains hash-pinned | A separately scoped migration or reviewed integrity-protocol change preserves their contracts |
| Operator and contributor pointers | Setup, trust, delivery, privacy, and cleanup guidance remain with their classified owners | Upstream documents equivalent supported behavior without losing anchors or safety facts |

The proof command's admission evidence, runner execution algorithms, and backend lifecycle transactions are retained authorities, not duplicate implementations awaiting extraction.
Use the [divergence and locality audit](verification.md#divergence-and-locality-audit) to distinguish those necessary boundaries from remaining duplication.

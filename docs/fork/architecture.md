# Fork module architecture

## Copilot and Pi harness seam

`bin/fm-harness-lib.sh` owns the closed, exact-name `copilot` and `pi` registry.
Its header owns the four internal operations, prepared launch fields, and refusal contract.
`bin/harnesses/copilot.sh` and `bin/harnesses/pi.sh` own their capability facts, staged identity checks, executable preparation, and rendered launch wiring.
They depend only on the interface's shared name facts and generic platform helpers, never on lifecycle scripts.
Missing or incomplete registered adapters report an error rather than selecting a legacy implementation; loading a different root cannot borrow previously loaded implementation functions.

Core callers retain detection-stage ordering, configuration structure and diagnostic ordering, recorded-name normalization, and the lifecycle transaction.
Bootstrap verification, local control, and remote launch/relaunch support remain distinct operation-specific capabilities.
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
The self-contained, hash-pinned `bin/fm-remote-doctor.sh` is the intentional static compatibility exception; its entrypoint pin and integrity protocol are unchanged.
Tracked clones and updates distribute the modules without a deployment copier or automatic reload of running extensions.
`tests/harness-helpers.sh` installs the complete tracked dependency closure in isolated copied or symlink-shaped fixtures, without an ambient-checkout fallback.

## Test registration seam

`bin/fm-test-catalog-lib.sh` owns parsing and validating `tests/catalog/core.tsv` and `tests/catalog/fork.tsv`.
Its header owns the versioned record schema and the `fm_test_catalog_load`, `fm_test_catalog_get`, and `fm_test_catalog_maps` interface.
Core holds shared registrations; fork holds additions and explicit overrides that name the expected prior value.
Both catalogs are introduced by this fork, not interfaces already supplied by canonical upstream.

The catalog supplies classification, expected gate-skip classes, duration hints, and ordered changed-path registrations.
`bin/fm-test-run.sh` retains flat discovery, procedural reference expansion, scheduling, timeouts, worker privacy, coverage, and reporting.
Add a root-level test file and its fork registration rather than editing runner algorithms for an ordinary new test.
Add changed-source mappings when the test introduces or covers a new source owner, and retain unknown-source refusal rather than supplying a permissive fallback.

Registration does not confer concurrency permission.
`bin/fm-test-isolation-proof.sh` owns portable candidates and frozen family admissions; the runner consumes those results once per invocation and retains its family caps.
A new test can be classified into an existing family while remaining serial until it has the required proof.
Changes to a family assignment cannot reuse admission recorded for a different family.
[Isolation verification](../fm-test-isolation-proof.md) owns the evidence needed to change admissions.

The loader validates once with Bash and awk, then serves in-memory lookups without evaluating metadata as shell code.
Validated keys are encoded into Bash 3.2-compatible scalar entries, so lookups do not repeatedly scan or trim the complete TSV snapshot.
Each successful load replaces the prior cache, including entries no longer present.
Missing dependencies or invalid records stop selection explicitly.
`tests/catalog-helpers.sh` installs the real loader and a minimal, valid dependency set for synthetic fixtures; it is not a production fallback or alternative registry.
Tracked-only clones carry the catalogs and loader, and `.gitattributes` preserves the catalogs' LF format on Windows.

## Private-path seam

`bin/fm-private-path-lib.sh` owns bounded native dispatch, path-data transport, batching, and retries through the interface in its header.
`bin/platform/windows-private-path.ps1` is the native ACL implementation owner; its header identifies the deliberately different PR, X, worker, and Herdr policies.
The Bash module caches only the converted location of that tracked PowerShell code, never a target's identity, permissions, or validation result.
The helper is loaded in the existing native invocation, without a second PowerShell bridge or per-item native calls for PR batches.

`bin/fm-pr-lib.sh`, `bin/fm-x-lib.sh`, `bin/fm-test-run.sh`, and `bin/backends/herdr.sh` retain their public helper names and platform detection.
They still own POSIX modes, ownership where required, device and link checks, publication ordering, lock identity, worker allocation, and rollback.
Extraction does not make their policies interchangeable or move transaction authority into the platform module.
Native failures remain refusals; a missing tracked dependency is not permission to reuse an earlier verdict or fall back to synthetic Windows modes.

`tests/private-path-helpers.sh` installs both tracked dependencies in copied and symlink-shaped test roots.
Production deployment continues to use the tracked repository layout rather than a generated copy or an ambient-checkout fallback.

## Remaining integration patches

The runner retains compatibility functions that delegate metadata queries, the procedural dependency/reference scan, and its execution algorithms.
The proof command retains the portable and family admission evidence independently of editable registration metadata.
The lint owner includes the fork module directories in full and changed mode, while changed-reference discovery includes their shell, module, declaration, and PowerShell files.
These are deliberate integration patches until upstream accepts compatible seams; moving implementation does not make the fork delta disappear.

[Fork verification](verification.md) owns CI ownership and repeatable checks.
The remaining delivery sequence follows the [implementation plan](upstream-plan.md).

## Process and native transport seam

`bin/platform/process.mjs` owns the overlapping Pi/OpenCode process implementation, with its typed interface in `bin/platform/process.d.mts`.
The existing `.pi/extensions/lib/fm-process-ancestry.ts` and `.opencode/plugins/lib/fm-process-ancestry.js` paths re-export their original export sets.
Pi retains `shellVisibleProcessPid` and `pidAlive`; OpenCode does not acquire those additional exports.
Both wrappers use the same functions rather than generated implementations, while lifecycle decisions remain in their extension/plugin callers.

The module retains per-instance Windows ancestry caching, verifies native liveness on every ancestry query, and takes fresh process rows for ordinary PID liveness.
`bin/platform/windows-process.ps1` owns native watch-arm root discovery and batched descendant termination in the same PowerShell invocation.
Graceful cleanup still finds the owned MSYS root and sends TERM through Bash before callers choose their existing escalation path.
Forced cleanup preserves the existing direct-PID TERM fallback after a native operation fails; this is not authority to terminate an arbitrary process, and callers must retain their owned-child and generation checks.
A missing tracked native helper throws explicitly before any native operation or direct-PID fallback.

`bin/fm-platform-process-lib.sh` owns generic Bash process facts, single-PID image queries, and literal PowerShell command rendering without a Node dependency.
`bin/fm-session-lock-lib.sh` retains ownership and ancestry orchestration, delegating Copilot marker verification and PID-result caching through the harness interface.
`bin/backends/herdr.sh` retains leases, worktree acquisition, presentation, and rollback; its public transport functions and spawn's quoting function delegate to the shared module.
Git Bash callers retain their inexpensive PATH/cygpath lookup, while existing PowerShell entrypoints continue using `bin/fm-windows-git-bash.ps1`.

`tests/process-helpers.sh` installs the complete tracked process dependency in repository-shaped fixtures.
Pi type checks preserve that shape rather than flattening libraries, and the Calm rendering fixture places its extensions at the same relative depth.
Fresh clones and linked worktrees carry the implementation through ordinary tracked files; no deployment copier, symlink requirement, ambient-checkout fallback, or running-extension reload is introduced.

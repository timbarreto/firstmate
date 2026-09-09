# Fork module architecture

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

## Remaining integration patches

The runner retains compatibility functions that delegate metadata queries, the procedural dependency/reference scan, and its execution algorithms.
The proof command retains the portable and family admission evidence independently of editable registration metadata.
The lint owner includes the fork module directories in full and changed mode, while changed-reference discovery includes their shell, module, declaration, and PowerShell files.
These are deliberate integration patches until upstream accepts compatible seams; moving implementation does not make the fork delta disappear.

[Fork verification](verification.md) owns CI ownership and repeatable checks.
The runtime module extractions and Copilot/Pi pilot in the [implementation plan](upstream-plan.md) are separate delivery slices, not interfaces introduced by the test catalog.

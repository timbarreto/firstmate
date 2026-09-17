# Metadata-selector optimization: no qualified latency result

Evidence for [Remove nested metadata selector substitutions](https://github.com/timbarreto/firstmate/pull/64), the first candidate from [Small, verified Windows latency wins for Firstmate](https://github.com/timbarreto/firstmate/issues/59).
The resolution in [Agree safe changes, acceptance checks, and PR order](https://github.com/timbarreto/firstmate/issues/62#issuecomment-5705242312) requires repeatable end-to-end Windows benefit, not only a smaller subprocess count.

**The implementation and correctness checks succeeded, but performance qualification did not complete.**
The unchanged base returned an incomplete task observation during the first qualification warmup.
There are **zero measured qualification samples** and no valid median, p95, or paired-win result.
The candidate is not qualified for landing under the agreed keep/drop rule; its code and evidence remain preserved rather than being broadened or represented as a verified speedup.

## Frozen inputs and scope

| Input | Identity |
| --- | --- |
| Actual base, including the reader-correctness prerequisite | `1695ad36f8c78db3a225b9205f38bba840d3b64e` |
| Candidate / exact CI head | `a8c23d7e86f33c650a2798537552e943a69406c5` |
| Frozen attribution and qualification driver | `6acc496c95e082ebd01004eec69b02722c2241c2` |
| Base code root | `C:/src/firstmate-base-metadata-helpers-v2` |
| Candidate code root | `C:/src/firstmate-perf-metadata-helpers-v2` |

The code roots are new sibling working copies with equal 41-character paths.
Only `fm_backend_of_meta` and `fm_backend_target_of_meta` change in production.
The existing destination-variable reader replaces nested command substitutions while retaining separate fresh reads, ordering, defaults, Orca fallback, literal values, output/status, and caller state.
No parser, busy-event path, runtime dependency, profile, global PATH, security setting, deadline, or concurrency admission changed.
No existing working copy was repurposed as a benchmark home, and no live fleet or vendor session was operated.

The task-scoped [run.sh](run.sh), [measure.mjs](measure.mjs), and [trace-hook.sh](trace-hook.sh) reuse the reporting fixture builder, entrypoints, timer boundaries, process controls, and separate Bash attribution from the [frozen baseline packet](https://github.com/timbarreto/firstmate/tree/82fe66d0f349e520c8bd91617e49934f0b7bb1bb/evidence/windows-workflow-baseline).
The historical packet is unchanged.
Both versions share the same byte-checked, read-only empty/three-task inputs, with Copilot/Pi/Copilot records and deliberately absent worktrees/endpoints.
Per-operation output, versions, source and fixture digests, timestamps, and aggregate host-load observations are retained in the manifests and raw files.

## Correctness and CI

All four new focused native Windows cases passed through `bin/fm-test-run.sh`:

- `test_backend_metadata_selection_stays_in_process` was first observed red on the pinned base, then green after the change.
- `test_backend_metadata_values_preserve_caller_state` covers literal/default/duplicate/empty/unterminated values and caller preservation.
- `test_backend_metadata_selection_rechecks_between_reads` exercises actual EOF-bound replacement and removal without combining read phases.
- `test_backend_metadata_read_errors_do_not_abort_callers` retains the separately fixed I/O-error behavior through both selectors.

Branch/workflow lint and explicit source-aware lint passed with pinned ShellCheck and actionlint.
The [local check records](packet/local-checks/) include the red/green progression and intermediate lint diagnostics, not just the final passes.

All **20 distinct automatic CI checks succeeded on the exact candidate head**, including portable regression, the native Windows checks, actual stock macOS Bash 3.2, and installed-package compatibility:

- [Shared CI](https://github.com/timbarreto/firstmate/actions/runs/35172849676)
- [Fork CI](https://github.com/timbarreto/firstmate/actions/runs/35172849718)
- [Exact-head check inventory](packet/ci-checks.json)

CI correctness and compatibility do not establish the missing Windows latency benefit.

## Separate partial attribution

The attribution run completed all ten version/scenario combinations with the stronger completed-observation and immutable-input assertions.
It ran on native Windows with tracing enabled, separately from qualification timing.

| Scenario | Observed Bash entries, base / candidate | Observed Bash contexts, base / candidate | Observed jq evaluations, base / candidate |
| --- | ---: | ---: | ---: |
| Empty Bash control | 1 / 1 | 1 / 1 | 0 / 0 |
| Empty canonical snapshot | 1 / 1 | 30 / 30 | 12 / 12 |
| Three-task canonical snapshot | 4 / 4 | 183 / 159 | 18 / 18 |
| Empty Bearings | 3 / 3 | 47 / 47 | 14 / 14 |
| Three-task Bearings | 6 / 6 | 200 / 176 | 20 / 20 |

The two populated operations each remove **24 observed Bash contexts**.
These are partial Bash observations, not a native process census; Bash entries, contexts, and command evaluations are different, non-additive measures.
The counter uses the baseline packet's algorithm in [summarize-counts.mjs](summarize-counts.mjs).
[Parsed observations](packet/counts/analysis.json), [compressed runtime traces](packet/counts/traces/), and [all attribution output](packet/counts/outputs/) retain the evidence.
The timing fields in the attribution files are instrumented durations and must not be promoted into performance results.

## Qualification stopped during warmup

The first qualification attempt was configured for the specified three warmup pairs and twenty measured pairs per scenario, with serial execution, alternating first version, and interleaved controls.
The driver stopped on the first incomplete observation instead of accepting degraded output, removing the failure, or repeating until successful.

- The first timed warmup started at `2026-09-17T02:09:55.032Z`.
- Six version-level warmups completed: one control pair, one empty-snapshot pair, and one empty-Bearings pair.
- The **base** three-task snapshot warmup started at `2026-09-17T02:10:50.159Z` and returned after `41137.4377 ms`.
- Its exit status was zero and its JSON contained three records, but `task-1.current_state.raw` and `.detail` were empty instead of the expected completed `worktree gone (torn down?)` observation.
  The other two task observations completed.
- The completed-observation assertion rejected this output.
  No corresponding candidate primary operation or measured pair was recorded.

The snapshot owner folds an empty/failed current-state read into an `unknown` record and suppresses the underlying child error.
The saved packet therefore does **not** distinguish the unchanged ten-second per-task bound being reached from another child-execution failure.
No specific operating-system, security-product, storage, or competing-process cause was established.
The failed operation observed approximately 69.8% aggregate host CPU busy time; the host was not reserved and no other activity was inspected or changed.

[Raw qualification rows](packet/qualification/batch-1/samples.jsonl), [failure record](packet/qualification/batch-1/failure.json), [manifest](packet/qualification/batch-1/manifest.json), and [rejected snapshot output](packet/qualification/batch-1/outputs/snapshot-small-base--3.stdout.txt) preserve the complete attempt.
There was no second qualification batch or rescue rerun.
The failure occurred in the unmodified base, so it is an unavailable comparison, not evidence that the candidate introduced a correctness regression.

The earlier [single-pair smoke run](packet/smoke-1/) used an older driver and unequal-depth source paths, before the stronger completed-observation checks.
It is smoke evidence only, never a latency comparison or acceptance result.

## Commands and disposition

The exact frozen-driver invocations were:

```bash
ARTIFACT=/c/src/.fm-perf-runs/metadata-helpers-v2/evidence/evidence/windows-metadata-helpers
BASE=/c/src/firstmate-base-metadata-helpers-v2
CANDIDATE=/c/src/firstmate-perf-metadata-helpers-v2
OUT=/c/src/.fm-perf-runs/metadata-helpers-v2

WF_TRACE=1 bash "$ARTIFACT/run.sh" "$BASE" "$CANDIDATE" "$OUT/counts"
WF_TRACE=0 WF_WARMUPS=3 WF_SAMPLES=20 \
  bash "$ARTIFACT/run.sh" "$BASE" "$CANDIDATE" "$OUT/batch-1"
```

The output directories are retained evidence; the driver refuses to overwrite them.
A future attempt would need separate authorization and fresh isolated inputs, not a repeated qualification run solely to obtain a pass.

The original criterion still requires both populated operations to improve by at least **5% AND 500 ms**, win at least **15/20 pairs**, and have non-increasing sample p95 in **each of two complete batches**; both empty regression scenarios also require non-increasing p95.
None of those timing requirements is established by this packet.
No speedup, live-vendor improvement, or SLA is claimed.

# Busy-event path cleanup: CI green, latency not qualified

Evidence for [Remove busy-event path-formatting subprocesses](https://github.com/timbarreto/firstmate/pull/65), the second candidate from [Small, verified Windows latency wins for Firstmate](https://github.com/timbarreto/firstmate/issues/59).
The resolution in [Agree safe changes, acceptance checks, and PR order](https://github.com/timbarreto/firstmate/issues/62#issuecomment-5705242312) is the acceptance authority.

**All 20 automatic CI checks passed on the final head, but neither complete Windows timing batch qualified.**
The patch removes three observed Bash child contexts from each measured lifecycle operation without changing its fixture results.
That deterministic cost reduction did not establish the required consistent end-to-end latency improvement.
The PR remains available as a draft, not a verified latency win or an authorized merge.

## Scope and frozen identities

| Input | Identity |
| --- | --- |
| Actual base, including the merged metadata-helper change | `0716ecdcb5b5e81654ef102eb471c2a04320f508` |
| Final candidate / exact CI and qualification head | `91a8d6dda8b6f15b80d1a105c0959a652d264f8b` |
| Frozen qualification driver | `9aa87056d6eb1827fdd23bcf7ec552b06755f11d` |
| Base code root | `C:/src/firstmate-base-busy-event-helpers` |
| Candidate code root | `C:/src/firstmate-perf-busy-event-helpers` |

Both source copies began as clean, equal-length siblings; the post-run untracked-cache limitation below is separate from their unchanged tracked source.
The prior metadata change is present in both versions and is not credited to this patch.
Production changes are only the quoted record/generation path assignments in `bin/fm-busy-event.sh` and the inner path assignment in `fm_busy_current_gen` in `bin/fm-busy-lib.sh`.
No parser, callback, public interface, Bash executable, login flag, dependency, profile, global PATH, security setting, deadline, or concurrency admission changed.
Generation binding, ordering, locking, sequence advancement, publication, writer umask, progress, and retirement retain their original owners.

### One proposed substitution deliberately omitted

The prior-record `head` read remains.
A real NUL-containing input demonstrated that the proposed built-in `read` replacement would silently discard an existing modern-Bash command-substitution warning.
The writer's existing sequence result remains available even for this malformed input.
The new executable characterization preserves that outcome, including stock Bash 3.2's absence of the newer warning.
This follows the plan's rule to leave out an individual substitution that cannot preserve behavior, rather than introducing another parser or normalizing the input.
[Original observations](packet/local-checks/nul-characterization/) and the permanent regression retain the evidence.

## Correctness and CI

The existing busy-state suite now supports named cases and retains its original unfiltered case order.
Its additions execute the public reader/writer and cover cost, first-line behavior, unterminated generation refusal versus unterminated prior-record acceptance, malformed and duplicate values, literal relative paths, caller state, real read failures, replacement while waiting for the lock, and publication under the lock/private umask.
The current-generation cost test was observed red before its assignment change, then green.
The controlled writer apply starts at 13 observed child-shell contexts on the base, has 12 after just the reader change, and passes its budget of 10 after the complete patch.

The new Copilot case consumes actual generated PowerShell hook commands and reaches the existing Bash owner and real writer.
It checks literal paths, busy/idle sequence, submission acknowledgements, turn-ended notification, stale events, and unarmed refusal without starting Copilot.
The new behavior characterizations and native Copilot case passed on both production versions; base tests used a separate source archive with a test overlay, never the clean timing copy.
The existing full harness-contract and Pi Windows shell suites, selected generated Pi/Copilot real-writer lifecycle cases, Bash worker lifecycle, workflow selection, coverage guard, ordinary lint, and source-aware lint also passed locally.

[Exact-head CI inventory](packet/local-checks/final-ci.json) contains 20 distinct successful automatic checks:

- [Shared CI](https://github.com/timbarreto/firstmate/actions/runs/35180526200)
- [Fork CI](https://github.com/timbarreto/firstmate/actions/runs/35180526099)
- [Actual stock macOS Bash 3.2 execution](https://github.com/timbarreto/firstmate/actions/runs/35180526200/job/105071473643), including the full busy-state suite
- [Windows busy-state characterizations](https://github.com/timbarreto/firstmate/actions/runs/35180526099/job/105075527667)
- [Executed native Copilot case](packet/local-checks/windows-management-attempt-1.log)

Limits and failed attempts remain visible in [local/CI records](packet/local-checks/):

- The full local Windows busy-state walk exceeded its unchanged 180-second bound during pre-existing cases, before reaching the additions.
  Focused cases passed; that interrupted full walk is not reported as a pass.
- The initial native test used PowerShell's `-File` mode rather than consuming the generated command.
  That probe exited 2 on both production versions; the generated command path completed correctly.
  The fixture was corrected, with no production transport change.
- The first PR head failed one new stock-Bash assertion after a custom IFS, intended for the changed generation-reader seam, leaked into the unmodified full-record parser's test setup.
  Isolating that setup to its intended seam made the complete stock-Bash suite pass on the final head.
- The final head's first Windows core job reached its unchanged ten-minute job limit without available job logs.
  One failed-job rerun passed on the same code and limits; the underlying cause of that timeout was not established.
- The pinned package job executed its Pi 0.84.3 type checks and other compatibility cases.
  Its existing stock-renderer comparison explicitly skips because that case requires Pi 0.84.4.
  This is missing evidence for that particular comparison, not a pass of it; package pins and gates were not changed.

## Separate partial Bash attribution

[Final attribution](packet/counts-final/analysis.json) used the same frozen driver as qualification, with tracing enabled in a separate one-pair run.
The [compressed traces](packet/counts-final/traces/) and archived per-operation output preserve the observations.

| Operation | Bash entries, base / candidate | Observed Bash contexts, base / candidate | Observed `head` evaluations, base / candidate |
| --- | ---: | ---: | ---: |
| Pi busy | 1 / 1 | 14 / 11 | 1 / 1 |
| Pi idle | 1 / 1 | 14 / 11 | 1 / 1 |
| Pi progress helper | 1 / 1 | 12 / 9 | 0 / 0 |
| Copilot busy worker hook | 2 / 2 | 20 / 17 | 1 / 1 |
| Copilot idle worker hook | 2 / 2 | 19 / 16 | 1 / 1 |

These measures are partial Bash observations, not a native process census, and are not additive.
The retained `head` call is intentional.
The [offline counter](summarize-counts.mjs) reuses the historical packet's algorithm.
Instrumented durations in these files are not qualification timing results.

## Two complete matched Windows batches

Each batch contains three warmup pairs and twenty measured base/candidate pairs for each of five workflows and two controls.
The operation order rotates, the first version alternates on successive paired rounds, and Bash/PowerShell controls are interleaved.
Both versions share each fixture's state path and seed; reset, setup, assertions, output capture to artifacts, and cleanup are outside the timer.
The operation's own shells/helpers and their completion remain inside it.

The [driver](https://github.com/timbarreto/firstmate/tree/9aa87056d6eb1827fdd23bcf7ec552b06755f11d/evidence/windows-busy-event-helpers) reuses the [historical packet](https://github.com/timbarreto/firstmate/tree/82fe66d0f349e520c8bd91617e49934f0b7bb1bb/evidence/windows-workflow-baseline)'s real arm/renderer fixture and Pi callback-to-helper-close boundary.
The added Copilot scenarios execute the generated PowerShell worker commands with a synthetic nonempty JSON object on stdin, covering payload forwarding without asserting a new vendor-emitted schema.
Each successful fixture operation must preserve generation, advance the expected sequence, produce the exact state/source/event, and have only its expected submission/notification/progress effects.
All 644 version-level fixture operations passed those completion assertions: 560 measured operations and 84 warmups.
[Offline audit](packet/qualification-audit.json) independently checks pair order, denominators, stdout digests, midpoint medians, nearest-rank p95, maxima, and acceptance calculations.

A primary qualifies only when its median improves by **at least 10% AND 100 ms**, it wins **at least 15/20 pairs**, and its sample p95 does not increase, in **each** batch.
Pi progress has no required median saving but must retain non-increasing p95 in both batches.
Positive reductions below mean faster; negative reductions mean slower.
Values are milliseconds, rounded only for presentation.

| Batch | Scenario | Median base / candidate | Reduction ms (%) | Faster pairs | Sample p95 base / candidate | Qualified |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Pi busy | 3165.5 / 3287.7 | -122.2 (-3.9%) | 12/20 | 6508.8 / 4728.4 | No |
| 1 | Pi idle | 3792.3 / 2876.8 | 915.5 (24.1%) | 11/20 | 4573.1 / 4696.3 | No |
| 1 | Copilot busy | 7431.0 / 7206.8 | 224.2 (3.0%) | 13/20 | 9859.3 / 8010.8 | No |
| 1 | Copilot idle | 7789.9 / 6527.2 | 1262.7 (16.2%) | 14/20 | 9632.1 / 8573.7 | No |
| 1 | Pi progress helper | 2131.7 / 2417.3 | -285.6 (-13.4%) | 10/20 | 3515.8 / 4498.2 | No (regression scenario) |
| 2 | Pi busy | 3320.4 / 3419.9 | -99.5 (-3.0%) | 11/20 | 4587.0 / 5533.9 | No |
| 2 | Pi idle | 3344.4 / 2806.0 | 538.4 (16.1%) | 8/20 | 5030.1 / 5992.1 | No |
| 2 | Copilot busy | 6415.9 / 7164.4 | -748.6 (-11.7%) | 10/20 | 8033.2 / 8950.1 | No |
| 2 | Copilot idle | 7025.0 / 6935.8 | 89.2 (1.3%) | 9/20 | 9851.3 / 10937.5 | No |
| 2 | Pi progress helper | 2662.8 / 1996.8 | 665.9 (25.0%) | 13/20 | 3895.9 / 3335.6 | Passes this batch only |

No primary reached 15/20 faster pairs in either batch.
The second batch was the second originally prescribed batch, not a rerun of the first, and cannot override its result.
Neither batch qualifies the PR.

### Controls and host conditions

| Batch | Control | Median base / candidate | Sample p95 base / candidate |
| --- | --- | ---: | ---: |
| 1 | Empty Bash | 120.6 / 125.8 | 616.8 / 1247.3 |
| 1 | Empty PowerShell | 421.1 / 502.3 | 1162.7 / 928.5 |
| 2 | Empty Bash | 108.8 / 183.4 | 744.7 / 846.0 |
| 2 | Empty PowerShell | 403.2 / 454.4 | 1630.8 / 1605.2 |

The same non-reserved Windows host reported OS `10.0.26200`, x64, 16 logical CPUs, and AMD EPYC 7763.
Batch 1 ran from `2026-09-17T04:27:05.369Z` to `04:46:49.179Z`, with 64.85% aggregate host CPU busy time.
Batch 2 ran from `04:49:35.429Z` to `05:08:55.925Z`, with 60.19% aggregate host CPU busy time.
Tools were Node `24.19.0`, Git `2.55.0.windows.5`, Bash `5.3.15(2)-release`, Windows PowerShell `5.1.26100.9444`, jq `1.8.2`, and Perl `5.42.3`.
The existing Copilot resolver selected `C:\Program Files\Git\bin\bash.exe`.
Manifests retain exact versions, paths, path digests, generated artifacts, seeds, and per-operation load observations.
No other processes or private fleet state were inspected, and no machine setting was adjusted.

Post-run inspection found an untracked `Microsoft/Windows/PowerShell/ModuleAnalysisCache` file only in the candidate source copy, created at `2026-09-17T05:08:11.093Z` during the second batch.
The driver verified tracked source and fixture state but did not cover this additional runtime-cache location, so it does not establish equivalent cache state for every operation.
[File metadata](packet/local-checks/runtime-cache-observation.json) is retained; the contents were neither read nor published, and the file was moved to private task artifacts after both batches.
No sample was deleted or remeasured, and no causal attribution to the optimization or a particular delay is made.
This is an additional comparison limitation, not grounds for treating the results as qualifying.

The controls and tails are variable, but no specific external cause is established and no control time was subtracted.
All maxima remain in the raw summaries, including the candidate's 26,115.2 ms Copilot-busy completion in batch 2.
Six measured Copilot fixture completions exceeded the generated hook's unchanged ten-second vendor configuration.
The fixture observes native command completion without launching the vendor or enforcing its outer timeout, so these are retained slow **fixture completions**, not proof that a live vendor would accept them.
Pi progress measures background helper completion, not synchronous callback blocking.
This packet establishes neither a population regression nor a production latency SLA, and claims no live-vendor improvement.

## Raw packet and reproduction

[Batch 1](packet/batch-1/) and [batch 2](packet/batch-2/) each retain the manifest, every row including warmups, summary including maxima, generated artifacts, and `outputs.tar.gz` containing every operation's stdout, stderr, and state snapshot.
The archive stores exact file bytes; owner IDs are normalized, and the archives were unpacked and audited again before publication.
Use [audit-results.mjs](audit-results.mjs) against the original output directories, or unpack each archive into its corresponding packet directory first.

The earlier [smoke-1](packet/smoke-1/) and [counts](packet/counts/) runs used the prior driver without nonempty Copilot payload forwarding.
[Smoke-2](packet/smoke-2/) and [counts-final](packet/counts-final/) use the final frozen driver.
None is substituted for qualification, and all attempts remain retained.

The following commands were executed with the driver at the frozen commit:

```bash
ROOT=/c/src/.fm-perf-runs/busy-event-helpers
DRIVER="$ROOT/evidence/evidence/windows-busy-event-helpers/run.sh"
BASE=/c/src/firstmate-base-busy-event-helpers
CANDIDATE=/c/src/firstmate-perf-busy-event-helpers

WF_TRACE=0 WF_WARMUPS=3 WF_SAMPLES=20 \
  bash "$DRIVER" "$BASE" "$CANDIDATE" "$ROOT/batch-1"
WF_TRACE=0 WF_WARMUPS=3 WF_SAMPLES=20 \
  bash "$DRIVER" "$BASE" "$CANDIDATE" "$ROOT/batch-2"
```

The driver refuses existing output directories and requires clean pinned source copies.
There was no outlier deletion, incomplete operation counted as fast completion, control subtraction, third qualification batch, or threshold relaxation.
Any later measurement or changed acceptance decision is separate work, not an automatic retry until a pass.

# Windows workflow baseline packet

Evidence for [Measure real Windows workflows for Copilot and Pi](https://github.com/timbarreto/firstmate/issues/60), under [Small, verified Windows latency wins for Firstmate](https://github.com/timbarreto/firstmate/issues/59).
This is a measurement prerequisite, not an optimization selection or implementation.
No production source, installed shell profile, global PATH, security setting, or production deadline was changed.
No live Firstmate home, vendor conversation, or fleet was operated.

## Result and evidence boundaries

- The accepted series contains **396 successful measured samples**, comprising 304 workflow samples and 92 interleaved process controls.
  Another 60 successful warmups are excluded from the statistics.
- There are 24 separately traced cases, including controls, with **partial Bash accounting**, not a complete native process census.
  Instrumented durations are not used in the latency results.
- Empty startup, local snapshot/Bearings, Copilot command checks and healthy Stop, Pi generated callbacks and primary command checks, and simulated-endpoint relaunch were measured through their real Firstmate entrypoints.
- The three-task Pi startup attempt **did not complete** within the unchanged 120-second production bound.
  Its 124.032-second return delivered a truncated digest, not a successful workflow latency.
  No successful populated-startup median is available; the populated Copilot startup variant was not subsequently measured.
- Native PowerShell Copilot repair dispatch did not accept the existing fixture's simulated process identity.
  It is excluded from successful timings.
  The separately labelled **Bash repair entry** succeeded; it is not a substitute measurement of the native repair bridge.
- These are controlled Windows execution results, **not live Copilot/Pi responsiveness, a speedup, or an SLA**.
  Startup and relaunch include deliberate fixture substitutes whose own shell launches affect absolute cost.

The machine-readable [analysis](packet/analysis.json) indexes timings, partial counts, and startup stage timings.
[Raw timing runs](packet/timings), [separate attribution runs](packet/counts), and [limitations](packet/limitations) retain the supporting observations.
Each passing timing directory has its command/environment manifest, all warmup and measured samples, summary, and representative stdout/stderr.
Captured operating instructions and paths are fixture output, not instructions to operate any home.
Account names in manifests and trace text were redacted before publication; controlled fixture paths and timing values were retained.
Trace text was then gzip-compressed, and `analysis.json` was recomputed from the published evidence.

## Frozen inputs and host

| Item | Observed value |
| --- | --- |
| Code base for every accepted run | `8f5f494f08f454901054c465a80c1de08ad1819e` |
| Accepted timing window | 2026-09-16, 18:47:51-19:57:27 UTC |
| Windows / architecture | `10.0.26200`, x64 |
| CPU / RAM | AMD EPYC 7763, 16 logical processors exposed, 64 GiB RAM |
| Native Node | `v24.19.0` |
| Git for Windows | `2.55.0.windows.5` |
| Bash | GNU Bash `5.3.15(2)-release`, `x86_64-pc-cygwin` |
| Windows PowerShell | Desktop `5.1.26100.9444`, no profile |
| Perl / awk / jq | `5.42.3` / GNU Awk `5.4.1` / `jq-1.8.2` |
| cygpath / strace | Cygwin `3.6.10` |
| Native Node's first `bash` resolution | `C:\Program Files\Git\usr\bin\bash.exe` |

The code was checked out in a new isolated working copy.
The original `firstmate` working copy remained clean and was not used as an operational home.
Copilot and Pi executables are fixture stubs in the relaunch and startup worlds, so their installed vendor versions are not benchmark inputs or newly verified vendor evidence.
Pi callback measurements execute actual generated TypeScript and the tracked primary extension under native Node, with a manually supplied event-registration interface, not an installed vendor session.

The host was not idle or reserved.
Aggregate CPU busy time over each accepted family was 41.3% for Copilot, 40.2% for Pi, 54.9% for reporting, 57.1% for empty startup, and 52.9% for relaunch.
Per-sample CPU observations, timestamps, PATH entry counts/fingerprints, exact temporary paths, and explicit environment overrides are in the manifests and samples.
The host's other activity was neither inspected nor changed.
No attribution to endpoint protection, storage, scheduling, or a particular competing process was established.

## Timing method

`run.sh` loads the existing suite's fixture builders with the test-case dispatcher disabled; it does not time a test-suite walk.
The copied production files and actual executable owners come from the frozen code base.
Fixture creation, Git setup, state restoration, assertions, and cleanup are outside the operation timer.
The Node timer starts immediately before process launch or an already-loaded extension callback and ends at the defined completion below.
It includes shells and helpers launched on that measured path.

Runs are serial.
Every round rotates the scenario order, including the controls, rather than timing all controls and then all workflows.
The short/reporting families have three warmup rounds and 20 measured rounds; empty startup and relaunch have one warmup round and six measured rounds.
There is no outlier removal or subtraction of the empty-shell control.
The median is the conventional midpoint median; p95 uses nearest rank.
The six-sample series report **maximum observed latency**, not a dependable p95 estimate.
First-half and second-half medians are retained in `analysis.json` to expose variation within a series.

| Surface | Timed entry and completion | Fixture / unavailable behavior |
| --- | --- | --- |
| Startup | Fresh Bash running `bin/fm-session-start.sh` through process close and complete digest | Existing `fm-session-start` world/toolchain/ancestry builders; manual backlog, no real agents or projects, stubbed tools/network; empty homes reset before each run |
| Snapshot | `bin/fm-fleet-snapshot.sh --json` through complete output | Existing startup-performance three-task shape; missing worktrees/endpoints deliberately produce `unknown`, not invented live state |
| Bearings | `bin/fm-bearings-snapshot.sh --json` through complete projection | Same empty/three-task inputs; no `--include-prs`, no live forge reads; TOON rendering itself was not timed |
| Status fold | Fresh Bash sources `fm-classify-lib.sh` and calls `status_open_decisions` | One unanswered decision plus 200 routine lines; exact surviving decision asserted |
| Copilot command | Fresh PowerShell runs `fm-ghcp-hook.ps1 pretool arm` through exit/output | Real native Node policy, allowed `printf fixture` and denied `bin/fm-watch-arm.sh &`; submitted command text is never executed |
| Copilot healthy Stop | Fresh PowerShell runs `fm-ghcp-hook.ps1 primary-stop` through exit | Existing primary fixture supplies a healthy observation; actual Stop dispatch/payload/scope path, but not a real health or ownership verdict |
| Copilot repair entry | Fresh Bash runs `fm-ghcp-hook.sh primary-stop` through a block response | Existing simulated loader identity and simplified lock/diagnostic helpers; ledger count and absence of watcher launch asserted; **not the native PowerShell repair path** |
| Pi busy / idle | Actual generated `agent_start` / idle `agent_settled` callback through its real helper exit | Native Bash and real `fm-busy-event.sh`; sequence increment and semantic record asserted; extension import and arming excluded |
| Pi progress | Actual generated progress event through real helper exit | Accepted event, real generation-bound progress file; throttle spacing is outside the timer; **fire-and-forget work completion, not synchronous callback blocking time** |
| Pi command checks | Tracked primary extension `tool_call` through allow/deny result | Real cd/arm shell owners and policy; manually delivered event, no model/tool execution; same allowed/denied strings as above |
| Relaunch | `bin/fm-control.sh <id> relaunch --note ...` through completed transaction and recorded launch delivery | Existing `fm-control-relaunch` worktree/task builders and simulated tmux endpoint; real Git, publication and generated wiring, no actual vendor start/readiness |

The three reporting records use Copilot, Pi, and Copilot respectively, one unresolved status decision each, and the existing literal-data/PR-URL fixture fields.
Both startup flavors use the suite's simulated harness ancestry and fake external toolchain.
Their complete digests intentionally disclose missing `tasks-axi`/`quota-axi`; the Pi fixture also discloses that real extensions are not loaded.
A complete digest is not a claim that this synthetic home passed real setup verification.
After each startup timer, the driver waits for the deferred stage's terminal/finished record and the summary publication, then allows one second for tail cleanup before starting another timed operation.
That settling procedure is not a kernel-level proof that every descendant has exited.
Startup traces include the deferred work and are not an inline-only process count.

Relaunch restores its task records and fake endpoint before each sample and verifies `phase=complete`, replacement wiring, and literal launch delivery.
It retains the existing fixture's 0.01-second poll, 0.05-second exit/launch waits, and no-sleep endpoint stub.
Those are fixture mechanics, not measurements of real vendor waits or permission to change production deadlines.

## Latency results

All values below are milliseconds, including the process controls.

| Measured operation | n | Median | Sample p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Copilot native command: allow | 20 | 715 | 1,183 | 1,679 |
| Copilot native command: deny | 20 | 824 | 1,571 | 1,712 |
| Copilot native healthy Stop | 20 | 1,604 | 2,239 | 2,921 |
| Copilot Bash repair entry | 20 | 3,910 | 5,124 | 6,436 |
| Pi generated busy event | 20 | 1,681 | 2,603 | 3,309 |
| Pi generated idle event | 20 | 1,270 | 2,337 | 2,932 |
| Pi generated progress helper completion | 20 | 1,110 | 1,920 | 2,204 |
| Pi primary command checks: allow | 20 | 319 | 979 | 1,817 |
| Pi primary command checks: deny | 20 | 1,066 | 1,964 | 2,197 |
| Status decision fold: 201 lines | 20 | 616 | 1,880 | 2,138 |
| Canonical snapshot: empty | 20 | 4,985 | 8,192 | 11,552 |
| Canonical snapshot: three tasks | 20 | 16,011 | 19,081 | 22,699 |
| Bearings JSON: empty | 20 | 7,766 | 10,763 | 10,909 |
| Bearings JSON: three tasks | 20 | 18,651 | 25,550 | 32,231 |
| Pi-flavored empty startup | 6 | 82,728 | - | 90,401 |
| Copilot-flavored empty startup | 6 | 71,309 | - | 78,498 |
| Copilot simulated-endpoint relaunch | 6 | 82,160 | - | 90,850 |
| Pi simulated-endpoint relaunch | 6 | 80,798 | - | 90,334 |

| Interleaved control | n | Median | Sample p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Empty Bash, Copilot series | 20 | 65 | 348 | 372 |
| Empty PowerShell, Copilot series | 20 | 267 | 540 | 556 |
| Empty Bash, Pi series | 20 | 71 | 354 | 619 |
| Empty Bash, reporting series | 20 | 71 | 343 | 884 |
| Empty Bash, startup series | 6 | 82 | - | 770 |
| Empty Bash, relaunch series | 6 | 65 | - | 375 |

Even the controls have substantial outliers.
For example, Pi busy's first/second-half medians are 1,916/1,503 ms, and the empty snapshot's are 4,846/6,332 ms.
Do not interpret nearby medians, different fixture families, or the two harness labels as a controlled comparison of implementations.
The packet establishes repeatable inputs and observed baseline costs, not how much any proposed change would save.

### Existing startup stage observations

The existing production stage timer, not extra tracing, recorded the following medians across the six complete empty-home runs.
The stage names and mechanics remain owned by `fm-session-start.sh`.
Medians do not add up to an end-to-end median.

| Completed stage | Copilot-flavored fixture | Pi-flavored fixture |
| --- | ---: | ---: |
| lock | 22,747 | 20,747 |
| bootstrap | 13,958 | 15,086 |
| wake-queue | 17,963 | 27,586 |
| supervision-instructions | 1,868 | 1,413 |
| fleet-state | 774 | 967 |
| network-checks / local harvest | 6,867 | 7,293 |
| context | 29 | 31 |

All stage records, including small output-only stages, are retained under [startup stage evidence](packet/timings/startup-empty/stages).
The local harvest stage is not a measurement of real network latency.

## Partial process and subshell accounting

An unprivileged Windows process-start subscription returned `Access denied`.
The installed `strace` also failed on a task-owned Bash/Node control with `0xc0000005` rather than yielding a usable descendant trace.
No privilege escalation, installation, or security-policy change was attempted.
A complete native process-start count is therefore **unavailable**.
The timer records the native PID of each directly launched entry process where applicable.

The fallback is one separate `BASH_ENV`/xtrace attribution run per case.
`trace-hook.sh` observes fresh noninteractive Bash entries, distinct `BASHPID` values, subshell depth, executed shell command evaluations, and source locations.
It is never enabled in the accepted timing series.
These are **partial observations**: native children outside Bash, the Git Bash launcher, untraced interpreters, and debugger-level fork/exec identity are not enumerated.
Command evaluations are not necessarily distinct native process starts, especially through fixture wrappers or `exec`.
Bash entry counts and context counts are different, non-additive measures.
The full counter algorithm is in `summarize.mjs`.

| Single traced case | Bash entries observed | Distinct Bash contexts observed | Selected external-command evaluations |
| --- | ---: | ---: | --- |
| Copilot native command allow / deny | 0 / 0 | 0 / 0 | No Bash observation; native Node execution is outside this tracer |
| Copilot native healthy Stop | 1 | 7 | 1 `jq`, 1 `git`, 1 `cat` |
| Copilot Bash repair entry | 4 | 24 | 2 `jq`, 1 `tasklist.exe`, 1 fixture `ps` |
| Pi busy / idle | 1 / 1 | 14 / 14 | Each: 3 `dirname`, 1 `uname`, 1 `head`, 1 `date`, 1 `mv` |
| Pi progress | 1 | 12 | 3 `dirname`, 1 `uname`, 1 `touch` |
| Pi command allow / deny | 2 / 2 | 4 / 14 | Allow: 1 `tr`, no Node policy launch; deny: 1 `node`, 1 `sed`, 2 `tr` |
| 201-line status fold | 1 | 4 | 1 `dirname`, 1 `uname`, no per-line external reader |
| Empty / three-task snapshot | 1 / 4 | 30 / 183 | 12 / 18 `jq`; three-task case enters `fm-crew-state.sh` three times |
| Empty / three-task Bearings | 3 / 6 | 47 / 200 | 14 / 20 `jq` |
| Empty Copilot / Pi startup, including deferred work | 56 / 58 | 743 / 825 | Includes fixture tool delegates and ancestry stubs; not live startup process totals |
| Copilot / Pi relaunch | 46 / 47 | 659 / 625 | Both include 37 simulated tmux entries and 24 `realpath` evaluations |

Counts are observations, not savings estimates.
In particular, multiplying subshell counts by an empty-shell median would not establish an application speedup.

## Owning call sites and already-existing fast paths

All source locations below refer to the frozen base.
They identify observed repeated work, not approved changes.

| Observed boundary | Owner / useful locations | Existing behavior that must not be claimed as new work |
| --- | --- | --- |
| Generated busy/idle/progress dispatch | `bin/harnesses/pi.sh:135-156`; `bin/fm-busy-event.sh:55,103-114,150,184,229`; `bin/fm-busy-lib.sh:98,177-184`; `bin/fm-harness-lib.sh:28` | Real callbacks already use Bash on Windows, settlement is guarded, progress is throttled and generation-bound; publication and writer locking stay with the busy owner |
| Pi's two command-check shell entries | `.pi/extensions/fm-primary-turnend-guard.ts:465-495,576-587`; `bin/fm-arm-pretool-check.sh:155-173,184-201` | Both policies already have conservative fast-allow prefilters; the allow sample does not launch Node; the arm prefilter still evaluates `tr` |
| Copilot native command dispatch | `bin/fm-ghcp-hook.ps1:8-19`; `bin/fm-copilot-command-check.mjs` | Native command checks already bypass Git Bash and share the arm/cd policy owners |
| Copilot healthy Stop | `bin/fm-ghcp-hook.ps1:33-36`; `bin/fm-copilot-stop.sh:48-70,145-169` | PowerShell already dispatches straight to Stop; the healthy no-counter branch avoids ownership-tree loading and a mutation lock; payload binding and the one late repair transaction are existing optimizations |
| Snapshot composition | `bin/fm-fleet-snapshot.sh:290,309-310,614-617,662-766,1693-1696`; `bin/fm-backend.sh:397-408`; `bin/fm-crew-state.sh:103`; `bin/fm-bearings-snapshot.sh:239-241` | Bulk/in-process metadata readers and reduced JSON-tool fan-out already exist; the measured three-task snapshot uses 18 `jq` evaluations, not a new per-field batching proposal |
| Status history | `bin/fm-classify-lib.sh:47-49` plus its decision fold | Routine-line filtering and in-process transition parsing already avoid a per-line subprocess walk; fresh status facts and decision semantics must remain |
| Startup composition | `bin/fm-session-start.sh`; `bin/fm-timing-lib.sh:124-130`; `bin/fm-wake-lib.sh:506-550`; `bin/fm-startup-network.sh:147,618` | Deferred work, read-once digestion, fresh ownership checks, and the existing startup/reporting cost optimizations are the baseline, not new proposals |
| Relaunch preparation/delivery | `bin/fm-control.sh`, `bin/fm-spawn.sh`; observed repeated sites include `bin/fm-backlog-transition-lib.sh:764`, `bin/fm-platform-process-lib.sh:38`, and `bin/fm-backend.sh:424` | Summary refresh is already deferred; lifecycle identity, leases, checkpoint/publication/rollback, and literal launch transport remain with their existing owners |

The directly measured callback entrypoints do not pass `--login`.
The relaunch fixture records rather than executes the delivered vendor launch string, so it establishes no launch-shell login cost.
The prior shell-only measurements therefore do not by themselves supply a safe drop-login or shorter-executable-path optimization for these workflows.

[Fork architecture](https://github.com/timbarreto/firstmate/blob/8f5f494f08f454901054c465a80c1de08ad1819e/docs/fork/architecture.md) and [fork verification](https://github.com/timbarreto/firstmate/blob/8f5f494f08f454901054c465a80c1de08ad1819e/docs/fork/verification.md) remain the contract and regression owners.
This packet neither changes those contracts nor supplies live-vendor evidence for changing an emitted-event or process-identity assumption.

## Limitations retained rather than repaired

### Populated startup

The original bounded series stopped during its warmup after the Pi three-task fixture returned a truncation banner.
Its completed-stage evidence was lock 22,685 ms, bootstrap 24,515 ms, and wake-queue 70,090 ms.
`supervision-instructions` was the current breadcrumb at timeout, **not a measured bottleneck**.
The missing stages included fleet-state and context.
The fixture represents recorded tasks with missing endpoints and no running monitoring, not a healthy populated fleet.
The limit was not increased, the fixture was not simplified to manufacture a pass, and the failed case was not repeatedly rerun.
[The failed series](packet/limitations/populated-startup) preserves the raw output and failure record separately from accepted summaries.

### Native Copilot repair fixture

The native PowerShell bridge returned no block response for the simulated loader, and the behavioral assertion rejected it.
A separate trace showed native loader validation rejecting the synthetic PID; the fallback `ps -W` observation did not supply the fixture row through this bridge.
The successful Bash entry uses the original suite's simulated identity boundary, but that does not prove native bridge equivalence.
The native failure is retained under [repair limitations](packet/limitations/native-copilot-repair); it was not fixed or promoted into a fast successful sample.

### Other exclusions

There is no live vendor session, backend responsiveness result, healthy populated fleet, remote ledger/forge timing, Linux/macOS execution, stock Bash 3.2 proof, or new compatibility claim here.
Native process totals remain unavailable as described above.
All source and fixture helpers must be checked for unchanged semantics before reusing this packet for a later before/after comparison.
A selected optimization that needs an unavailable boundary must obtain that evidence or be dropped; this prerequisite does not choose which.

## Repeat the comparison

Run from Git Bash against a **new isolated code working copy**, not an operational Firstmate home.
Use a fresh output directory every time.
The commands below preserve the existing successful scenario set and sample counts.
`ARTIFACT` is this directory from the evidence branch; `CODE` is the separately pinned baseline or comparison working copy.
The driver accepts native Windows or Git Bash paths, records the actual code SHA, and refuses tracked changes relative to that commit.

```bash
ARTIFACT=/c/src/path-to-evidence/evidence/windows-workflow-baseline
CODE=/c/src/path-to-isolated-code
OUT=/c/src/path-to-new-results

for family in copilot pi reporting; do
  WF_SAMPLES=20 WF_WARMUPS=3 \
    bash "$ARTIFACT/run.sh" "$CODE" "$OUT/timings/$family" "$family" || exit
done

WF_SAMPLES=6 WF_WARMUPS=1 \
  WF_ONLY=control-bash,startup-pi-empty,startup-copilot-empty \
  bash "$ARTIFACT/run.sh" "$CODE" "$OUT/timings/startup-empty" startup
WF_SAMPLES=6 WF_WARMUPS=1 \
  bash "$ARTIFACT/run.sh" "$CODE" "$OUT/timings/relaunch" relaunch

# Separate counts, never mixed into the latency series.
for family in copilot pi reporting relaunch; do
  WF_TRACE=1 bash "$ARTIFACT/run.sh" "$CODE" "$OUT/counts/$family" "$family" || exit
done
WF_TRACE=1 WF_ONLY=control-bash,startup-pi-empty,startup-copilot-empty \
  bash "$ARTIFACT/run.sh" "$CODE" "$OUT/counts/startup-empty" startup

node "$ARTIFACT/summarize.mjs" "$(cygpath -m "$OUT")" > "$OUT/analysis.json"
```

Do not add the failed populated-startup case back to a repeated timing loop without first addressing its recorded limitation.
`WF_ONLY` also accepts a single scenario for a bounded smoke check.
The fixture driver deliberately leaves production timeout defaults intact for startup.
PowerShell created an untracked `Microsoft/Windows/PowerShell/ModuleAnalysisCache` in the isolated code directory during these runs; it was not a code change and is not part of the packet.
If reproducing in another fresh isolated copy, retain ordinary warmups and clean only that newly generated cache after measurement, not an existing user cache.

A future comparison should keep these fixture shapes, command/environment contracts, completion assertions, and serial controls equivalent, and record its actual code SHA and load separately.
Only the next decision ticket selects optimizations; this packet authorizes none.

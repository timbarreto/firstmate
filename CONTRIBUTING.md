# Contributing

Thanks for wanting to contribute.
Contributions use ordinary GitHub pull requests.
[`no-mistakes`](https://github.com/kunchenguid/no-mistakes) remains an optional local validation path, but its signature is not required.

## Workflow

1. Clone this fork or your own fork of it, keeping `origin` pointed at the repository where you intend to push.
2. Create a branch and make your changes.
3. Run the relevant checks from the [Development](#development) section.
4. Commit your changes and push the branch to your fork:

   ```sh
   git push origin <branch>
   ```

5. Open a pull request against `timbarreto/firstmate:main`.
6. Address review findings and required CI checks.

Contributing a generic change to `kunchenguid/firstmate` is a separate upstream submission decision, not a prerequisite for a working fork change.

## Repo conventions

- This repo is a template for running a firstmate orchestrator agent.
  [`AGENTS.md`](AGENTS.md) owns the supervisor contract, role boundary, and bundled firstmate skill triggers; `CLAUDE.md` is a real `@AGENTS.md` pointer to it, and `.claude/skills` is a symlink to `.agents/skills`.
- Only shared material is tracked: `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `.tasks.toml`, `.github/workflows/`, `bin/`, `.agents/skills/`, and `skills/`.
  `.agents/skills/` holds agent-loaded skills that assume a live firstmate home and carry `metadata.internal: true` so installers such as [skills.sh](https://skills.sh) hide them from discovery; `skills/` holds standalone, installer-facing public skills for external agents, and those skills never depend on a live firstmate home or private fleet state (see the README's "Two-tier skill layout").
  Everything personal to one captain's fleet (`.env`, `data/`, `state/`, `config/`, `projects/`, `.no-mistakes/`) is gitignored; never commit it.
  The root `.tasks.toml` is tracked `tasks-axi` config for `data/backlog.md`; compatible `tasks-axi` is the default backend for routine backlog mutations, with the compatibility definition owned by [`docs/configuration.md`](docs/configuration.md) ("Backlog backend").
  A local `config/backlog-backend=manual` opt-out forces firstmate's routine backlog updates to hand-editing and stays gitignored; validated secondmate handoffs still delegate through `tasks-axi mv`.
  A local `config/backend` file explicitly overrides runtime auto-detection for new task endpoints and stays gitignored; spawn-supported values are `tmux`, `herdr` (which has its own required CI lane), and `zellij`, `orca`, and `cmux`, which remain experimental with no dedicated real-backend CI lane, while `codex-app` is documented only in `docs/codex-app-backend.md`.
  It does not make `data/` tracked.
- Shell helpers in `bin/` are plain Bash; semantic policy owners may use tracked `.mjs` modules, and Windows-native installers or bridges may use tracked `.ps1` scripts.
  Each starts with a usage header comment; keep it accurate when you change behavior.
  Test scripts and helpers in `tests/` are plain bash too.
  `bin/fm-lint.sh` must pass: it is the single owner of the lint definition (the shellcheck file set, config, pinned shellcheck version, pinned actionlint workflow lint, and the backend-purity check rejecting direct Beads CLI calls in core `bin/` scripts), and both CI and the optional no-mistakes configuration invoke it with no arguments.
  Its header and `--help` output own the exact local lint modes, file-set selection, and analysis flags.
  A malformed `.github/workflows/*.yml`, including a self-broken `ci.yml`, fails that local lint path before merge because a broken workflow cannot report its own breakage.
  It pins one exact shellcheck version and one exact actionlint version and refuses to run under any other.
  Print the shellcheck pin with `bin/fm-lint.sh --required-version` and the actionlint pin with `bin/fm-lint-workflows.sh --required-version`.
  Use `bin/fm-install-shellcheck.sh` and `bin/fm-install-actionlint.sh` to install those exact builds locally; each installer's header owns its destination usage and supported platforms.
- [Fork architecture](docs/fork/architecture.md) owns the module map, change-placement rules, fixture dependencies, and retained integration patches.
  Spawn-time Claude workspace trust remains in `bin/fm-claude-trust.sh`, delivery-only rendered guards remain in `bin/fm-composer-lib.sh`, and harness facts remain discoverable from `.agents/skills/harness-adapters/SKILL.md`; the `firstmate-coding-guidelines` skill owns the validation policy for harness-dependent checks.
- Changes to runtime session backends (`bin/fm-backend.sh`, `bin/backends/`, and the scripts that dispatch through them) keep current setup and limits in the relevant backend guide and active empirical evidence in [`docs/verification/runtime-backends.md`](docs/verification/runtime-backends.md).
- [`docs/documentation-audiences.md`](docs/documentation-audiences.md) and its machine-consumed inventory own prose classification; run `bin/fm-doc-audience-check.sh` after documentation changes.
- In Markdown, put each full sentence on its own line.
- `README.md` stays a concise overview plus pointers: it never carries a wall of inline detail.
  Route detail to the most specific `docs/` file (architecture, configuration, or a backend guide) and link to it instead.

## Development

Tracked changes to firstmate itself - `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `.tasks.toml`, `.github/workflows/`, `bin/`, `.agents/skills/`, and `skills/` - ship through a feature-branch pull request and require an explicit merge approval.
Before making any such change, load the agent-only `firstmate-coding-guidelines` skill (`.agents/skills/firstmate-coding-guidelines/SKILL.md`).
It has the knowledge-placement rules that keep `AGENTS.md` from regrowing after each diet pass.
There is no reliable way for `bin/fm-brief.sh`'s scaffold to detect that a task's repo is firstmate itself, so firstmate adds this skill's load line to firstmate-repo briefs by hand.
A crewmate picking up such a brief should load the skill even if the brief predates this instruction.
When supervising live crewmates, keep firstmate's own long validation or build commands in the background so watcher wakes can still be handled.
When no-mistakes is used optionally, follow the installed version's SKILL.md and live `axi` help instead of duplicating its mechanics here.
Firstmate's wrapper still matters: crewmates route every `ask-user` finding to firstmate, which applies `ask-user-authority`.
Crewmates never pass `--yes` or `-y` because either flag bypasses that check and any required captain escalation.
[`docs/configuration.md`](docs/configuration.md#gate-defaults-no-mistakesyaml) owns the tracked `.no-mistakes.yaml` gate defaults.
The `firstmate-coding-guidelines` skill owns the rule that local no-mistakes Test stays intent-targeted rather than configuring `commands.test`.
Verify the same way the gate does: reach for `bin/fm-test-run.sh` with the subjects you care about rather than chaining `bash tests/a.test.sh && bash tests/b.test.sh`, because a list of script paths gets the same bounded concurrency as `--changed`.
The pipeline publishes that evidence itself, so never hand-commit `.no-mistakes/` paths onto a feature branch; CI rejects them as tracked personal fleet paths.

Check and test the toolbelt before pushing:

```sh
while IFS= read -r script; do /bin/bash -n "$script" || exit; done < <(bin/fm-lint.sh --list-files)   # syntax-check the shell surface fm-lint.sh will cover (changed files locally, full set in CI/on main)
bin/fm-lint.sh   # lint that shell surface plus GitHub workflows via pinned actionlint; the single owner CI and the no-mistakes gate both run
bin/fm-test-run.sh tests/<subject>.test.sh   # one script (primary local focus path, timed)
bin/fm-test-run.sh tests/<a>.test.sh tests/<b>.test.sh   # several subjects at once: bounded automatic concurrency
bin/fm-test-run.sh --family pure-contract-unit   # ordinary family-scoped local path (serial, timed)
bin/fm-test-run.sh --changed   # normal changed-file-informed path with automatic bounded concurrency
bin/fm-test-run.sh --changed --jobs 1   # explicit serial override
bin/fm-test-run.sh --changed --max-wall-ms 300000   # same automatic path with a post-run five-minute result check
bin/fm-test-run.sh --proven-isolated --jobs 4   # explicit local parallel of the individually proven set
bin/fm-test-run.sh --lane portable-serial   # portable serial remainder (watcher/AFK/tmux/stateful)
bin/fm-test-run.sh --list-lanes   # discover exact lane names, including the current CI serial shards
bin/fm-test-run.sh --check-coverage   # prove portable shards + serial + serial shards + Herdr equal the full inventory
bin/fm-test-run.sh --all   # deliberate complete regression (optional local full walk; not no-mistakes Test)
bin/fm-test-isolation-proof.sh --list   # proven portable parallel candidate set
bin/fm-test-isolation-proof.sh --jobs 4 --json /tmp/fm-isolation-proof.json   # re-run the portable candidate proof
bin/fm-test-isolation-proof.sh --pool watcher-wake-lock --jobs 4   # re-run an admitted family proof
[ ! -L CLAUDE.md ] && cmp -s CLAUDE.md - <<'EOF'
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
EOF
[ "$(readlink .claude/skills)" = "../.agents/skills" ]
tmp=$(mktemp -d) && printf 'done: smoke\n' > "$tmp/smoke.status" && FM_STATE_OVERRIDE="$tmp" FM_SIGNAL_GRACE=1 FM_POLL=1 FM_HEARTBEAT=999999 bin/fm-watch-arm.sh  # watcher re-arm smoke test (prints arm status, then an actionable signal)
```

`bin/fm-test-run.sh` owns behavior-suite execution, portable CI lane composition, bounded scheduling, per-script timing markers, family totals, the coverage guard, and the optional JSON timing artifact.
The [test registration seam](docs/fork/architecture.md#test-registration-seam) separates catalog metadata from runner algorithms and independent proof admission.
Suites registered with `fm_test_run_cases` support the shared named-case and case-listing interface documented in `tests/lib.sh`; use it through the behavior runner when investigating one failure.
The public [`reconcile-firstmate-upstream`](skills/reconcile-firstmate-upstream/SKILL.md) skill owns the bounded, resumable local-check and early-PR workflow for upstream reconciliation, while existing GitHub Actions lanes retain broad coverage and merge-readiness checks.
The runner's header and `--help` own runner flags and lanes; the catalog loader header owns metadata records and ordered changed-path registration.
`bin/fm-test-isolation-proof.sh` remains the single owner of the portable candidate proof and reusable family proof harness; see `docs/fm-test-isolation-proof.md`.
Portable shard balance evidence lives in `docs/fm-test-portable-shards.md`.
Family selection is the ordinary local path; `--all` is deliberate full regression only.
[Fork verification](docs/fork/verification.md#ci-ownership) owns the shared/fork CI coverage map, native and package proof boundaries, and [divergence/locality audit](docs/fork/verification.md#divergence-and-locality-audit).
The upstream repository additionally requires a no-mistakes signature workflow, but this fork intentionally omits that pull-request policy because ordinary pull requests remain supported and no-mistakes is optional here.
Use `bin/fm-test-run.sh --list-lanes` for exact lane names and `--help` for `--jobs` rules and required gate-skip flags when reproducing a lane locally.
Leave the `sleep 0.1` cadence in the suites' bounded condition waits alone.
Those sleeps look like recoverable overhead - `fm-watch-triage.test.sh` alone issues about 1,900 of them, each paying a flat ~100ms scheduler wake-up penalty on macOS - but they are not overhead added to the clock; they are how a test waits for a subject that only moves on `fm-watch.sh`'s own one-second `FM_POLL` cadence.
Sampling less often does not remove that wait, it only delays detection: raising the interval to 0.5s and charging each sample proportionally measured `fm-watch-triage.test.sh` at 435s and 440s against 390s and 393s for the unchanged script, back to back on 2026-09-03, because each of its ~40 poll-cycle waits and ~73 process-exit waits paid up to half a second more.
Some of those loops are also catching a transient rather than waiting for a settled condition, so a coarser sample can step over the state they assert on.
Discover tests by listing `tests/*.test.sh`: each is a self-contained bash script named `<subject>.test.sh`, and its header comment describes what it covers, so pass one to `bin/fm-test-run.sh` to focus on a subject with canonical timing output.
Shared test helpers live in `tests/lib.sh` (reporters, temp roots, git fixtures), `tests/fixtures.sh` (fake toolchain and spawn-world builders), `tests/wake-helpers.sh`, and `tests/secondmate-helpers.sh`.
Source those instead of copying a fake toolchain into a new suite.
A fixture may shorten a production timeout to keep a failure path prompt, but never below what the real work inside that window costs on a loaded machine: a fork, an exec, a lock acquisition, a beacon publication, or a first-poll check.
Where a case's assertion is not about the timeout itself, give that window headroom over the measured loaded cost, and bound the test's own waiting with iteration-counted poll loops, which stretch under load where a wall-clock budget does not.
Tests that need a real optional backend or an explicit opt-in (real herdr/zellij/cmux smoke tests, the live Pi regression) skip themselves and print the tool or environment gate needed to enable them, so the portable suite remains safe on machines without those tools.
The [Herdr backend guide](docs/herdr-backend.md#destructive-lab-safety) owns the lane's isolation boundary, while [runtime backend verification](docs/verification/runtime-backends.md#herdr) owns active empirical evidence; live harness credential tests remain opt-in.

## Questions

Open an issue, or talk to me on [Discord](https://discord.gg/Wsy2NpnZDu).

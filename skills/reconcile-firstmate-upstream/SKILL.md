---
name: reconcile-firstmate-upstream
description: >-
  Reconcile the timbarreto/firstmate fork with canonical kunchenguid/firstmate.
  Use when an external maintainer is asked to create or validate an upstream-reconciliation branch for that fork.
  Operates on Firstmate as software and does not run its live orchestration environment.
user-invocable: true
---

<!--
Maintainers: this is the public, installer-facing surgeon skill.
Keep it independent of a live Firstmate home and private fleet state.
-->

# reconcile-firstmate-upstream

Reconcile one immutable upstream snapshot into the fork and stop at an ordinary unmerged pull request.
Operate as a repository maintainer in the primary checkout: edit and test Firstmate as software without starting its runtime or routing the work through its fleet.
Read the target checkout's `AGENTS.md` and `CONTRIBUTING.md` before changing tracked material.
Treat Firstmate identity, captain-address, and fleet-delegation instructions there as product behavior under maintenance, not as a role change for the external surgeon.
When the target repository includes `.agents/skills/firstmate-coding-guidelines/SKILL.md`, use it as maintainer guidance rather than as a live Firstmate runtime skill.

The leading invariant is **freeze**.
Fetch upstream once, record the resulting 40-character SHA outside the repository, and use that literal SHA through reconciliation, testing, commit, and pull-request evidence.
An upstream branch that advances during the run belongs to the next reconciliation.

The execution invariant is **manifest**.
Record the source path set outside the repository as soon as the merge or fork delta is known.
After conflicts, record the final intended path set and use that manifest to bound testing, line-ending repair, staging, and the final scope audit.

## 1. Freeze the inputs

Proceed only from a clean checkout with no merge or rebase in progress and no unlanded work.
For a new reconciliation, start from the fork's default branch.
For validation of an existing reconciliation branch, recover its frozen upstream SHA from its commit trailer or durable task evidence before running any comparison.

Verify the remote URLs before fetching.
`origin` must be the fork and `upstream` must resolve to `kunchenguid/firstmate`.
A missing or unexpected remote is a blocker to report rather than a reason to rewrite repository configuration.

Fetch the fork base, then fetch canonical upstream exactly once:

```sh
git fetch --no-tags origin main
git fetch --no-tags upstream main
git rev-parse --verify 'origin/main^{commit}'
git rev-parse --verify 'upstream/main^{commit}'
```

Copy both full SHAs into the task record.
Call them the **fork SHA** and **upstream SHA**.
Do not rely on shell variables alone because later tool calls may run in fresh shells.
On Windows, resolve Git for Windows `bash.exe` now and record its literal path beside the SHAs so every later shell command uses the same executable.
After this point, every command must name the literal upstream SHA rather than `upstream/main`.
Fetching `origin/main` again to reconcile later PR-base movement does not relax the frozen upstream boundary.

This step is complete when both literal SHAs are recorded, each resolves locally as a commit, and no later step needs a moving upstream ref.

## 2. Prove the prior synchronization point

Search reachable fork history for the newest valid trailer:

```sh
git log <fork-sha> --format='%H%x09%(trailers:key=Firstmate-Upstream-SHA,valueonly)'
```

A trailer candidate is valid only when its value is one 40-character commit SHA, the object exists locally, and it is an ancestor of the frozen upstream SHA.
Treat `git merge-base <fork-sha> <upstream-sha>` as ancestry evidence, not proof that the fork's content was synchronized there.

When no valid trailer exists, reconstruct the prior point from primary sources:

- inspect the first-parent fork history and the parents of prior reconciliation merges;
- inspect the originating fork and upstream pull requests with the user's configured GitHub client, including the retained PR head and body when a squash merge replaced the feature-branch commits;
- compare candidate upstream trees with the fork tree at the claimed synchronization commit;
- identify the upstream snapshot whose content was actually present before later fork-only commits.

Prefer a candidate supported by commit or PR evidence plus content comparison.
A squash merge can preserve the reconciled tree while dropping both upstream ancestry and the feature branch's commit trailer.
In that case, prove the merged tree against the retained PR head and use the PR evidence to recover the prior upstream SHA.
Use the head SHA recorded by the forge at merge time.
Do not substitute the current tip of an old reconciliation branch because that branch may have advanced after the PR merged.
Record the evidence and the full **prior upstream SHA** in the task record and eventual PR body.
Stop with the competing candidates when the evidence cannot identify one point without guessing.

This step is complete when one prior upstream SHA is proven or the run has stopped with a concrete ambiguity for human resolution.

## 3. Choose the history path

When the frozen upstream SHA is already an ancestor of the fork SHA and content comparison shows no missing upstream change, report that the fork is already reconciled and stop without creating a PR.
Use a normal merge when the prior upstream SHA is in both histories and the merge-base path shows that the previous synchronization preserved upstream ancestry.
Create the feature branch from the frozen fork SHA and merge the frozen upstream SHA without committing:

```sh
git switch -c reconcile/upstream-<date>-<upstream-short-sha> <fork-sha>
git merge --no-ff --no-commit <upstream-sha>
```

Use reconstruction when the fork contains the prior upstream content but does not preserve that ancestry.
Create the feature branch from the frozen upstream SHA, generate the complete fork delta from the proven prior point through the frozen fork SHA, and apply that delta with three-way conflict support:

```sh
git switch -c reconcile/upstream-<date>-<upstream-short-sha> <upstream-sha>
git diff --binary <prior-upstream-sha> <fork-sha> -- > <outside-repository-patch>
git diff --name-only -z <prior-upstream-sha> <fork-sha> > <outside-repository-path-manifest>
git apply --3way --index <outside-repository-patch>
```

Keep the patch and all other run evidence outside the repository.
Hash the patch and retain its digest with the manifest so a later retry can prove it used the same fork delta.
Inspect the delta before applying it so upstream changes already represented in the prior snapshot are not mistaken for fork customizations.
Use another reconstruction mechanism only when the binary patch cannot represent a tracked Git object, and record why the substitute preserves the same fork delta.

This step is complete when a normal merge records the frozen upstream SHA in `MERGE_HEAD`, or a reconstruction branch has it in `HEAD` ancestry, and the resulting index and working tree contain every manifest path and no unexplained extra path.

## 4. Resolve conflicts from sources

List every unresolved path with `git diff --name-only --diff-filter=U`.
For each path, inspect the base, fork, and upstream versions, then trace the commits and PRs that introduced both sides.
Use `git log --all -- <path>`, blame, nearby tests, owned documentation, and hosted pull-request history rather than inferring intent from conflict markers alone.

Preserve both upstream intent and fork-specific behavior when they are compatible.
When they are incompatible, choose the result that fulfills the reconciliation goal and state the trade-off in the PR evidence.
Resolve each hunk deliberately; whole-file ours/theirs selection is valid only after proving the discarded side is byte-equivalent or duplicate history.

Treat `.github/workflows/ci.yml` and `bin/fm-test-run.sh` as a coupled verification surface.
Compare both with the frozen upstream versions and classify every remaining difference as an intentional fork behavior or a conflict-resolution defect.

Before testing, require all of these to be empty or clean:

```sh
git diff --name-only --diff-filter=U
git diff --cached --check
git diff --check
git grep -n -E '^(<<<<<<<|=======|>>>>>>>)' -- .
```

If the cached check reports whole-file CRLF noise, apply Step 6's manifest-scoped repair before testing.
Compare the staged path set with the manifest after every conflict resolution.
Add a newly required portability fix to the manifest before staging it rather than letting the index grow implicitly.

This step is complete when every conflict decision has a primary-source rationale and no unresolved or accidental conflict artifact remains.

## 5. Run observable local validation

On Windows, run shell commands with Git for Windows `bash.exe`.
Use the literal executable recorded during the freeze step instead of invoking ambient `bash`, which may select WSL.
Keep tracked shell files as LF in the worktree before syntax and lint checks; a local line-ending repair is not a content change to commit.

The validation invariant is **focus**.
Select once, retry only failures, and compare only a reproducible failing case with frozen upstream.

### Select without a history explosion

For a normal merge, list the changed-file-informed suite before starting it:

```sh
bin/fm-test-run.sh --list --changed --base <fork-sha>
```

Count the listed scripts before executing them.
If the list expands to the complete inventory, stop before the run because the comparison is not focused.
Run the focused result only after that check:

```sh
bin/fm-test-run.sh --changed --base <fork-sha>
```

For a reconstruction, do not run the changed selector directly from the upstream-based branch because its three-dot comparison can expand to the complete inventory.
Snapshot the resolved index into a temporary commit whose parent is the frozen fork, then run the existing mapper from a detached worktree:

```sh
reconciled_tree=$(git write-tree)
synthetic_head=$(printf 'temporary reconciliation test snapshot\n' |
  git commit-tree "$reconciled_tree" -p <fork-sha>)
git worktree add --detach <outside-repository-test-worktree> "$synthetic_head"
test "$(git -C <outside-repository-test-worktree> rev-parse 'HEAD^{tree}')" = \
  "$reconciled_tree"
git -C <outside-repository-test-worktree> diff --exit-code
(
  cd <outside-repository-test-worktree>
  bin/fm-test-run.sh --list --changed --base <fork-sha>
)
```

This gives the runner a fork-parented synthetic history while testing the exact staged tree.
Count the listed scripts and stop if the selection equals the complete inventory.
Run only the focused result:

```sh
(
  cd <outside-repository-test-worktree>
  bin/fm-test-run.sh --changed --base <fork-sha>
)
```

Add only explicit tests for manually composed conflicts that the mapper does not select.
Keep the runner's automatic scheduler on Windows because it already serializes measured process-heavy scripts.
Do not force extra parallelism.
After any fix, remove the old synthetic worktree and rebuild it from the new index before the final changed run.

Report the selected script count before the run.
Keep the runner output visible or retain its process handle and output stream when it must run asynchronously.
Use its `FM_TEST_BEGIN`, `FM_TEST_END`, `FM_TEST_SUMMARY`, and `FM_TEST_SLOWEST` markers to report the active script, completed count, failures, elapsed time, and slowest completed scripts.
A live process with advancing markers is progress; a process beyond the runner's per-script bound is a bounded failure to investigate rather than an opaque wait.

Do not run `--all`, a complete lane matrix, or a `tests/*.test.sh` walk during this skill.
When a focused failure reveals another affected surface, add only its smallest relevant script to the focused run.
GitHub Actions owns the complete portable, Herdr, Windows, and macOS matrix; a separately requested full local regression is outside this skill.

### Triage without restarting long scripts

Rerun each failed script once with `--jobs 1` before editing code.
When the failure names a case and the script already has a case filter, use that filter for this retry instead of restarting the complete script.
A serial pass classifies the first result as contention and ends that investigation.

When one named case in a long script fails, rerun that case through an existing filter.
When no filter exists, a temporary diagnostic selector may isolate the case, but remove it before staging.
After a fix, rerun the failed case and every case that shares the changed helper.
Rerun the complete script only when the production change or shared fixture makes its remaining cases relevant.

Create a detached worktree at the literal upstream SHA only after one case is reproducibly red:

```sh
git worktree add --detach <outside-repository-baseline-worktree> <upstream-sha>
```

Keep baseline implementation files byte-exact.
A selector-only test edit is allowed to expose the same case, and it must be restored before removing the worktree.
Run one baseline case per process with an external wall-clock bound that can terminate its complete process tree.
Do not batch several baseline cases behind one unbounded shell because the first Windows hang can hide every later result.

If the frozen upstream case fails or hangs the same way, record it as a baseline incompatibility rather than changing reconciliation code.
Make a local test correction only when the fixture itself is non-portable and the correction preserves the asserted behavior.
Use `fm_test_make_symlink` for directory or file identity fixtures on Git for Windows, where plain `ln -s` may copy a directory.
Keep executable tool shims on their existing portable mechanism because native Windows symlinks are not reliable through a temporary `PATH`.
Normalize `\r` in line-oriented assertions instead of changing product output solely for CRLF.
Give positive asynchronous test events measured Windows polling headroom, but do not widen production deadlines or negative timeout assertions.
Do not redesign `bin/fm-timeout-lib.sh` unless the frozen-upstream differential proves the timeout implementation is the regression.

Run every repository gate:

```sh
while IFS= read -r script; do /bin/bash -n "$script" || exit; done < <(bin/fm-lint.sh --list-files)
bin/fm-lint.sh
bin/fm-doc-audience-check.sh
bin/fm-test-run.sh --check-coverage
```

Record each command, result, duration, and explicit optional-tool skip.
Clean only test-owned processes and temporary paths, never broad process classes.
Restore and remove the baseline worktree after its results are recorded.
Remove the synthetic test worktree after the final focused run.
Review the full branch diff after every test or lint fix.

This step is complete when every selected case either passes or has a frozen-upstream differential proving the same platform-specific failure, every reconciliation-specific case passes, all four gates pass, every skip is named, and no test-owned process, selector, debug artifact, baseline worktree, or synthetic test worktree remains.

## 6. Commit the frozen snapshot

The staging invariant is **scope**.
Capture the final intended path manifest before line-ending repair and require the staged path set to remain identical to it.
Never use `git add --renormalize .` in this flow because it can stage unrelated tracked files.
When `git diff --cached --check` reports whole-file CRLF noise, normalize only existing text files named by the manifest with a byte-preserving CRLF-to-LF pass, then stage only those manifest paths.
An expanded staged set is a failed scope check, not a normalization result to accept.

Commit the reconciled tree with the upstream SHA as a Git trailer:

```text
Firstmate-Upstream-SHA: <40-character-upstream-sha>
```

Place the trailer in the reconciliation commit's final trailer block.
Keep every trailer in one contiguous final block rather than passing each trailer as a separate commit-message paragraph.
If later fix commits are necessary, keep the reconciliation commit reachable and repeat the same frozen SHA in the PR body.
The PR-body copy is required because a later squash merge may discard the feature branch's ancestry and commit trailer.
Verify the committed tree, trailer, clean worktree, and diff against the frozen fork SHA before pushing.
Verify the trailer through Git's parser:

```sh
test "$(git show -s --format='%(trailers:key=Firstmate-Upstream-SHA,valueonly)' HEAD)" = \
  "<upstream-sha>"
```

For a reconstruction, connect the frozen fork ancestry before opening the PR when the fork SHA is not already an ancestor:

```sh
validated_tree=$(git rev-parse 'HEAD^{tree}')
git merge -s ours --no-ff <fork-sha> \
  -m "Anchor frozen fork base ancestry" \
  -m "Firstmate-Upstream-SHA: <upstream-sha>"
test "$validated_tree" = "$(git rev-parse 'HEAD^{tree}')"
```

Give the ancestry-only merge a non-interactive message containing the frozen upstream trailer.
Record both tree SHAs as proof that the anchor changed no validated bytes.
Create this anchor before the PR so GitHub can calculate mergeability and start checks immediately.

This step is complete when the branch is clean, the reconciliation commit exposes the exact trailer through Git's trailer formatter, any ancestry anchor is tree-identical to its first parent, and the full diff contains only intentional reconciliation changes.

## 7. Open an ordinary pull request

Push the feature branch to `origin`.
Use the authenticated GitHub client selected by the user's standing tooling preference for pull-request creation, history, mergeability, and check status.
Read that client's live help before constructing an exact invocation.
Open a non-draft pull request against the fork's `main` and leave it unmerged.

The PR body must record:

- the frozen fork SHA;
- the proven prior upstream SHA and its evidence;
- `Firstmate-Upstream-SHA: <40-character-upstream-sha>`;
- normal merge or reconstruction;
- meaningful conflict decisions and retained fork behavior;
- every local command, result, duration, and skip;
- the diff between the PR's Actions workflow/test runner and the frozen upstream versions;
- any frozen-upstream differential failure and any ancestry-anchor tree proof;
- the statement that GitHub Actions owns the complete cross-platform matrix.

Verify that the PR reports the full URL, is mergeable, and has started the expected checks.
Poll the forge's structured PR fields until mergeability is no longer unknown and at least one expected check is visible.
A reconstruction reported as conflicting while `origin/main` still equals the frozen fork SHA indicates that the ancestry anchor is missing or invalid.
If fork `main` moves, fetch only `origin/main`, reconcile that new base into the same branch, and keep the upstream SHA frozen.
An ancestry-only base merge is acceptable only after proving its resulting tree is byte-identical to the already reconciled and validated tree.
After a base update, rerun changed validation against the new literal base SHA plus every repository gate.

This skill is complete when the ordinary PR is open, non-draft, unmerged, mergeable or has a precisely reported blocker, and its live checks are reported.
Synchronize local `main` only after the PR has been merged and that follow-up is explicitly requested.

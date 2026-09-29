---
name: dsh-pre-push-checks
description: Use before pushing, force-pushing, marking ready for review, or claiming checks pass on a branch, and immediately after gh stack sync publishes rewritten branches, to select the smallest tests and checks that cover the outgoing or just-published diff without reflexively running the full repository suite.
---

# DSH Pre-Push Checks

Use this skill to run relevant local evidence once before a push. The sole ordering exception is `gh stack sync`, which may publish a cascading rebase before the rewritten layers can be validated; validate them immediately afterward and do not merge until the evidence passes. Commit-time checks and the minimal pre-push command set are defined in the repository's `AGENTS.md`; CI owns exhaustive coverage and the platform matrix.

## Inspect the outgoing change

1. Confirm the checkout and branch.

```sh
git status --short --branch
git rev-parse --show-toplevel
```

2. Verify the live PR base or stack parent, fetch that ref, and inspect the complete scope against it.

```sh
git diff --stat <verified-base-ref>..HEAD
git diff --name-status <verified-base-ref>..HEAD
```

The commands never guess or fetch a base. Supply the ref verified from current remote or stack state; use `--head <ref>` when inspecting a commit other than `HEAD`. After merging a changed base, rerun the diff, reassess which behavior the combined scope can affect, and rerun only checks invalidated by the merge.

## Select relevant evidence

There is no universal local baseline beyond the repository rules. Every behavior change needs the narrowest available test or purpose-built check that would fail for its regression; add broader checks only for surfaces the diff actually reaches.

- **Crate or script behavior:** run the owning crate's tests (`cargo test -p <crate>`) or a focused test name. Add adjacent crate tests when a shared contract changes; leave repository-wide coverage to CI unless the change is genuinely cross-cutting or the user requests it.
- **Documentation, Agent Notes, catalogs, or doc-linked comments:** run `.\scripts\verify-agent-notes.ps1` and `.\scripts\verify-translation-pairs.ps1` when those trees are touched; run full lint when the documentation workflow requires it.
- **Model-, editor-, CLI-, or terminal-visible output:** run the focused keyless snapshot or real runnable-example scenario that owns the output, such as `cargo run -p zhu-ye-cli -- demo <pinyin>` or `self-check`.
- **Cargo manifests, public APIs, build configuration, binary entries, or built runtime paths:** run `cargo check --workspace` (or `cargo build --workspace` when the built artifact itself matters), the relevant hygiene checks, and the owning built-artifact smoke.
- **Real provider or agent behavior:** run the relevant smoke or integration scenario when credentials are available; never print secrets.

Do not manually repeat a passing check merely because commit or push follows. In particular, do not run the full Cargo suite immediately before pushing solely to duplicate a check that already passed for the same diff.

### Focus unit coverage on the affected source

Test selection and coverage selection are separate. A Cargo test filter chooses which tests run; when unit coverage is relevant, name both the owning tests and the source files or crate whose coverage those tests must prove:

```sh
cargo test -p <crate> <focused-test-name>
```

Keep the selected scope tight: add adjacent crate tests only when the shared contract changes. When the owning tests are unclear, use `rg` to trace callers and symbols, then inspect the selected tests before treating the run as evidence. Do not use `--passWithNoTests` or narrow the test selection merely to hide an uncovered affected file. If a focused test does not cover an affected source, add the relevant owning tests or narrow the changed scope only when the excluded modules cannot be affected by the change.

Tests cannot always discover behavior reached only through configuration, dynamic loading, subprocesses, external providers, or the TSF process boundary; select those owning tests or smoke scenarios explicitly.

## Full local rehearsal

Run the complete local approximation only when the user explicitly requests it, while diagnosing a CI failure, or when the change spans the repository so broadly that no narrower set is credible. Use the current workflow and `AGENTS.md` commands as the inventory; do not recreate a removed aggregate check.

## Protect history-rewriting pushes

Rebase is allowed for standalone and stacked PR branches, including after review. Before a standalone history rewrite, fetch the current remote branch and record its exact OID; publish with `--force-with-lease=<branch>:<observed-oid>` so a concurrent update aborts the push. `gh stack push` and `gh stack sync` supply lease protection for their managed branches. Raw `--force` is never allowed.

After any rewritten push, fetch the live heads again and re-audit unresolved review threads, approvals, mergeability, and checks. Commit hashes and inline-comment anchors from before the rewrite are not current evidence.

### Post-sync validation

`gh stack sync` fetches, cascade-rebases, and pushes as one operation, so it cannot place local validation between rewrite and publication. Before running it, require a clean worktree and record the official stack order and exact remote heads. After it returns:

1. Re-query every branch head and the official GitHub stack order.
2. Inspect the changed scope of every rewritten layer against its live PR base.
3. Run the relevant evidence selected by this skill for each affected layer.
4. Keep every PR unmerged and report validation as pending until all selected checks pass.

If post-sync evidence fails, leave the lease-protected published heads in place, repair the failure, validate the repair, and publish the correction. Do not claim the sync made the stack ready merely because the command succeeded.

## Handle failures

If a relevant check fails before an ordinary push, stop and fix or explain the blocker. Do not push and hope CI differs. For the post-sync exception, block the merge and follow the repair procedure above.

If a failure looks environment-specific, prove it:

- Record the exact command, failing test, and platform-specific mismatch.
- Confirm the relevant non-platform evidence.
- Prefer fixing cross-platform nondeterminism when the check is required.
- Bypass a local gate only when the user explicitly asks or agrees, and report exactly what failed and why CI is expected to differ.

## Push procedure

For ordinary and standalone rebase pushes:

1. Run the selected relevant checks once.
2. Commit normally and inspect any files changed by commit-time checks before continuing.
3. Push normally, or use the exact lease for an authorized rewritten branch.
4. Verify the remote ref matches local `HEAD`.

```sh
git rev-parse HEAD origin/$(git branch --show-current)
```

For GitHub PRs, inspect remote CI after the push:

```sh
gh pr checks
```

Report pending checks as pending. Inspect failures before attributing them to the branch or the environment.

For `gh stack sync`, use the post-sync validation sequence instead of pretending the ordinary order was possible.

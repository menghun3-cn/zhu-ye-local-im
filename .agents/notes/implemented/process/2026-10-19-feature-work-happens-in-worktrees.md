# Agent Note: Feature work happens in worktrees

Status: implemented

English | [中文](2026-10-19-feature-work-happens-in-worktrees.zh.md)

## Problem

The main checkout is shared by too many things. A feature branch, a release
process and an unrelated in-progress feature all land in the same working tree,
and a `git status` that lists half a dozen unrelated changes makes it impossible
to tell which PR a file belongs to. An interrupted or abandoned task leaks its
half-finished files into the next feature's commit, and the gates (`dart test`,
`flutter analyze`) run against a tree that is not the tree being published.

## Decision

**Every feature or fix gets its own git worktree.** The workflow is now:

```powershell
git worktree add -b <type>/<description> F:\asc_workspace\code\aicode\zhu-ye-local-im-<name> origin/develop
```

The main checkout (`zhu-ye-local-im`) is reserved for repository operations and
releases; code for a branch lives in its own worktree, is tested there, and is
PR'd from there. `AGENTS.md` §2.1 carries the rule so every future agent and
contributor starts from the same place. Parallel tasks cannot pollute each
other's `git status`, and a half-finished feature can be left alone in its own
checkout instead of forcing the next feature to carry it.

## Alternatives considered

**Keep one checkout and rely on `git stash`.** Rejected: stashes are easy to
forget and easy to pop onto the wrong branch, and they do not help two tasks
that both need `test_flutter` running at once.

**A separate clone per feature.** Rejected: a clone duplicates the whole
repository history and needs its own remote setup; a worktree reuses the same
.git and the same remotes.

## Consequences

- `AGENTS.md` §2.1 documents the worktree rule.
- Releases and unrelated experiments in the main checkout no longer leak into
  a feature's diff.
- The convention costs one directory per active feature and a `git worktree
  prune` now and then, which is cheaper than untangling a mixed `git status`.

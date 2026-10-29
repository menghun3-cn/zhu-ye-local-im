# Agent Note: Deleting files needs an absolute path

Status: implemented

English | [中文](2026-10-28-deleting-files-needs-an-absolute-path.zh.md)

## Problem

On 2026-10-28 the repository's main checkout was deleted from under itself.
The chain was a cleanup of a stray file named `$null`: a PowerShell `cmd /c rd`
call expanded `$null` to an empty token, and the `rd /s /q` that reached
`cmd.exe` targeted the repository root instead of the file. The working tree
and its `.git` were gone; the checkout had to be rebuilt from the remote.

The failure was not the intent to clean up, nor the file itself — it was that a
destructive command crossed a shell boundary without ever validating the path
it would act on, and that a refused or failed delete was retried instead of
reported.

## Decision

The `AGENTS.md` §7.1 safety rules are binding for every shell command in this
repository, including AI assistants:

- **No destructive commands across shells.** A PowerShell process must not run
  `cmd /c rd` (or any `cmd` / bash file mutation) against a path that earlier
  steps computed or enumerated. Deletion and moves happen entirely in one
  shell with its own native tokens.
- **Cleanup is never the goal.** A stray file is ignored, not actively removed,
  unless the user asked for the removal. Leaving one missed file in place is
  cheaper than touching the repository with a destructive command at all.
- **Resolve and verify before deleting or moving.** Before any delete/move the
  target's absolute path is resolved and must equal the intended literal path;
  it must not equal the repository root or anything under it that is meant to
  stay. Commands must not end in an unexpanded variable or a wildcard.
- **`$null` is not a file name.** In PowerShell `$null` is the null value.
  Putting it inside a `cmd /c "..."` string expands it to nothing, which moves
  the delete to the repository root. Suppress output with `2>$null`
  (PowerShell) or `2>/dev/null` (bash), and keep the two shells apart.
- **A failed delete/move is a stop signal.** Retrying, or switching tools after
  an `Access is denied` / in-use error, is prohibited until a human confirms.
  The right first response is a report of what is intact and what the next
  step would be.
- **Repository content is moved, not deleted.** Relocating a checkout goes
  through an intermediate safe path first; the old location is only re-purposed
  after the new location is verified.

## Alternatives considered

**A dedicated "delete this" skill with a confirmation prompt.** Rejected for
now: the rule set above already makes the dangerous shape of command
impossible, and an extra component would only create a second place to skip.

**Permitting cross-shell deletes when the user asked to clean up.** Rejected:
the 2026-10-28 incident started exactly this way — a "cleanup" that nobody had
asked for. Cleanup intent is precisely when destructive commands must be least
clever, not more so.

## Consequences

- Every agent and contributor now has a binding safety section in `AGENTS.md`
  (§7.1) that outranks convenience.
- Recovery from a deleted checkout is documented: the remote
  (`https://github.com/menghun3-cn/zhu-ye-local-im.git`) rebuilds the tree and
  refs (`master` / `develop` / tags), and `git fsck` and `rev-parse` verify
  completeness before use.
- The cost is a few seconds of verification (resolve a path, check its item
  count, confirm) in exchange for not losing the repository again.

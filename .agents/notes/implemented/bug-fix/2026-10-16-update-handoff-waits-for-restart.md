# Agent Note: The update hand-off waits for the restarted build

Status: implemented

English | [中文](2026-10-16-update-handoff-waits-for-restart.zh.md)

## Problem

The last step of the portable build replacing itself was a race: in
`lib/ui/update_handoff.dart`, `_finish()` ran the new files into place on an
isolate, called `startDetached(executable)`, and then immediately called
`exit(0)`. The original `startDetached` was a fire-and-forget call to
`Process.start(...)` that was never awaited.

`Process.start` returns a `Future`; the actual creation of the child process
happens on a later event-loop turn. `exit(0)` terminates the isolate and with it
any future that has not completed yet. That left a window where the update
files were already in place but the new window never came up — the "关闭并更新"
path closed the program and did not bring it back.

The installer path is unaffected: Inno's `[Run]` entry starts the executable
after a silent `/update` install. This bug is specific to the portable build's
self-replacement hand-over.

## Decision

Make `startDetached` return `Future<void>` and await the `Process.start` call
inside it; in `_finish()`, await `startDetached(executable)` before `exit(0)`.

The point of the await is not style but ordering: the old process may only go
away once the operating system has accepted the new process. In detached mode
the child survives the parent's exit, so once the future completes the restart
has actually started. If the start fails, the exception now surfaces in
`_finish()`'s failure branch and the hand-over window reports it instead of
disappearing silently.

## Consequences

- The portable build restart is no longer aspirational; the old process waits
  for the new process to be created.
- A failure to start the new process is reported on the hand-over window rather
  than leaving the user looking at an empty folder.
- A test guards the contract: calling `startDetached` with a missing executable
  throws a `ProcessException` to the caller, which a fire-and-forget
  implementation would have swallowed.

## Alternatives considered

**Keep fire-and-forget** — it is the source of the reported "updated but never
reopened" situation and cannot be kept.

**Use `Process.run`** — it is not a detached start, and waiting for the output
is not what the hand-over needs; the child must outlive the parent.

**Sleep for a fixed delay before exiting** — a delay is not evidence that the
process started, and it taxes every normal machine; awaiting the start result
is the only check that actually means something.

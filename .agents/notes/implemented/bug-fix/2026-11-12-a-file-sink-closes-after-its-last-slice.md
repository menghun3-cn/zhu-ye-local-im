# Agent Note: a file sink closes only after its last slice lands

Status: implemented

## Problem

`FilePayloadSink.close` could run while a slice's `writeFrom` was still in
flight, and Windows answered with `FileSystemException: An async operation
is currently pending`. The widget suite caught it as an unhandled async
error that failed whichever test happened to be running — a received file
whose Transfer was failed mid-write by a closing Session surfaced the
error through `_publishLandings`/`_abandonLandings`, whose `await
sink.close()` had no guard of its own.

The race is structural, not a missed `await`. `TransferEngine` funnels
chunk frames and control messages through one serial queue, so `onChunk`'s
`await sink.write` always finishes before `onComplete` settles the
Transfer — *for the orderly endings*. But `engine.close()`, a dead
Session, and `onChannelError` all reach `finish` directly, without draining
the queue: a task already inside `writeFrom` keeps running while
`onSettled` fires `_closeSinks` and the app-side landing code awaits the
same close. Two callers, one handle, no ordering between them and the
write that was still on the wire.

## Decision

**Every handle operation goes through one tail.** `FilePayloadSink` keeps
`_tail`, a `Future<void>` that each `setPosition`+`writeFrom` pair and the
final `close` chain onto. A close can therefore only ever queue *behind*
the writes submitted before it — which is exactly the set that can still
be in flight, because `onChunk` checks `isSettled` before writing and no
write is submitted after the Transfer settles. The tail swallows its own
errors (`run.then((_) {}, onError: ...)`) so one failed slice cannot poison
the operations queued after it; the error still reaches the write's own
awaiter, which is the `onChunk` that reports it as `ioError`.

Nothing else changed: `PayloadSink`'s contract, the settle-then-close
order in `IncomingTransfer`, and the shared `_closing` future that lets
the landing code and `_closeSinks` await the same release all stay as they
were. The fix is inside the sink because the sink is the only place that
knows a handle operation is outstanding.

## Alternatives considered

**Drain the engine's queue before failing Transfers on close.** Rejected:
`close` exists precisely because the Session is gone or going; making
shutdown wait on in-flight disk writes would couple engine teardown to
filesystem latency, and a hung write would hang the close. The sink-level
tail bounds the wait to the operations already submitted, which is the
same bound either way but without touching the engine's contract.

**Guard each `await sink.close()` call site.** Rejected: there are three
(`_closeSinks`, `_publishLandings`, `_abandonLandings`) and the next caller
would have to remember the same guard. The invariant — a handle is never
closed under a pending operation — belongs to the object that owns the
handle.

**Reject writes once `_closed` is set.** Rejected as insufficient: it
fixes writes submitted *after* close, but the failing case is a write
submitted *before* it. Ordering, not refusal, is the missing piece.

## Consequences

**Bought.** A Transfer failed mid-write — Session drop, engine close,
peer cancel racing the last chunk — now closes its file cleanly instead of
surfacing a pending-operation `FileSystemException` as an unhandled async
error. Received files still land or get discarded exactly as before; only
the close waits, and only for writes already submitted.

**Cost.** File operations on one sink are now explicitly serialized
rather than implicitly ordered by the message queue. That is the same
order they already ran in, made guaranteed for the one caller — `close` —
that never went through the queue.

**Testing.** `test_flutter/ui/pages_test.dart`'s file-search case was the
reproducer: it failed consistently on this machine before the change and
passes after. `test/transfer/` keeps passing, including the session-death
cases that exercise the non-queued settle paths.

# Agent Note: A received picture was drawn from a file that did not exist yet

Status: implemented

English | [中文](2026-10-10-a-received-picture-was-drawn-before-its-bytes-landed.zh.md)

## Problem

A picture received from a peer sat in the conversation as a grey box with a
broken-image glyph and the file name (`pasted-1791595231659873.bmp`) — and it
stayed that way. The file itself was fine: 348,214 bytes in
`Downloads\LocalTransfer`, a textbook 32-bpp `BI_RGB` bitmap (340×256, header
verified byte by byte) that the same Flutter build decodes without complaint
when it is the *sender's* copy. The decoder was never the problem; the decoder
was never given a whole file.

The trail ends in `LocalTransferController.acceptInto`
(`lib/app/app_controller.dart`):

```dart
await transfer.accept(itemIds: ..., sinks: sinks);
accepted = true;
...
// The bytes are verified and closed by now — `accept` does not return until
// they are — so it is only here that a received image has a path worth
// drawing.
if (landed.isNotEmpty) {
  _recordLocalPath(transfer, landed.values.first);
}
_notify();
```

The comment is wrong about the one fact it exists to state.
`IncomingTransfer.accept` (`lib/core/transfer/incoming_transfer.dart`) sends the
`AcceptMessage` and returns — *"Throws ... if the Offer has already been
answered"* is the only settlement it touches. The bytes cross afterwards, chunk
by chunk, and are verified in `onComplete`, which runs on a later turn of the
event loop entirely. So `_recordLocalPath` fired at the moment the file was
**empty**: the conversation rebuilt, saw `kind == image && localPath != null`,
switched to `_bareImage`, and `ImageBubble` resolved a `FileImage` over a
zero-byte file. The decode failed, `_unreadable` was set, and `ImageBubble` has
no re-trigger — `_follow` re-resolves only when the *path changes*, and the path
never changes. The broken-image box was therefore permanent, across progress
ticks, completion, and every rebuild after.

What makes this sly is that the codebase *documented* the correct rule twice
and still got the code wrong. `_Tracked.localPath`: *"a path still being
written to would draw half a picture or fail outright"*. `TransferView
.localPath`: *"a received image is given a path only once its bytes are all
present"*. The existing test — `a received picture keeps a path worth drawing`
— checks `localPath` is null *before* `acceptInto` and not null *after the
transfer settles*, which the buggy code satisfies trivially, because it records
the path too **early** rather than not at all. Nothing asserted the in-between.

## Decision

`acceptInto` records the path when the transfer's outcome says the bytes are
real, not when the answer goes out:

```dart
if (landed.isNotEmpty) {
  final path = landed.values.first;
  unawaited(transfer.outcome.then((outcome) {
    if (outcome is TransferCompleted && _recordLocalPath(transfer, path)) {
      _notify();
    }
  }));
}
```

`Transfer.outcome` is the future the transfer's own verification already
completes — `finish(TransferCompleted(...))` runs only after every accepted
item's byte count matched and its digest verified. Hanging the recording off it
means the path appears exactly when `_Tracked`'s doc says it should, and never
appears for a transfer that fails, which is the honest answer about a file that
never arrived. `_recordLocalPath` now answers whether it found the record, so
the notify fires only when something actually changed, and the extra `_notify()`
covers the race where the outcome's own progress notification rebuilds the UI a
beat before the callback lands.

Nothing else moves. The sender's side already records its path at `_track`
time, and rightly — the file it names is the user's own and was whole before
the transfer existed. `ImageBubble` keeps its no-retry stance, because with the
path arriving only after verification there is nothing left to retry.

The test gained the assertion that was missing — the one that fails on the old
code:

```dart
await bob.controller.acceptInto(offer, incoming);
expect(
  bob.controller.transfers.single.localPath,
  isNull,
  reason: 'the answer is on the wire but the bytes are not here yet, ...',
);
```

## Alternatives considered

**Fix `accept` to await settlement.** Rejected: it would change the meaning of
a method whose other callers — and whose name — say it sends an answer, and it
would hold `acceptInto`'s future for the whole transfer. The engine's
offer/accept/complete split is deliberate; the app layer was reading it wrong,
not the engine being wrong.

**Promote the path inside `_track`'s progress subscription.** Considered: a
`landedPath` field on `_Tracked`, promoted to `localPath` when the state turns
settled. Rejected: it threads a pending value through a record that exists to
be a dumb pair, and it needs the same outcome test somewhere anyway. Waiting on
`outcome` keeps the whole rule visible at the one place the path is born.

**Make `ImageBubble` retry failed decodes.** Rejected: it treats the symptom —
the retry would paper over any future caller that hands the bubble a file that
is not there, and each retry is a re-read of a file that should not have been
pointed at yet. The bubble's contract ("no re-trigger, the path is only
recorded when it is drawable") is reasonable; the bug was the recording.

**Record the path on every settle, including failures.** Rejected: a failed
transfer's partial file is deliberately kept for resume, but it is not a
picture — drawing it would show a truncated decode, and "show me where this
went" would point at debris.

## Consequences

- A received picture now shows its bubble with a name and progress bar while
  the bytes cross — the documented "transfer's business" look — and flips to
  the bare thumbnail the moment verification completes, with the decode
  guaranteed a whole file.
- A received *file* gains the same correctness for free: its "open containing
  folder" entry appears only when the file is actually on the disk.
- The grey broken-image box is now reachable only by a file that was deleted
  or is genuinely undecodable, which is what its own doc says it is for.
- `dart test` 444/444 with the new in-between assertion in place.

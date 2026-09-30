# Agent Note: Make a staged clipboard entry reach the screen

Status: implemented

English | [中文](2026-09-30-staged-clipboard-entry-never-reaches-the-screen.zh.md)

## Problem

When clipboard sync is set to *Ask me*, an entry arriving from a peer is not
applied. It is **staged**: it waits for the user to accept or discard it, and the
Clipboard surface renders the waiting list.

`ClipboardMirror` reports a staged entry on its own `staged` stream rather than
through the `onNotice` callback the controller already passes in. That split is
deliberate and right — a staged item is a thing to answer, not the Device's
running commentary — but nothing in `LocalTransferController` listened to the
stream. Every other channel the mirror offers ended up at `_notify()`: notices
through `_notice`, applies through the calls around them, and `changes` is the
stream the UI rebuilds on.

So a staged entry arrived with nobody told. The surface kept rendering the list it
had built the last time something unrelated fired a change — a Transfer
progressing, a peer appearing, the clipboard mode being toggled — or it corrected
itself once the user navigated away and back. The feature worked and looked
broken: "Ask me" is precisely the mode where the user is meant to be asked while
they are looking at the screen.

No test caught it because the tests drove the controller directly and read
`stagedEntries`, whose value was always correct. What was missing was the
notification, and nothing asserted that anything would be told.

## Decision

The controller subscribes to the mirror's `staged` stream and notifies on it, as
it does for every other change it watches:

```dart
_watch.add(clipboard.staged.listen((_) => _notify()));
```

The subscription is added to `_watch`, so `close()` cancels it with the rest.

## Alternatives considered

**Route the staged entry through `onNotice` instead.** Rejected: the Clipboard
surface renders notices as the Device's commentary and the staged list as items
awaiting an answer. Merging them would make a waiting item look like a fault, or
force the UI to sort one kind of notice out of the other's list.

**Have the Clipboard page poll `stagedEntries` on a timer.** Rejected: a permanent
poll that exists only because one stream was left unwired, and it makes the
surface's freshness a second thing to reason about next to the controller's own
notification.

**Rebuild on every controller change no matter what changed.** Rejected: the
controller already notifies for everything else it watches. This was one missing
subscription, not a missing policy, and replacing the policy would hide the next
one.

## Consequences

- A staged entry appears on the Clipboard surface as it arrives, which is the
  whole of what *Ask me* promises.
- `test/app/app_controller_test.dart` pins the defect where it lived: it listens
  to the controller's `changes` stream and asserts it fires when an entry is
  staged. Removing the subscription makes that test fail.
- `test_flutter/ui/pages_test.dart` covers the same behaviour through the widget
  tree, so the surface is checked as well as the stream.
- The lesson is recorded rather than the fix alone: a stream a caller can *read*
  is not the same as a stream a screen will be *told* about, and the controller
  is the only place that difference is decided.

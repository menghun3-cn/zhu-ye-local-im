# Agent Note: A conversation left open on screen rewrote its file every frame

Status: implemented

English | [中文](2026-10-14-conversation-save-sharing-violation.zh.md)

## Problem

Opening the Settings surface used to fill the Notices list with one line, over
and over, for as long as the app ran:

```
the conversation could not be saved: PathAccessException:
  Cannot rename file to .../LocalTransfer/messages.json,
  path '.../LocalTransfer/messages.json.tmp'
  (OS Error: 另一个程序正在使用此文件, errno = 32)
```

`errno = 32` is `ERROR_SHARING_VIOLATION`. Nothing outside the program held
`messages.json`; the program held it itself, one save at a time.

Two defects met to produce it.

**The loop.** `ConversationsPage.build` schedules a post-frame callback that
calls `markConversationOpened` whenever the remembered conversation is on
screen. That method mutated the reading state, called `_notify()` and awaited a
save — and `_notify()` is what rebuilds the page that schedules the next
callback. The guard meant to break the cycle did not:

```dart
final advanced = before == null || now.isAfter(before);
if (!advanced && !movedLast) return;
```

`now` is read from the clock on every call and `before` is the previous mark,
so `now.isAfter(before)` is true on every call after the first. The comment
above it said "writing only when something actually changes keeps this from
rewriting the conversation file on every rebuild" — the intent was right and
the predicate never implemented it. One conversation left open on screen
rewrote the file once a frame, for as long as it stayed open.

**The race.** `FileMessageStore.save` wrote the whole conversation into
`messages.json.tmp`, deleted the target and renamed the temp over it. The
controller calls for a save from several directions at once — a Transfer
settling, a conversation being opened, a message being deleted — and the
callback above did not await the save it asked for. So saves overlapped, and
two of them shared one temp file: the rename that landed while the other save
still held it open was refused, and Windows reports that refusal as another
program using the file. Every refusal became a notice, which is why the list
scrolled.

No test caught either half. There was no test that called
`markConversationOpened` twice, and no test that started two saves without
awaiting the first.

## Decision

**Make the guard hold.** `markConversationOpened` now returns before it touches
the file or notifies unless the mark would move something: a conversation never
opened before, a different one from the one opened last, or one still holding
messages the watermark does not cover.

```dart
if (before != null && !movedLast && unreadCount(peer) == 0) return;
```

The clock read moved after the guard, so a call that writes nothing also costs
nothing.

**Chain the saves.** `FileMessageStore.save` — and `FileProfileStore.save`,
which had the identical shape — now chains rather than overlaps:

```dart
final started = previous == null
    ? _write(json)
    : previous.then((_) => _write(json));
```

The chain is held by a future that cannot fail, so one rejected save does not
turn every later one into the same failure without trying; and it is cleared
when the newest save finishes, so it does not grow for the life of a process
that sits in the notification area for a week.

## Alternatives considered

**Have the page stop scheduling the callback on every build.** Rejected: it
fixes the symptom in one of the two call sites and leaves `markConversationOpened`
free to be called in a loop from anywhere else. The guard is the contract; a
call site that happens not to spin is not.

**Compare the reading state instead of the clock** — write only when
`toJson()` output changed. Rejected: it compares maps to answer a question the
watermark already answers, and it would still write on every rebuild whenever a
message arrives, because the state legitimately changed then. The unread count
is the question actually being asked.

**Write the temp file under a unique name per save.** Rejected: it removes the
shared-handle race but introduces two worse problems. Saves could then land out
of order, so an older snapshot could overwrite a newer one; and a save that
failed midway would leave a temp file behind per attempt, with nothing to clean
them up.

**Retry the rename a few times.** Rejected: it papers over a race that has a
cause, and it makes the failure slower instead of absent. A sharing violation
between two of this program's own saves is not something to wait out.

**Drop the delete-before-rename** in favour of renaming straight over the
target. Rejected as unnecessary here: with saves chained, no second save holds
the file, and the delete is what makes the intent readable. It also widens the
window in which a crash leaves no target at all, which the atomic write exists
to avoid.

**Give the conversation its own file per peer.** Rejected: a much larger change
than the defect, and it would trade one lock for a directory that has to be
enumerated, pruned and kept consistent.

## Consequences

- The Notices list no longer fills by itself, and an open conversation costs
  one write when it is opened and none afterwards.
- Two latent races are closed rather than one: `FileProfileStore.save` had the
  same shape and the same exposure, and is fixed the same way.
- `test/app/app_controller_test.dart` pins the guard with a counting store:
  opening a conversation writes once and twenty-five further spaced calls write
  nothing. With the old guard it recorded 27 saves.
- `test/history/message_store_test.dart` pins the chaining: eight saves started
  back to back and awaited together all succeed, leave the last one on disk and
  leave no temp file behind; and a save whose parent path is obstructed fails
  once and then succeeds normally once the obstruction is gone.
- The cost of the guard is one `unreadCount` per call, which is the same work
  the conversation list already does per build to draw its badges.
- Known gap: the chaining is per store, so two stores over the same path would
  still race. Nothing constructs two.

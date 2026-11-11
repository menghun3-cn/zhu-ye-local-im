# Agent Note: a drop stages in the composer like a pick

Status: implemented

## Problem

The composer had two rules for getting a file in. Choosing through the
paperclip, pasting, and — since
[a picked file waits in the composer](2026-10-09-a-picked-file-waits-in-the-composer.md)
— staging all ended in the attachment tray, waiting for 发送. A file dragged
onto the conversation was the exception: dropped on the history it was sent
the moment it was let go (`_sendDropped`), and dropped on the input field
itself it did nothing at all, because the `DropTarget` only wrapped the
history. Two roads into one box, two different promises — and the drop's road
did not even cover the whole box.

## Decision

**One road in, one rule.** The `DropTarget` now wraps the history *and* the
composer — the header stays outside, because it is chrome rather than
somewhere a message is written — and `onDragDone` ends in `_stagePaths`, the
same call the picker and the paste use. A dropped file appears in the
attachment tray and leaves only when 发送 is pressed. `_sendDropped` is gone:
there is no send-on-drop path left.

**The overlay says what the drop does.** It covers the whole drop area and
reads 松手加入输入框 (`dropToAttach`), replacing 松手即发送 (`dropToSend`), and
its icon moved from `file_download_outlined` to `attach_file` — both because
the promise changed from sending to attaching.

**This reverses the drop half of
[a picked file waits in the composer](2026-10-09-a-picked-file-waits-in-the-composer.md).**
That note's "a dropped file still sends immediately" no longer holds; it is
updated in place and cross-linked here, per the implemented-note rule that a
reversal gets a new note rather than a rewrite of the old one.

**`classifyDrop` is deleted.** It had no callers left — the drop path
classifies through `classifyPaths` like every other road in.

## Alternatives considered

**Keep send-on-drop and only widen the target.** Rejected: it keeps two rules
for one box — a drop sends, a pick waits — and the difference was never the
user's intent, only which road the file came in through. The request was for
the drop to behave like the rest of the composer.

**Stage on the composer but keep send-on-drop over the history.** Rejected:
two overlays, two promises, and a target whose meaning changed with the pixel
it was dropped on. One drop area with one rule is the version a user can
predict.

**Keep `dropToSend` as the key and only change its text.** Rejected: a key
that says "send" over a behaviour that attaches is the same kind of lie the
one-picker note already removed once. The packaging probe list
(`scripts/packaging-probes.json`) names the key, so it moved with the rename.

## Consequences

**Bought.** "Nothing leaves until 发送" is now a single rule with no
exceptions: pick, paste and drop all stage. The drop area also covers the
input field, which is where a drag onto a composer is expected to land.

**Cost.** A drop is one action slower — it takes a second click on 发送 —
and a user who learned "let go and it's gone" has to learn the tray. The
overlay text is the mitigation: it names the new promise while the file is
still in the air.

**Testing.** `test_flutter/ui/pages_test.dart` gains "a dropped file waits
until 发送 is pressed": the `DropTarget`'s `onDragDone` is invoked with a
`DropDoneDetails` — the OS drag itself is not drivable in a widget test — the
file appears in the tray with no Transfer yet, and 发送 produces it.

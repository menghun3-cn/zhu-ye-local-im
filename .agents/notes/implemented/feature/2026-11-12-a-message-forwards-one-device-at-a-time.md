# Agent Note: a message forwards one Device at a time

Status: implemented

## Problem

A conversation could send and could resend, but it could not *pass on*:
the words or the file that arrived from one Device had no way to reach a
second one except by being typed or picked again. The user asked for the
two shapes every messenger has — forward a single message, and pick
several and send them on — with one hard constraint: each forward goes to
exactly one Device, and a selection goes as one message per Transfer,
never bundled.

The constraint that shapes everything is what a forward *is*. It is not
a new wire message and not a copy of a record: it is a fresh send through
the same doors a typed message takes, which means it needs the content to
still be *here* — the words inside the `TransferView`, or the bytes at
`localPath`. Some messages cannot answer that question.

## Decision

**`TransferView.canForward` is the one predicate.** It lives next to the
view it judges (`lib/app/views.dart`) so the menu, the selection ticks
and the controller all ask the same question: settled, not an unsent
draft, and per kind — text/emoji need non-empty `text`; file/image need
`localPath` *and* exactly one name; clipboard is never forwardable. A
multi-item send keeps only an aggregate name, so half a folder is not the
folder and the message is not forwardable as a whole. Anything still in
flight is excluded because its bytes are not all here yet.

**Forwarding is sending, through the existing doors.**
`LocalTransferController.forwardMessage` dispatches on `PayloadKind` to
`sendText`/`sendEmoji`/`sendFile`/`sendImage`/`sendAppOwnedImage` — a
forwarded file arrives as an ordinary file offer the target answers, not
as a silent write. A file/image whose `localPath` no longer exists throws
`AppRefusal.localFileMissing` before anything is queued: a draft for bytes
that are not there would only move the failure to the resend.

**Offline is the draft road, not a refusal.** `noSessionOpen` and
`noPeerConnected` are caught and the content goes through
`queueUnsentMessage`, owed to the target exactly as a message typed while
they were away would be. Every other failure stays loud.

**`forwardMessages` is a loop, not a transaction.** Each view is sent in
the order given, one `Transfer` each; a failure counts and the rest still
go. The caller owns ordering — the conversation hands views over oldest
first, because `transfers` reads newest first — and the function returns
how many failed rather than throwing, so a batch toast can say
`forwardFailedCount` without losing the sends that worked.

**One dialog, both entries.** `forwardToPickedDevice`
(`lib/ui/forward.dart`) is the single road: the context menu's 转发 on one
message and the selection bar's 转发 on a batch both end at the same peer
picker — every peer listed, offline ones included and marked, connected
first then by name — and the same count-and-toast report. It returns
whether a target was picked so a selection mode can keep its ticks when
the user backs out.

**Selection mode replaces the composer, not the conversation.** 多选 on a
message's menu enters picking with that message ticked; bubbles of
forwardable messages grow a checkbox, ineligible ones get none rather
than a dead tick. The bar shows the count, 取消, and 转发. Tapping a
message toggles it; switching conversations or cancelling exits. The
original messages are never touched — a forward adds to the *target's*
conversation and leaves the source exactly as it was, including allowing
a forward back to the same peer.

## Alternatives considered

**Bundle a selection into one Transfer.** Rejected by the requirement
itself: the receiver must see the messages as the separate things they
were, each with its own state and its own delete. A bundle would also
need a wire shape that does not exist.

**Copy the `MessageRecord`s to the target's history directly.** Rejected:
it would fake arrivals — the target never consented, never answered an
offer, and its own device would hold messages its engine never saw. A
forward is a send, so it takes the send path and lands wherever a send
lands.

**Offer multi-item transfers anyway, forwarding the first file.**
Rejected: silently sending part of what the user sees is worse than not
offering the action at all. `canForward` says no up front instead.

**Fail the whole batch on the first error.** Rejected: the messages are
independent sends; one moved file must not take the rest of the selection
down with it. Counting failures and reporting the number is the honest
summary — the successful ones are already visible as new messages.

## Consequences

**Bought.** Forwarding needs no wire-protocol change, no new Transfer
kind, and no persistence change — a forwarded message is a `Transfer` like
any other, so history, unsent drafts, deletion and the settled-record
contract all apply unchanged. The two surfaces (single menu, batch bar)
cannot drift because they share `canForward` and `forwardToPickedDevice`.

**Cost.** `forwardMessages` sends sequentially and awaits each send, so a
large selection is a queue of round trips rather than parallel offers —
deliberate, since the order the user picked is part of the message. A
file that moves between the tick and the send fails individually and is
counted, not named; the toast says how many, not which.

**Testing.** `test/app/views_test.dart` pins `canForward` per kind.
`test/app/app_controller_test.dart`'s `forwarding` group pins the sends
against real paired Devices — order kept, offline becomes a draft, a moved
file counts as a failure, a live file arrives as an offer. 
`test_flutter/ui/forward_message_test.dart` pins the surface: the two menu
lines, the picker, the ticks, and the batch leaving as separate messages.

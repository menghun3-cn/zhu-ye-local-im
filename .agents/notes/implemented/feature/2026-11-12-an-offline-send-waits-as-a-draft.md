# Agent Note: an offline send waits as a draft

Status: implemented

## Problem

Sending to a peer with no Session used to end in a toast. `_target(to)`
refuses before a `Transfer` exists — `AppRefusal.noSessionOpen` when the
peer is named but unreachable, `AppRefusal.noPeerConnected` when nothing is
connected at all — and `guarded` turned that refusal into a line at the top
of the screen. The words the user typed were gone: not in the conversation,
not anywhere a resend could find them. For a messaging surface whose whole
promise is "what I wrote is still here", a send that evaporates on an
offline peer was the worst of the three outcomes — delivered, failed
visibly, or silently dropped — and it was the third.

The harder constraint is structural: an offline peer has no Session, so
there is no engine to mint a `Transfer` from, and `MessageRecord` — the
persisted shape a conversation is kept in — only decodes *settled* states.
A queued message is not an ending; it is a thing still owed.

## Decision

**A draft is its own record, kept beside the history.** `UnsentMessage`
(`lib/core/history/unsent_message.dart`) carries the peer, a locally minted
id, the kind, the timestamp, the names and byte count, the body or the
local path, and an `appOwned` flag for the one file this app may take away
again — the temporary image a paste writes. It is *not* a `MessageRecord`
with a made-up state: the history reader refuses anything that is not an
ending, and a draft is not one.

**It persists in the same envelope, under its own key.** `StoredConversation`
gains `unsent`, written and read next to `messages` and `reading`. The
format version stays 1: the key is additive, an older build ignores it
exactly as it does `reading`, and a newer build reads an old file as an
empty draft list. `LocalTransferController` keeps the drafts in `_unsent`,
loads them in `_loadHistory`, and merges them into `transfers` through
`_viewOfUnsent` — an outgoing view in the settled `failed` state (nothing
in flight, so no progress bar and no cancel button) with `TransferView.unsent`
set, which is the one flag that tells "owed" apart from "broke on the
wire".

**Queueing happens at the refusal, not before it.** `_sendOrQueue` in the
conversation catches only the two offline refusals and calls
`queueUnsentMessage`; every other refusal is still a real error and still
toasts, because queueing it would hide a bug behind a draft. Each staged
item is handled independently, so a send that is half online — text through,
file refused — lands each part where it belongs.

**The marker is the interface.** An unsent bubble draws a red
`Icons.error_outline` to the left of the bubble — the side the message came
from is already spoken for by the avatar — and a tap opens a resend dialog:
the preview (the words, or the file's name), 重发, 取消. 取消 leaves the
draft exactly as it was. An unsent *image* keeps its bubble rather than the
bare-image path a delivered picture takes, because the bare image has
nowhere to put the marker.

**Resend is a fresh send, not a mutation.** `resendMessage` removes the
draft, routes it through the same `sendText`/`sendFile`/`sendImage`/
`sendAppOwnedImage` doors a new send takes, and lets the real `Transfer`
appear at the newest end of the conversation. Any failure — the peer is
still offline, the file has been moved — puts the draft back and is said
out loud. The draft's id names the attempt; the Transfer's names the
delivery, and the two are deliberately different things.

**Drafts die with their conversation.** `deleteMessage`, `clearConversation`
and `deleteConversation` all take the drafts with the rest, and the last
also collects `appOwned` draft paths for deletion alongside the tracked
ones. `deleteMessage` deletes an app-owned draft file itself: a picked file
is the user's and stays, but the temporary image a paste wrote has no other
owner once the draft is gone.

## Alternatives considered

**Fabricate a settled `MessageRecord` with `state: failed`.** Rejected:
the record's reader validates that only endings decode, and a failed state
would claim something was offered and broke. Nothing was offered. It would
also put "not sent yet" and "sent and failed" in the same bucket, and only
one of them can be resent into a new Transfer without lying about the old
one.

**Queue optimistically, before the send is refused.** Rejected: a send
that succeeds would have to be un-queued, and a send refused for a reason
that is *not* offline — several peers and none named, an offer already
answered — would be silently kept as a draft instead of reported. Catching
the two named refusals keeps every other failure loud.

**Keep the draft in memory only.** Rejected by the requirement itself: the
user asked for unsent messages to survive a restart with the conversation.
The `unsent` key in the existing envelope is the smallest persistence that
delivers that, and it costs older builds nothing.

**Turn the failed bubble green in place on resend.** Rejected: the draft's
id is not a Transfer id, there is no engine object to mutate, and "the
message you see change state" would be a view-layer fiction over two
different records. A new Transfer at the newest position is honest about
what happened — a second attempt, at a later time.

## Consequences

**Bought.** An offline send is now visible, marked, and resendable; it
survives a restart; and the wire protocol, the Transfer state machine and
the settled-history contract are untouched — a draft never pretends to have
been a Transfer. A send that fails *after* it started (the peer drops
mid-transfer) still lands on the ordinary failed-history path, which is
unchanged and correctly distinct.

**Cost.** `transfers` now merges three sources, and every consumer of
`TransferView` sees a new flag it must respect — `send == null` and
`unsent == true` are the contract. A draft whose file has been moved or
deleted fails at resend time rather than at queue time: `queueUnsentMessage`
stores the path, not a promise the bytes are still there, and the restored
draft plus the toast is the honest answer.

**Testing.** `test/history/unsent_message_test.dart` pins the codec —
round-trips, and the malformed shapes a hand-edit could produce.
`test/app/app_controller_test.dart`'s `unsent messages` group pins the
behaviour against real paired Devices on separate beacon networks: queue,
resend-while-offline restores, resend-after-connect delivers, restart
persistence through `MemoryMessageStore`, deletion, and the argument
refusals. `test_flutter/ui/unsent_message_test.dart` pins the surface: the
marker, the dialog, 取消 leaving the draft owed, and a file draft naming
itself.

# Agent Note: a conversation outlives the process

Status: implemented

## Problem

A conversation was never written down. `LocalTransferController` held every Transfer this run had
taken part in as a `_Tracked` in a list, the conversation list and the conversation view both read
that list, and the process ending was the conversation ending. Two things followed, and both were
visible to a user within a day of using the product.

**Restarting emptied every conversation.** A Device that had been talking to another one all morning
came back with nothing: the same peer, the same name, the same address in the header, and no
history under it. The Transfers surface was no better — it filters the same list.

**The list was bounded at a hundred, and the bound deleted history.** `_pruneTransfers` drops
settled records once the list is longer than that, which is right for a live list and wrong for the
only copy there is: a busy conversation quietly forgot its own beginning.

Alongside that, there was no way to take one message off the screen at all. A right-click offered
"show me where that file went" and "copy that picture" and, for a send still in flight, "stop
sending" — and for a text message, which is most of them, nothing: the menu did not even open,
because a handler that opened an empty menu would swallow the right-click that selects a name.

## Decision

**A message is remembered when it ends, as a record rather than as a handle.** Settling is what
turns a Transfer into history, and it is the only moment at which there is something worth keeping:
before that, a message is either a question somebody is still waiting on or bytes that have not
arrived. `MessageRecord` therefore holds what a conversation would show about a message that is
over — who, what kind, when it arrived, when it ended, how it ended, the items, the body of a text,
and where its bytes landed — and holds none of the live parts. The offer a user could answer and
the send a user could stop were objects belonging to a Session, and a Session does not outlive the
process either.

**The conversation is written to a file of its own, `messages.json`, beside `profile.json`.** Same
directory, because both are per-user state belonging to this installation rather than to the user's
documents. A different file because the two have nothing to do with each other: the profile holds
an identity nobody can afford to lose and is written rarely, while the conversation changes every
time somebody types and could be rebuilt by talking again. `MessageStore` is the same
interface-and-two-implementations shape `ProfileStore` already has, `FileMessageStore` writes
through a temp file and renames, and a file that will not decode is moved aside as `.corrupt` and
reported in `notices` — a conversation is not worth refusing to start over.

**The whole list is written every time.** Archiving happens once per message and deleting once per
delete; a person sends a handful of messages a minute at the very most. There is nothing a journal
would buy at that rate, and a single file that is always either the old list or the new one is a
file a reader can trust. The list is bounded at `maxRememberedMessages` (1000) from the oldest end,
which is the end a person has scrolled away from.

**`transfers` is the live list and the record, joined on a handle.** A message in the current run is
drawn from its `_Tracked`, because that is what has real state and real byte counts to report;
a message from an earlier run is drawn from its record, where every accepted byte has arrived and
the fraction is one. They describe the same message for as long as both exist — archiving does not
remove anything from the live list — so they are joined on `TransferView.handle` rather than
concatenated, and the live one wins. The order is by `at`, newest first, with the id as a tie-break:
`List.sort` is not stable, and two messages stamped in the same millisecond would otherwise swap
places while somebody was reading them.

**A handle is the peer and the Transfer's id.** The id is minted random and unique *within the
Session that carried it*, which is not a lifetime: reopening a Session and sending again produces a
new id, and the two Sessions are one conversation. What survives every Session is the peer, so the
pair is what names a remembered message. The separator is a NUL, which neither a fingerprint nor a
hex id can contain.

**Deleting a message is local, one-sided, and unconditional.** It takes the message out of the live
list and out of the record, writes the conversation out, and tells the peer nothing — there is no
wire message for this and there should not be one, because a conversation either end could edit is
a conversation whose two sides cannot be trusted to agree. The bytes stay where they landed; a
picture that was received is still a file the user has, and "delete this message" in every messaging
application a user has met means "take it off my screen".

**A message deleted while it is still moving stays deleted.** The Transfer itself keeps going: the
engine owns it until it ends, and stopping it is a *different* action, which the same menu offers a
line above. So the record is flagged (`_Tracked.dismissed`) and the callback that would have
archived it checks the flag — without that, the ending would put the message back on screen a
moment after the user removed it.

**Every message offers Delete, so the right-click is always intercepted.** That is a deliberate
change in behaviour for text messages, which used to pass the right-click through so that a name
could be selected and copied. The menu now always has something in it, so the guard that kept an
empty menu from swallowing the gesture has no case left to apply to.

**A text message's words are plain text, and copying them moved into the menu.** A `SelectableText`
body brings a gesture recognizer of its own, and Flutter hands a tap to the innermost member of the
gesture arena — so a secondary click on the words opened the platform's copy/select-all toolbar and
never reached the message's menu. Delete would have been offered on every kind of message except
the one a person sends most. The words are therefore drawn as a `Text`, and `Copy text` sits in the
shared menu beside the picture's `Copy image`: the capability moved rather than left, and it now
copies the whole message rather than the words the pointer happened to be over.

## Alternatives considered

**Keep the conversation in `profile.json`.** Rejected: the two have opposite write patterns and
opposite value. The profile is rewritten rarely and holds the identity seed and the group secret;
the conversation would be rewritten every time a message ends. Sharing a file would mean a
corrupt or truncated conversation could cost a Device its identity, which is the one loss this
product cannot recover from — the profile store's own doc comment says as much about why it moves a
damaged profile aside rather than overwriting it.

**Serialize the `Transfer` or the `TransferView` as it stands.** Rejected: both hold live objects —
streams, completers, the offer and the send. A remembered message has no live parts by definition,
and a format that carried them would be a format that promised, on every restart, to restore things
that cannot be restored.

**Remember unanswered offers too.** Rejected: an offer is a question the *other* end is waiting on,
and the other end is not waiting any more — its Session died with whichever process ended first.
Restoring one would put Accept and Refuse buttons on screen for a Transfer nobody would answer,
and the buttons would fail when pressed.

**Make Delete also cancel a Transfer in flight.** Rejected: they are different wants and the menu
offers both. "Stop sending" is about the wire and the peer is told; "delete" is about this Device's
record and the peer is not. Fusing them would mean a user who wanted a message off their screen
also had to interrupt a transfer that was working.

**Tell the peer that a message was deleted.** Rejected: the protocol has no message for it, and
adding one would make a conversation something either end could rewrite. The product's whole
premise is that two Devices report the same bytes; a delete that travelled would be the first
exception to that, and there is no user story that needs it.

**Draw the list in insertion order, as the live list did.** Rejected: insertion order is a fact
about this process, and a conversation that outlives the process has no insertion order to appeal
to. Timestamps are the only ordering that survives, and they needed a tie-break because nothing
guarantees two messages differ in their millisecond.

**Key the two lists by position, or by the Transfer id alone.** Rejected: the id is unique only
within a Session, so two Sessions with one peer — before and after a restart — could collide, and
position says nothing at all once the record is loaded from a file.

**Keep the message body selectable, and let the platform's toolbar answer a right-click on the
words.** Rejected: it leaves Delete unreachable on exactly the messages it is wanted most. The other
way to keep both — suppressing the toolbar and opening the menu from a raw pointer listener that
skips the gesture arena — is a parent reaching over a child that Flutter deliberately gave the
gesture to, and it leaves a selectable body collapsing the user's selection on every right-click
for no visible reason. One menu per message is also the rule `TransferContextMenu` exists to
enforce.

## Consequences

**A conversation now costs a file, in the clear.** The record holds the text of every message and
the path of every received file, written as JSON, unencrypted, in the same per-user directory as
the identity seed. That is a real change in what is at rest on disk, and it is the honest reading of
"persist the conversation": encrypting the file would need a key, and the only key this Device has
that survives a restart is the one the profile already stores beside it. Recorded as a known
property rather than a gap to close.

**Pruning no longer loses history.** A settled Transfer dropped from the live list has already been
archived by then, so the message stays in the conversation; the live list is now only what the
current run has to draw with real state.

**The two lists have to agree, and a test says so.** `transfers` merges them on the handle, so a
message that is in both must draw once, and a deletion must remove both. `test/app/app_controller_test.dart`
gained a group of its own for this: a settled message read back by a second Device over the same
store, a delete that takes the message off the screen and out of the file, a delete that leaves the
rest of the conversation, an unanswered question that is *not* remembered, a message deleted while
it was moving that stays deleted, and the ceiling dropping the six oldest of a pre-loaded record.
`test/history/` covers the record's own round trip and the file store's bad-input paths.
`test_flutter/ui/delete_message_test.dart` covers the other half, on the screen: a text message —
the kind with nothing on disk behind it — offers Delete and Copy text and no more; a landed file
still offers its folder beside Delete; and Copy text hands the whole message to the clipboard while
a file is never offered it.

**A right-click on a text message now opens a menu.** The one visible cost of Delete being
unconditional, and the reason it is written down here rather than left to be discovered: selecting
a name inside a message with the secondary button no longer works, because the gesture is
intercepted. The Transfers surface and the conversation both draw the same menu, which is what the
shared `TransferContextMenu` has always been for.

**A message's words are no longer range-selectable.** They were a `SelectableText` and are now a
`Text`, for the reason above. What that costs is dragging a selection across part of a message; what
it replaces it with is `Copy text`, which copies all of it and works on a message read back from
disk as readily as on one sent a moment ago. Worth knowing rather than discovering: Ctrl+C over a
dragged selection inside a bubble no longer does anything.

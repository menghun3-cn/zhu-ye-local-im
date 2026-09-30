# Agent Note: A conversation per paired Device

Status: implemented

English | [中文](2026-09-30-a-conversation-per-paired-device.zh.md)

## Problem

Once two Devices were paired and connected there was nowhere to send anything.
The Devices card offered Pair, then Connect, and then a small overflow menu whose
entries were "send text", "send file" and "trust" — three destinations that all
mean *talk to this Device*, offered as three separate things, one of which was
not about talking at all. Sending was a dialog per message: pick a file, confirm
a path, and watch the result appear on a different surface (Transfers) where it
sat among every other Transfer in the app, with no visible relationship to the
text that had been sent a moment before. A user who wanted to send a file to a
paired Device had to find the card, find the menu, and pick the right entry.

The Transfers surface is a good answer to "what is happening across all my
Devices" and a poor answer to "talk to this one". Nothing in the app was that
second answer.

## Decision

Tapping a connected Device's card opens that Device's conversation, and the
conversation is where sending lives.

`ConversationPage` is keyed by the peer's `Fingerprint` — the same identity the
wire uses — and reads everything it shows out of the controller it already
notifies on:

* The AppBar shows the peer's name and its address, on screen for the whole
  conversation. That address is the answer to "which machine am I actually
  talking to", and it is the thing a user needs when they walk over to the other
  one.
* The history is every Transfer the controller holds for that peer, rendered
  newest-first (`ListView(reverse: true)`, so the newest message is at the
  bottom). Outgoing messages sit right, incoming left. A text payload shows its
  body — `TransferView.text`, carried through from `Transfer.text` for exactly
  this — and a file shows its names and `bytesOf` progress. Clipboard entries
  are filtered out: they travel as Transfers too, but they are mirrored rather
  than written and read, so they would be noise here.
* An offer that has not been answered shows its Accept and Refuse inside its own
  bubble, so the thing that arrived and the decision it needs are in one place.
* The composer at the bottom is a `TextField` (Enter sends), an attach button
  (the existing file picker, `showSendFileDialog`) and a send button. Text goes
  out through `controller.sendText`, addressed to the peer's Fingerprint rather
  than to a position in a list.
* Trust moved here, into the AppBar's overflow menu: the two things that act on
  one Device — send it something, trust it — are now on that Device's screen.

The answer to an offer is written once. `acceptOffer` and `rejectOffer` live in
`lib/ui/transfer_actions.dart` and are used by both the Transfers list and the
conversation, so a file accepted from one is accepted by the same code as from
the other, including the folder question and the `defaultIncomingDirectory`
fallback.

On the card, one action per state: **Pair** when the peer is not in the group,
**Connect** when it is but has no Session, and the card itself — with an "open
conversation" button beside the name — once a Session is open.

## Alternatives considered

**Keep the overflow menu and add a conversation to it.** Rejected: it keeps the
menu, which was the problem. Three peer-scoped actions behind one icon is three
things a user has to learn; a card that opens the conversation is one thing they
already know how to do.

**Open the conversation on a long-press.** Rejected: the card tap was already
the "do the obvious thing with this Device" gesture. A long-press target is
invisible, which is why the menu it would have replaced was not discovered
either.

**One global conversation list, all Devices in one view.** Rejected: a group can
hold several Devices and the wire has no notion of a conversation spanning them.
One page per Device keeps the peer key — a `Fingerprint` — as the identity, and
the Transfers surface already covers the across-Devices case.

**Let the page keep its own list of what was sent, appending as it arrives.**
Rejected: the controller already owns the Transfer list, and a second place that
remembers what was sent would have to be kept in step with it — and would lose
history whenever the page closed.

**A real messenger: delivery ticks, typing indicators, conversations that
survive.** Rejected as false promises on this wire. There is no server and no
persistent channel: a Session exists while both Devices are up, and the protocol
has no application-level acknowledgement that would let a tick honestly mean
"delivered" or "read". What the bubble shows instead is what is actually known —
the kind, the state, and the progress.

## Consequences

- Sending a file to a paired Device is now: tap the Device, tap attach, pick the
  file. The text that went with it is in the same scrollback.
- `showSendTextDialog` is gone. Text is typed in the composer and sent through
  `controller.sendText`; there is no dialog whose only job was to collect one
  line.
- The Devices surface no longer carries peer-scoped actions other than opening,
  pairing and connecting, and `DevicesPage` now takes `defaultIncomingDirectory`
  so the conversation it pushes can answer the folder question the same way the
  Transfers surface does.
- `test_flutter/support/ui_harness.dart` grew `openConversation`,
  `onConversation` and `conversationOffered` so a test can walk from the card
  into a peer's thread, assert within it, and wait for the card to offer it
  before tapping. `onConversation` is built with `find.descendant` and **not**
  `find.ancestor`: the ancestor form collapses to the `ConversationPage` widget
  itself, which is fine for `isNotEmpty` and silently wrong for a tap — the tap
  lands in the middle of the message list rather than on the control named.
  `test_flutter/ui/pages_test.dart` uses them to check that a Device with an
  open Session offers its conversation, and
  `test_flutter/e2e/two_window_e2e_test.dart` drives a file from Alice's
  conversation to Bob's Transfers surface through them.

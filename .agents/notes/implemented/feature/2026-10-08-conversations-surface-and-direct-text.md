# Agent Note: A Conversations surface, and text that needs no answer

Status: implemented

English | [中文](2026-10-08-conversations-surface-and-direct-text.zh.md)

## Problem

Two complaints, one about what the app does and one about where it says it.

**Text waited for an answer.** Every Transfer was offered and answered: an
incoming offer landed on the Transfers surface with Accept and Refuse buttons,
and nothing moved until the receiving user tapped one. That is right for a file
— it writes bytes into a folder somebody has to choose — and wrong for a line of
text. A text item carries its body inside the offer and takes no sink, so
accepting it commits nothing, writes nothing, and has no answer a user could
plausibly give differently. Prompting for it was a question with one sensible
answer, and it made the thing a conversation is made of stall on a tap: two
people typing at each other had to press Accept on every line before the other
saw a word.

**The conversation was behind a door.** [The conversation per paired
Device](../2026-09-30-a-conversation-per-paired-device.md) gave every peer a
thread, but reaching it meant going to the Devices surface, finding the card,
and tapping it — and only then, if the Device was not connected yet, pressing
Connect first. A user who had just connected had to know that the next step
existed. There was no way to see the Devices worth talking to and the thread
with one of them at the same time, and no way to move between threads without
walking back to a list of hardware.

## Decision

Two changes that belong together, because the first is what makes the second
worth looking at.

### Text is accepted on arrival; a file is still a question

`LocalTransferController._onOffer` sorts an incoming offer by kind. A text
Transfer is accepted by the controller the moment it arrives — `_acceptInline`,
which calls `offer.accept(itemIds: …)` with **no sinks**, because a text item
has no digest by construction and `accept` rejects a sink for an item that
streams nothing. A file Transfer goes to the `incoming` stream and waits, as
before.

The rule is stated in one place and defended in another. `_onOffer` is the
decision; `_viewOf` is the second line of defence, where a `TransferView` only
carries an `offer` when the Transfer is an `IncomingTransfer`, is decidable, and
is **not** text. `TransferView.offer` is the single field that decides what a UI
is allowed to answer, so the rule lives at both ends of it rather than in the
pages.

This is a genuinely asymmetric rule and the asymmetry is the point: a file
writes bytes into a folder the user picks, so it is a question; a text item is
already in memory, so there is nothing left to decide. An error accepting a text
becomes a notice rather than a dialog, for the same reason — it is not a
question the user failed to answer.

### A Conversations surface, left list and right thread

The shell has five surfaces now, and the second is Conversations
(`ConversationsPage`, `lib/ui/pages/conversations_page.dart`). Wide windows
(≥720 logical pixels) get a WeChat-shaped two-pane layout — a 300-pixel list of
threads, a divider, and the open thread beside it. Narrow windows show one at a
time with a back button, because two panes at 400 pixels is two unusable panes.

The thread list is built from `controller.peers` as the skeleton, keeping a peer
when it is connected **or** has history, and ordered connected-first, then
waiting-for-an-answer, then by name. A peer with a live Session and a peer with
a week of scrollback are both worth showing; a peer that was paired once and has
neither is not.

The body of a thread is `ConversationView`, which is the message list, the
bubbles and the composer extracted from what was `ConversationPage` — with the
`Scaffold` and `AppBar` left behind. `ConversationPage` is now a thin shell
around one, and the Conversations surface puts one in a pane. Two ways to reach
one conversation, one widget underneath: the composer, the history and the two
answers are the same code either way, which is why the tests find a conversation
by `ConversationView` rather than by which route or pane it arrived in.

Tapping a connected Device on the Devices surface now runs Connect and then
lands on the Conversations surface with that thread open, through a
`onConversationRequested` callback the shell hands the page. It is a surface
switch rather than a pushed route, so the list stays beside the thread.

## Alternatives considered

**Let the user choose, per Transfer, whether text needs an answer.** Rejected:
it is a preference about a question with one answer. A setting that can only
make the common case worse is not a setting.

**Answer text at the UI layer instead — auto-accept in the page when a text
offer renders.** Rejected: the offer reaches a screen late, and only if a screen
is listening. A text sent while the app is on another surface would sit
unanswered until the user navigated to it, which is the same stall the change
was meant to remove, plus a dependency on which surface happens to be up.

**Drop the offer/accept step from the protocol entirely and stream every
payload.** Rejected: files still need the answer. The receiving user has to
choose a folder, and the protocol's acceptance step is what makes a refused file
cost nothing — no bytes cross the wire before somebody says yes.

**A `TabBar` inside the conversation, one tab per Device.** Rejected: a group
can hold several Devices and the tabs would grow without bound, and a tab is not
a list — it has no room for the address, the unread mark or the ordering that
says which thread matters.

**Keep the conversation as a pushed route and add a list surface separately.**
Rejected: two places that both mean "this Device's conversation", reached two
different ways, with a back button that behaves differently depending on which
one you came through. One surface holds both halves.

**Put the Conversations surface first, ahead of Devices.** Rejected for now:
pairing and connecting are still the things a new user has to do first, and the
Devices surface is where both live. This is a decision that can be revisited
once a Device is set up once and used for a long time.

## Consequences

- Two people typing at each other no longer press Accept per line. `dart test`
  grew two cases that pin the asymmetry: text arrives with
  `TransferState.completed`, `needsDecision == false` and an empty `offers`
  stream, and a file does not.
- `incoming` no longer carries every incoming Transfer — it carries the ones
  that are questions. Two tests that used a text Transfer to reach an offer were
  rewritten to use a file, because a text offer no longer exists to reach.
- `ConversationPage` lost its state and most of its body; `ConversationView`
  owns the message list, the composer and the two bubbles, and
  `ConversationComposer` and `MessageBubble` are public for it.
- `test_flutter/support/ui_harness.dart` has five surface constants where it had
  four, and `onConversation` now looks for a `ConversationView` rather than a
  `ConversationPage` — the two-pane layout and the pushed route both put one on
  screen, so keying on the page would have made a test depending on how the
  thread was reached.
- `tempDirectory`'s cleanup is now best-effort. An undecided file Transfer holds
  its source file open, and Windows fails the delete rather than the test's
  assertion — failing a test over the cleanup of a directory under the system
  temp is the wrong failure.

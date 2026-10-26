# Agent Note: A sent text does not flash a transfer card

Status: implemented

English | [中文](2026-10-26-a-sent-text-does-not-flash-a-transfer-card.zh.md)

## Problem

Sending a text message kept its transfer visible as *in flight* while the
accept round trip was still crossing the wire. A card carrying an "sending"
state and a progress bar flashed in the conversation for a frame or two and
then resolved into the message — progress bookkeeping for work that had not
started, out of proportion to the effect it described.

## Decision

An inline payload settles the moment its acceptance is sent. Its body already
travelled inside the Offer, which the record layer authenticated, so there is
no byte stream to move and no digest to verify afterwards; the accept and the
verification round trips are only a confirmation of a fact this Device already
knows. Reaching `TransferState.completed` directly from the acceptance keeps
both ends of a text or emoji message from drawing an in-flight card that has
nothing to measure.

The conversation draws a progress bar only under a file — the one payload with
bytes still moving across the wire — and the Transfers surface draws one only
for a file as well. A text or face message never flashes a bar again.

A clipboard entry keeps the ordinary accept-then-complete flow. Mirroring is
not a message: the mirror applies it on its own schedule, it renders nowhere,
and its transfer bookkeeping is not what the flicker was about.

## Testing

The engine-level acceptance test for an inline item now expects the transfer to
settle on acceptance instead of on the sender's later `complete`, and a new
clipboard test pins the other half of the rule. The conversation widget test
that sends text asserts there is no progress bar under the sent bubble.

## Alternatives considered

**Hide the progress bar in the conversation only, and leave the transfer
settling when the final message arrives.** Rejected: the state machinery would
still model a text as in flight with nothing moving, and a future surface that
forgot the visual rule would reintroduce the same flicker elsewhere.

**Show the message optimistically and mark it unconfirmed until the round trip
finishes.** Rejected: it doubles every message's visual states for a delay that
is normally one frame, and this application's transfers settle on the peer's
word by design.

**Make every inline payload settle on acceptance, clipboard included.**
Rejected: clipboard mirroring has its own lifecycle and is not a conversation
message; changing its settle semantics would touch mirroring behaviour to fix
a chat flicker.

## Consequences

- A sent text or face appears directly as the message, with no in-flight card.
- Received text settles on acceptance, right after the controller answers it.
- File and image transfers keep their progress bars, on both surfaces.
- Clipboard mirroring keeps its existing accept-then-complete flow.
- The `TransferCompleted.digests` map reports an empty digest for an inline
  item, which already carried no digest to verify.

# Agent Note: A send in flight can be stopped, and a wait ends in a day, not a minute

Status: implemented

English | [中文](2026-10-10-a-send-in-flight-can-be-stopped.zh.md)

## Problem

Two things a user could see happen to a file being sent, both wrong in the same
direction: the transfer gave up too easily and could not be stopped.

**The wait.** A four-megabyte file was offered to a peer whose dialog sat
unanswered. Sixty seconds later the sender's transfer failed —
`acceptanceTimeout` is 60 seconds — while the receiver's offer stayed on
screen, buttons and progress bar and all, forever. The asymmetry was by design:
`TransferLimits`' doc says the two timeouts are the sender's, "a receiver that
is mid-write has a Transfer the user can cancel". But the sender's giving up
was *silent*: `watchAcceptance`'s timer called `finish(TransferFailed(...))`
and told nobody. The receiver keeps no clock precisely so that a slow answer
never fails — which left the one side without a timeout holding a question
whose asker was gone.

**The stop.** The sender could not cancel at all. `OutgoingTransfer.cancel`
existed — finish locally, `CancelMessage` to the peer — but nothing in the
interface called it. A file picked by mistake, an offer the other side will
never answer, a payload crawling over a half-dead link: every one of them sat
on the screen with no way out. And the receiver-side consequence compounded:
with no cancel, the *only* exits from the receiver's stuck state were a
session death or an answer.

**The width.** A file bubble stretched across the whole conversation pane,
whatever its name. The cause was mechanical: the bubble's content column is
laid out under a loose width constraint, and a `LinearProgressIndicator` fills
whatever it is given — so the bar took the whole pane and the bubble, sized by
its widest child, followed. A five-character name drew a bubble six hundred
pixels wide.

## Decision

Three changes, each aimed at one of the three.

**The timeout becomes a workday.** `acceptanceTimeout`: 60 seconds → 24 hours.
The question sits in a dialog on the far side, and the person it is for may be
away; a sender that gave up sooner failed a transfer its user still means to
send. This is affordable *because* of the next change — waiting costs the
impatient nothing when they can stop by hand. `verificationTimeout` stays at
120 seconds on purpose: verification is hashing, seconds of work, and a sender
silent there has been hung up on rather than kept waiting.

**A timeout and a cancel both tell the peer.** Both of the sender's timeout
paths now go through one `_expire` helper: `finish(TransferFailed(...))` and
then `sendQuietly(CancelMessage)`. The receiver's `onCancel` settles its offer
as cancelled, which is the honest word for "the sender walked away". This is
what makes a 24-hour timeout safe to sit through — every other ending already
reached the peer.

**The UI hands out the send and offers the stop.** `TransferView` gains
`send` — the live `OutgoingTransfer` while it is unsettled, null otherwise, on
the same terms as `offer` hands out a live `IncomingTransfer`. From it:
a 取消发送 button in the bubble where the receiver's Accept/Refuse sit (the
same kind of question — one only the person looking at the bubble can settle),
and a 取消发送 entry in the right-click menu, which is how a bare outgoing
image — bubble-less by design — reaches the same action. The receiver gets
none of this: its counterpart is `reject` on an offer it has not answered.

**The bubble takes its name's width.** The file block — name rows, size line,
progress bar — is drawn at a *measured* width: `TextPainter` lays out the
longest name (and, for a file, the size line) on one line, the result is
clamped into `WeChat.transferBubbleMinWidth` (160) and
`WeChat.transferBubbleMaxWidth` (280), and the name cuts off with an ellipsis —
whole name on the tooltip — when it exceeds the cap. The answer buttons sit
outside the measured block, so a bubble is the max of the two and nothing
overflows. Text bubbles are untouched: their kind never enters the measured
path.

## Alternatives considered

**A receiver-side timeout.** Rejected: it is the opposite of the design's
grain. A receiver mid-write on a slow link should never fail for being slow —
and now it never has to, because the sender's clock comes with a voice.

**A shorter timeout plus an "are you still there?" re-offer.** Rejected: a
protocol round trip and state machine additions to solve a problem a cancel
button and a generous clock solve with neither. The Offer stays a question
answered once, not a lease renewed.

**Cancel as a context-menu item only.** Rejected for the bubble: a stop that
lives behind a right-click is a stop nobody finds, which is the same reasoning
that puts Accept and Refuse in the open. The menu carries it too, but for the
bare image's sake, not instead of the button.

**`IntrinsicWidth` instead of measuring.** Rejected: the progress indicator's
intrinsic width is unbounded, and an `IntrinsicWidth` over an unbounded child
either asserts or degenerates to the full pane — the exact bug — depending on
how the constraints land. Measuring the texts with `TextPainter` is four lines
and deterministic.

**Capping only the progress bar.** Rejected: a bar capped at 200 under a name
row that measures 90 pins the bubble at 200 — a short name still cannot shrink
what it should. The bar has to take the *content's* width, which is what the
measured block gives it.

## Consequences

- A receiver whose sender gave up — by timeout or by hand — sees its transfer
  settle as cancelled within a beat, instead of filling in forever.
- A sender's Offer waits a workday for an answer it can stop waiting for.
- A file bubble hugs its name: measured, floored, capped, ellipsised, with
  the full name one hover away.
- `dart test` 444/444 (the unanswered-offer test now also asserts the far side
  settles); widget coverage for the bounded bar and the cancel button lives in
  `test_flutter/ui/transfer_bubble_test.dart`.
- New l10n: `cancelSend` (取消发送). The packaging script's probe list gains
  it; `Icons.close` was already in the subset.

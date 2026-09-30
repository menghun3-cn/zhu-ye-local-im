# Agent Note: Accepting the request is the whole approval

Status: implemented

English | [中文](2026-09-30-accepting-the-request-is-the-whole-approval.zh.md)

## Problem

Pairing had already lost the typed code, but it still ended in a comparison:
both Devices drew the six digits the handshake derives, and both users were
asked to confirm that the two screens agreed before either side committed. The
person answering therefore made one decision and was immediately handed a
second one — the same request, the same answer, and a step that existed only
because the flow had always had it.

The case for the digits was also overstated, and worth stating precisely. Both
screens agree on the digits **whatever peer dialled**: the string is derived
from the handshake and from the two Fingerprints, and the Fingerprint a caller
sends is a claim, not a fact. A stranger on the link that dials this Device and
gets as far as the question sees exactly the digits this Device shows it. What a
two-screen comparison does catch is a **relay** — a third Device sitting on the
wire between the two people, running half a handshake with each. What it never
caught is the situation the interface actually has to answer: a Device on this
link started a Pairing, and someone has to decide whether to let it in.

That someone is shown the caller's name and told, in the same sentence, that the
name is only what the caller calls itself. That sentence plus the tap is the
admission check. A number underneath it, which the two screens would have agreed
on anyway, was presented as if it were more than that.

## Decision

The question has two answers and no third step. `PairingRequest.admit()` and
`PairingAttempt.confirm()` now run back to back from a single button
(`l10n.acceptPairing`, `l10n.refuse`), and the initiating Device confirms itself
as soon as its own user has asked — so neither side waits on a comparison that
no longer happens.

* `_PairingRequestDialog` keeps one state: asked, then settled. Its Accept calls
  `admit()` and then `confirm()` on the same attempt, and reports
  `l10n.pairingCompleting` while the exchange finishes. `_PairWithPeerDialog`
  does the same to the attempt `pairWith()` returned, and then opens the Session
  (`connectAfterPairing`) as before.
* The short authentication string is still derived and still load-bearing on the
  wire. `SecureLink.shortAuthenticationString` feeds `_pairingContext`, which a
  Pairing signs its admission over — `pair ` plus both Fingerprints in sorted
  order plus the digits — so the two sides must still agree on the value for the
  signature to verify, and a signature cannot be carried from one handshake into
  another. What is gone is the display: `PairingOutcome.sas` and
  `PairingAttempt.sas` still carry it and no screen reads either.
* The widgets that showed it are deleted, along with the strings that named the
  step: `_BigCode`, `_Confirmation`, `compareDigits`, `theyMatch`,
  `pairingPreparing`, `continuePairing` and `cancelThisPairing`.
* The phase the answering side moves a caller into is no longer called the
  comparison — `_Receiving.decide` and its `_deciding` set — because that is not
  what happens next.

The compensating controls are the ones already in place, and they are worth
naming because they are now the whole of it: the caller's claimed name is on the
question with the sentence that says it is a claim, the question is an ordinary
dialog the user can refuse, answering can be switched off with the preference
surviving a restart, and the responder only offers its group secret to a peer
whose admission it has read.

## Alternatives considered

**Keep the digits behind a "show details" disclosure.** Rejected: the check is
worth something only if a person performs it, and an app cannot tell whether one
was performed. A control that is optional, unverifiable, and skipped by everyone
who does not already know why it matters is worse than no control, because it is
still documented as one.

**Show the digits on the answering side's final screen, after the answer.**
Rejected: they would then arrive *after* the decision they are meant to inform.

**Keep the digits only when the answering Device has no group yet.** Rejected:
extra state for a threat the digits do not cover. Both screens agree whatever
peer dialled, so restricting *when* they are shown does not turn them into a
check on *who* is asking.

**Let the listener admit a caller automatically, with no tap at all.**
Rejected: that is "whoever asks first is admitted". The tap is the whole
admission gate, so removing the digits does not make the tap optional — it makes
it the only thing there is.

## Consequences

- Pairing is two taps in total, one per Device: tap **Pair** on the peer's card,
  tap **接受 / Accept** on the other one. Nothing is read off one screen to
  compare with another.
- The negative guarantee, stated plainly: a Device on the link that completes the
  open handshake and gets a person to answer yes is in the group. The digits
  never covered that case. What the users give up is detecting a relay between
  the two real Devices by comparing screens.
- The typed-code path is unaffected in kind — a peer that does not know the code
  still cannot complete the handshake at all — and the ~50-bit offline bound on
  a recorded typed-code Pairing still stands, which is why that path stays the
  fallback.
- `test_flutter/ui/pages_test.dart` pins both halves from the screen: allowing
  the request is the whole of the Pairing, and refusing pairs nobody. The shared
  harness `pairThroughWindows` taps the Accept button and waits for both sides to
  report `isPaired` and `isServing`, so the two-window end-to-end test pairs
  through the same single tap a person makes.
- The secret rules are unchanged, including the one this flow depends on: the
  responder reads the peer's admission before deciding which secret to offer.
  They are owned by
  [Pairing by clicking instead of typing a code](2026-09-30-click-to-pair-no-more-typing.md),
  which this note takes over the confirmation step from.

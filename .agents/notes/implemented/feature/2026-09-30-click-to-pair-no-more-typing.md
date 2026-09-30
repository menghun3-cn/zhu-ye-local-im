# Agent Note: Pairing by clicking instead of typing a code

Status: implemented

English | [中文](2026-09-30-click-to-pair-no-more-typing.zh.md)

## Problem

The first real use of the packaged app hit it immediately: the Join dialog asks
for an address, a port and a ten-symbol code, and the code was pasted into the
address field. The error — `that is not a Pairing code: a pairing code is 10
symbols, got 0` — was accurate and useless at the same time. Reading a code off
one screen and keying it into another is exactly the kind of work a person gets
wrong, and the flow asked for three fields before anything could happen.

The typed code exists to put a secret into the Pairing handshake. But the code
path was already documented as the fallback — `PairingSecret`'s own header
calls the 50-bit code a ceiling an attacker can test offline — and the thing
that actually guards admission is the six-digit short authentication string
that both screens show and both users confirm. The app also already discovers
every Device on the link automatically; the discovery list simply offered no
way to pair with what it found.

## Decision

Pairing is now two taps, and the code path is gone from the interface.

* The receiving Device opens an **open Pairing** (`PairingService.inviteOpen`),
  which listens on the well-known pairing port and shows no code.
* The initiating Device taps **Pair** on the discovered peer's card, which
  dials `joinOpen(host: peer.address)` — no port to know, because the peer's
  well-known pairing port is the destination, deliberately not this Device's
  own binding.
* Both screens still show the six digits, and both users still confirm them.
  That step is what keeps admission a human decision, and with a well-known
  handshake secret it is the *only* thing standing between a Pairing and a
  third Device on the link that starts one.

What the well-known secret must never produce is the group secret. On an open
Pairing the responder now decides what to offer *after* reading the peer's
admission: it offers its own group secret if it has one, offers nothing if the
peer brought one (a fresh Device joining an established group), and otherwise
mints a fresh random secret and offers that. Two unrelated fresh pairs
therefore share no key material, where a constant-derived secret would have
put every fresh pair worldwide into one implicit group. The typed-code path
keeps deriving the secret from the code, exactly as before, which is why the
responder-reads-first reordering is gated on `openPairing`.

After the digits are confirmed, the initiating Device opens the Session itself
(`connectAfterPairing`) and retries with a bound. The retry exists because the
first dial can legitimately fail twice: the peer's beacon has not yet
re-announced the port its new Session layer listens on, and the initiator's
own discovery has restarted with an empty registry after the descriptor
changed. Each retry re-resolves the target, so the Session opens as soon as
the next announce lands rather than after a user clicks again.

## Alternatives considered

**Keep the code and auto-fill it from a QR or a shared clipboard.** Rejected:
it keeps the third field and the second screen, and the clipboard of an
unpaired Device is local — there is no channel to carry the code over that
does not already assume the Pairing it is meant to bootstrap.

**Derive the group secret from the well-known constant.** Rejected outright:
it would make the handshake secret and the Session secret the same value, so
every Device that ever completed an open Pairing would hold the same
Session key. The responder-mints rule costs one message ordering change and
keeps the two secrets unrelated.

**Drop the six-digit comparison for the open path.** Rejected: with a public
handshake secret the digits are not a second layer of secrecy — they are the
whole check. Removing them would turn Pairing into "whoever asked first is
admitted".

## Consequences

- Pairing two Devices is now: tap Receive a connection on one, tap Pair on the
  other, compare the digits, confirm. No fields, no retyping, no address.
- A Device on the link can *start* an open Pairing where before it could not
  start a typed one. The confirmation step is the compensating control; the
  typed-code path remains in the core for a future QR or out-of-band flow, and
  is still what the test harnesses use for state setup.
- `pairing_service_test.dart` pins the secret rules: both sides of an open
  Pairing agree on one fresh secret, two separate open Pairings do not share
  one, and a fresh Device joining an established group adopts that group's
  secret.
- The two-window E2E test pairs through the clicks a person would make, and
  the guest opens the Session itself — the send-a-file assertion now runs on a
  Session nobody dialled by hand.

# Agent Note: A Pairing runs on its own link, and admits only after both users confirm

Status: implemented

English | [中文](2026-09-30-pairing-by-typed-code.zh.md)

## Problem

The previous increment left a Device with a persisted Owner identity and a
`LinkManager` that opens Sessions — but a Session is authenticated with the
group secret, and two Devices that have never met share no group secret. Nothing
could turn two strangers into one Owner Group: no way to run a handshake on a
secret the two users already share, no way to prove that the Device on the other
end is the one the user meant, no way to hand a new Device the group's secret,
and no rule for what the group *is* once a third Device joins. Every later
capability — a Transfer to a peer found on the LAN, a Mirror inside the group —
needs that step to exist first.

Two things made it harder than it looks. The typed code is short — ten
Crockford base32 symbols, 50 bits — because a person has to read it off one
screen and type it into another. And a group is not a pair: after the third
Device joins, the first two must still recognise each other.

## Decision

`PairingService` owns the flow, and a Pairing is a first-class kind of link
rather than a Session with different settings.

- **A Pairing listens on its own port** (`defaultPairingPort`, 47656), distinct
  from the Session port and from the discovery port, and its link is torn down
  when the Pairing ends. A Session's responder has to authenticate before it
  knows who is dialling, so it can only ever accept the group secret; a Device
  with no secret has to arrive somewhere else, and "somewhere else" is a
  different socket rather than a second admission rule on the same one.
- **The typed code is the only secret, and it is never sent.** Both sides call
  `PairingSecret.fromCode`, which derives the same bytes from the same ten
  symbols, so the handshake in
  [SecureLink](../../architecture/2026-09-29-core-wire-protocol-and-secure-session.md)
  authenticates without anything crossing the wire. `PairingSecret.random` — the
  QR path — remains the stronger option and is not built yet.
- **`PairAdmitMessage` turns the announced Fingerprint from a claim into a
  fact.** The handshake proves only that the peer knows the code; the descriptor
  in it is whatever the peer chose to announce. So each side signs a context
  built from both Fingerprints in a fixed order plus the short authentication
  string, sends it with its Owner public key, and the receiver requires the key
  to hash to the Fingerprint the peer announced and the signature to verify.
  Without this, a Device that knows the code — a Device already in the group,
  say — could claim any identity it liked.
- **`confirm` is symmetric and both sides must call it.** Each side sends a
  `PairConfirmedMessage` and waits for the peer's; neither writes anything until
  both have. A half-pairing, where one Device believes in a group the other
  knows nothing about, is worse than no Pairing.
- **The group secret is derived for a first Pairing and adopted by a joiner.**
  Two Devices that both have none derive it from the code — the same bytes on
  both sides, nothing sent. A Device joining an established group is handed the
  group's secret inside the sealed link, which is why joining does not cut the
  existing members off. Two Devices that both already have *different* secrets
  cannot be reconciled and are refused.
- **The roster travels with the admission.** `PairAdmitMessage` carries the
  sender's group members, and the receiver admits them along with the sender.
  Without it the third Device in a group would know only the Device it paired
  with, and would refuse a Mirror from the second — because the gate that
  decides who may mirror reads the group.
- **Membership only grows.** A roster is one peer's belief about the group, and
  a stale belief must not be able to undo a removal a user made, so `_commit`
  adds and never removes. A Device that removed a member re-pairs, or removes it
  again where it lands.
- **One invitation at a time per Device**, because two live codes would be two
  live secrets derived from two guesses. Withdrawing an invitation fails its
  `attempt` rather than leaving it pending, so a UI that awaits it cannot hang on
  a peer that will never come; a peer that connects afterwards is dropped.

### What the six digits are worth

Both users see the peer's identity and six digits, and both have to confirm. The
digits are derived from the handshake — so a Device that took part in *this*
exchange knows them, and the two sides agree without sending anything. What they
are **not** is a second layer over the code: a peer that knows the code completes
the handshake and derives the same digits, and a peer that does not know the code
cannot complete the handshake at all. This was recorded as a correction to an
earlier comment in `pairing_secret.dart` that claimed the comparison was the
mitigation for the code's weakness; it is not, and a reader relying on that would
have had a false security boundary in mind.

The step's real value is that admission stays a human decision, with the peer's
identity on screen at the moment of the choice. The bound that actually applies
is the code's ~50 bits: an attacker who records a typed-code Pairing can test
code guesses offline against it, and no amount of comparing digits on the two
screens changes that. That is why the typed code is a fallback for a Device with
no camera and the full-entropy secret is the preferred path.

## Alternatives considered

**Run the Pairing over the normal Session port, with the code-derived secret
standing in for the group secret.** Rejected: one socket would then have two
admission rules, and which one applied would depend on how the caller intended to
use the connection. A Session is also handed out with a hub, a transfer engine
and a clipboard conversation attached; a Pairing wants none of them. Separating
the ports keeps each admission rule on one socket and makes a mis-routed
connection a refusal rather than an escalation.

**Have the inviter generate a fresh, full-entropy group secret and send it
sealed.** Rejected: it is sealed with keys derived from the code either way, so a
recorder who recovers the code recovers the secret too. It would add a message,
a timeout and a failure mode in exchange for nothing — the ceiling is the code,
not the length of the value derived from it.

**Use the Pairing Secret itself as the group secret, with no separate
derivation.** Rejected: the same bytes would key the Pairing link and every later
Session, so a weakness in one is a weakness in the other, and `SecureLink`'s own
domain separation would be doing double duty. `_deriveGroupSecret` keeps a
one-shot link key and a long-lived group key distinct.

**Derive the group secret from something already shared, so joining needs no
message.** Rejected: the only thing two Devices share before a Pairing is nothing
at all. Adding a Device to a group means handing it the group's secret, and the
sealed Pairing link is the one place that can be done safely.

**Let either side confirm and commit on its own.** Rejected: the sequence
"user confirms here, then cancels there" is ordinary — two people are looking at
two screens — and committing on the first confirmation leaves exactly the
half-paired state the two-sided rule exists to prevent.

**Send the inviter's whole Known Device table instead of member
Fingerprints.** Rejected for this increment: the Mirror gate reads group
membership, not the Known Devices table, so the extra aliases and addresses would
be payload nobody reads, and a joining Device gets the peer's descriptor when it
first connects anyway.

## Consequences

- An app layer can pair from `PairingService` alone: `invite` and show the code,
  `join` with a typed code, show both peers the digits, `confirm`. It never holds
  a `Socket` or a `SecureLink`.
- A successful Pairing changes the group secret, which invalidates any
  `LinkManager` or beacon built from the old one. `changes` is how a caller
  notices — the emitted `LocalProfile` and `PairingOutcome.sessionSecret` are the
  same value — and rebuilding from it is the caller's job, not something the
  service can do on its behalf.
- A group converges by growing, so a removal made on one Device can be undone
  when a peer with a stale roster pairs and hands its list back. Until a removal
  flow exists, that is a theoretical cost; when one exists, it will need either a
  roster version or a removal that propagates.
- `KnownDevice.platform` comes from the unsigned handshake descriptor, so a peer
  can misreport the platform it runs on. The alias is the signed one; the
  platform is not, and nothing uses it to decide anything — only to display.
- The typed-code ceiling is ~50 bits against an attacker who records the
  handshake. The QR path, which carries a full-entropy secret, is the preferred
  path and is not built yet; until it is, the typed code is what the product
  offers and its limit is stated in `pairing_secret.dart` rather than discovered.
- `lib/core/` still has no Flutter dependency. The flow is exercised by
  `dart test` over real loopback sockets — a full Pairing, a refused code, a
  refused identity, a third Device joining an existing group, a cancellation, and
  a hostile peer that completes the handshake and then lies about who it is — see
  [the core gate](../testing/2026-09-29-dart-test-as-the-core-gate.md).

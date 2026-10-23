# Agent Note: Discovery connects automatically

Status: implemented

English | [中文](2026-10-23-discovery-connects-automatically.zh.md)

## Problem

The `v0.1.16` interface still required a person to start Pairing and another
person to accept the request. That was not the product requirement: discovering
another running copy of the application is the connection gesture, and the two
Devices must become usable for text, images, files and emoji without anybody
looking for a Pair button or an acceptance dialog.

The reported failure exposed a second defect in the same path. A Device can
announce Discovery before its Pairing listener has bound its port. When the
listener came up, `PeerRegistry` did not treat the newly announced
`pairingPort` as a visible change, so neither the peer list nor the controller
was notified. A PC could therefore display an Android Device by address while
the row said it was not accepting connections, with no action that could repair
the state.

## Decision

Discovery establishes Owner Group trust and opens a Session automatically.
There is no Pair button, Pair code, request dialog, acceptance step, request
switch, or Pair again action. Once another Device is visible, the user can send
text, images, files and emoji as soon as the automatic exchange finishes.

* `PeerRegistry.observe` treats a changed `pairingPort` as a visible change, so
  the controller receives the peer again when its trust listener becomes ready.
* A discovered peer outside the Owner Group starts the existing open Pairing
  exchange automatically. A peer already in the group but temporarily
  advertising no Session listener does the same, which also restores a profile
  that retained its roster but lost its group secret.
* Only the Device with the smaller Fingerprint initiates automatic Pairing.
  Both sides can compute that ordering from facts they already hold, so a fresh
  pair never creates two unrelated group secrets at once.
* The receiving controller admits and confirms every valid discovery request.
  `PairingRequest` and `PairingAttempt` remain the protocol seams; the
  application layer no longer forwards requests to a screen.
* An open Pairing between two established groups resolves a conflicting secret
  by selecting the smaller Fingerprint's secret. Both sides make the same
  choice. The typed-code fallback still rejects conflicting secrets because
  that path retains an out-of-band check and must not silently merge groups.
* Pairing commits are serialized in the controller. Two concurrent discovery
  handshakes therefore union their rosters from the latest profile rather than
  overwriting one another.
* The Device that initiated Pairing dials the first Session. The reconnect
  sweep does not dial that peer while the automatic Pairing is active, and it
  tries the other direction only after the handshake settles. This avoids two
  simultaneous Sessions that each side can discard as the duplicate.
* Failed automatic Pairings and Session dials use bounded backoff and are
  retried by the existing sweep. They do not open a modal interruption.

File reception remains a per-Transfer decision, and clipboard sharing remains
an explicit per-Device choice. Both are separate from membership: automatic
connection makes a Device reachable, not implicitly allowed to write files or
replace the clipboard.

Manual Address remains available only for reaching a Device that already
belongs to the same Owner Group when Discovery cannot place it. It is a
troubleshooting fallback, not another admission flow.

[A stale group membership offers Pair again](2026-10-22-stale-group-membership-repairs-by-pairing-again.md)
is superseded by this decision. The earlier notes that introduced click-to-pair,
the permanent request listener and the one-tap request dialog retain their
protocol rationale but no longer describe the user flow.

## Alternatives considered

**Keep the one-time Pair and Accept flow.** Rejected: it is the reported
product error. A Device visible on the local link is expected to become usable
without a second person performing an action on another screen.

**Let both Devices initiate Pairing when they discover each other.** Rejected:
two fresh Devices would both mint a group secret during simultaneous
handshakes. The Fingerprint ordering gives both sides one initiator without an
extra round trip.

**Have both sides dial the first Session after Pairing.** Rejected: duplicate
Sessions can close each other, leaving each Device holding a different survivor
or no usable Session. The Pairing initiator owns the first dial, and the sweep
handles the direction that is reachable.

**Resolve conflicting group secrets on the typed-code path too.** Rejected:
that path has an out-of-band code and can safely refuse an unexpected merge.
Silently choosing a winner would weaken its meaning.

**Retain Pair again only for a stale roster.** Rejected: the protocol can
restore the missing secret during discovery, and exposing a second admission
surface contradicts the automatic connection rule.

**Leave the Pairing port out of the visible-change comparison.** Rejected:
that is the defect that strands a peer which announced before its listener was
ready. A changed dial target must produce a discovery event.

## Consequences

- Two running Devices on the same local network become one Owner Group and open
  a Session without user admission. Any copy of this application reachable on
  that network can join the group, so the product depends on operating it on a
  trusted local network and on the operating system's network boundary.
- The first connection is more reliable when listeners start in a different
  order from Discovery, and a stale one-sided roster recovers without a manual
  repair action.
- Group membership grows by the existing union rule. The smaller Fingerprint's
  secret becomes the shared secret when two established groups meet.
- The conversation list still shows found Devices and retains Connect only as
  a retry for a known member that is visibly dialable but temporarily
  disconnected; it never offers Pair or Pair again.
- The Devices and Settings surfaces report automatic-connection readiness
  rather than a request-answering preference.
- `test/discovery/peer_registry_test.dart` pins the Pairing-port event.
  `test/app/app_controller_test.dart` covers automatic discovery, simultaneous
  discovery, stale-secret recovery, text and emoji delivery, and Session
  ownership. Widget and two-window tests assert that trust and a Session appear
  with no dialog or Pair control.


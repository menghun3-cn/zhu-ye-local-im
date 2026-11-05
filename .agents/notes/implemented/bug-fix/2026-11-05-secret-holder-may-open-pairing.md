# Agent Note: A secret holder may open Pairing as the larger Fingerprint

Status: implemented

English | [中文](2026-11-05-secret-holder-may-open-pairing.zh.md)

## Problem

Discovery connects automatically, but the automatic Pairing initiator was still
chosen only by Fingerprint order: the smaller Fingerprint always dialled. That
rule is correct for two fresh Devices, yet it strands the case the ordering was
not meant to solve. When an earlier member and a later joiner can see each
other but the joiner's inbound TCP ports are unreachable, the earlier member is
usually the larger Fingerprint. It therefore refuses to dial, while the smaller
joiner keeps dialling into ports that cannot answer. Both Devices remain
discovered and offline from each other.

## Decision

Automatic Pairing keeps the Fingerprint ordering for a fresh pair, and adds one
exception: a Device that already holds a group secret may initiate open Pairing
even when its Fingerprint is larger, but only for a peer outside its roster. A
peer already in the roster keeps the smaller-Fingerprint rule, so the window
after Pairing before the Session port is announced cannot start a second
handshake. The exception is safe because the two
sides already share or deterministically merge the secret; open Pairing does
not mint two unrelated group secrets for established members. The roster
adopted by that Pairing is also what lets the earlier member learn the later
joiner, after which the initiator dials the first Session in the direction that
is actually reachable.

`PairingService` gains a `dialTransport` seam for the same reason
`LinkManager.dialSocket` exists: a test needs to make one direction's Pairing
dial fail without weakening the production dial. `LocalTransferController`
passes it through from its constructor.

## Alternatives considered

**Keep Fingerprint ordering for every automatic Pairing.** Rejected: it is the
defect. The ordering prevents fresh pairs from minting two secrets, but it also
prevents an established member from using the only reachable direction when a
later joiner cannot accept inbound TCP.

**Remove Fingerprint ordering entirely.** Rejected: two fresh Devices could then
start simultaneous open Pairings and mint unrelated group secrets. The ordering
still chooses the only initiator until a Device already holds a secret.

**Keep the rule and require Manual Address.** Rejected: Manual Address reaches a
known Session port, not the Pairing listener, and it asks the user to perform
the diagnosis the automatic sweep should already make.

**Change Session dialling only.** Rejected: the missing fact is group
membership and the shared secret, which only Pairing can restore. Dialling the
Session port first cannot teach the earlier member that the later joiner exists.

## Consequences

- A discovered Device that is not yet in this Device's roster can be adopted by
  an open Pairing started by the larger Fingerprint when that side already has
  a group secret.
- Fresh automatic Pairings still have exactly one initiator, so two unrelated
  Devices cannot create conflicting group secrets at once.
- A peer already in the roster keeps the smaller-Fingerprint rule and the
  Session sweep; the out-of-order Pairing cannot turn the post-Pairing window
  or a reconnect race into a second handshake.
- The receiving side is unchanged: it still admits and confirms valid open
  Pairing requests automatically.
- `test/app/app_controller_test.dart` covers the blocked-inbound case: the
  smaller-Fingerprint Device cannot reach the larger one's Pairing or Session
  ports, while the larger one can reach it, and the Session still comes up.
- The earlier [Discovery connects automatically](2026-10-23-discovery-connects-automatically.md)
  note is updated for the refined initiator rule.

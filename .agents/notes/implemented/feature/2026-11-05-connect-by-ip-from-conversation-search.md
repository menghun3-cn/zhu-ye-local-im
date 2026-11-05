# Agent Note: Connect by IP from the conversation search

Status: implemented

English | [中文](2026-11-05-connect-by-ip-from-conversation-search.zh.md)

## Problem

Broadcast Discovery cannot reach every Device that is still on the same LAN:
a peer may be on a subnet the broadcast does not cross, behind an AP that
filters broadcast, or simply missed by the announce window. The Devices page
already had a Manual Address dialog, but it dialled the Session port directly
and therefore only worked for a Device already inside the Owner Group. The
Conversations surface — where a user actually starts talking — had no way to
name an address at all.

## Decision

The conversation search field carries a fixed `+` action beside the clear
button. It opens a dialog that asks for one IP address and calls
`LocalTransferController.connectByAddress`.

`connectByAddress` treats the typed address as a place to look, not as proof of
identity. It first reuses a Discovery sighting at that address when one exists,
then asks `DiscoveryService.probeHost` to send a unicast probe to the
well-known Discovery port and wait for the matching announce. The answer is a
normal `DiscoveredPeer`: the Fingerprint and ports are claims until the
handshake proves them.

The trust decision is unchanged. A peer already in the Owner Group with an
announced Session port is dialled with `expectedFingerprint` pinned to the
probed Device. A peer outside the group must complete the same open Pairing as
a broadcast-found Device, after which `connectAfterPairing` opens the Session.
A probe that nobody answers, or a Device that announces no Pairing port and no
usable Session port, is refused rather than dialled blindly.

`LocalTransferController` keeps an `addressProbe` seam for tests: production
uses `DiscoveryService.probeHost`, while tests can answer the unicast probe
without modelling every broadcast domain. The Devices-page Manual Address
dialog is untouched; it remains the advanced entry for a known Session port.

## Alternatives considered

**Reuse `connectTo` from the search `+`.** Rejected: `connectTo` dials a Session
port with no prior probe, so it cannot learn the Pairing port of an unpaired
Device and cannot pair first. It stays correct for the Devices page, where the
user is expected to know the port.

**Broadcast another probe and filter by address.** Rejected: the user already
answered "where". A unicast probe reaches the typed address directly, works
across the broadcast boundaries that motivated the feature, and does not make
every Device on the link answer a question only one of them was asked.

**Dial the Pairing port blindly after the probe.** Rejected: the probe already
returned the advertised ports. Trust still comes from the Pairing handshake,
but there is no reason to guess a port the Device just announced.

**Let the typed address admit a Device by itself.** Rejected: the address is
untrusted input. Membership still requires the Owner Group secret, and a
Session still requires the peer to prove it knows that secret; a stranger that
answers the probe but cannot complete Pairing or the Session handshake is
refused.

## Consequences

- A user can start a conversation from the Conversations search field by typing
  an IP, including for a Device that automatic Discovery has not placed.
- The same unicast probe path can pair a Device that is reachable by unicast
  TCP/UDP but invisible to broadcast Discovery.
- Manual IP is not a back door: it performs Discovery, then the same authenticated
  Pairing and Session rules as automatic connection.
- `DiscoveryService.probeHost` sends one probe and waits for the matching
  announce; the announce is recorded like any other sighting, so the peer joins
  the normal peer list.
- `test/discovery/discovery_service_test.dart` covers the unicast probe answer,
  and `test/app/app_controller_test.dart` covers invalid input, an unanswered
  address, a same-group dial, and a pair-then-session over the typed IP.
- `test_flutter/ui/pages_test.dart` covers the `+` action and the invalid-IP
  refusal.

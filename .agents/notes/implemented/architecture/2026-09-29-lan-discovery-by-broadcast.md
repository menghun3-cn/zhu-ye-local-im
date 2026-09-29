# Agent Note: Find peers by UDP broadcast, unauthenticated and subnet-local

Status: implemented

English | [中文](2026-09-29-lan-discovery-by-broadcast.zh.md)

## Problem

Before two Devices can transfer anything they have to find each other, and this
product has no server, no account, no cloud and no user configuration. So
discovery has to work from a cold start on a link nobody has described: no
rendezvous host to ask, no hostname to resolve, and nothing the user is willing
to type.

Three platform facts constrain the mechanism, all recorded in this repository's
platform notes:

- **Android 17 (API 37) blocks local network access by default** and needs the
  `ACCESS_LOCAL_NETWORK` runtime permission. Dart sockets cannot display a
  permission prompt, so any socket use without it fails with a
  `SocketException` (see `docs/android-background-constraints.md`).
- **Receiving multicast on Android needs `WifiManager.MulticastLock`** plus
  `CHANGE_WIFI_MULTICAST_STATE`. That is a platform API, and this project ships
  no plugins — the development machine cannot even build one, because its
  non-admin session cannot create the symlinks Flutter's plugin machinery
  creates.
- `InterfaceAddress.broadcast` gives a directed broadcast address per interface
  with no netmask input (see `docs/dart-networking-capabilities.md`).

There is also a security constraint that shapes the whole design: discovery runs
*before* any trust exists. Whatever it carries, it carries to anyone on the
link.

## Decision

Discovery is UDP broadcast on a fixed port, in `lib/core/discovery/`:

- `beacon.dart` — the datagram format: `{v, k, n, device}` where `v` is
  `beaconVersion` (1), `k` is `probe` or `announce`, `n` is a per-Device random
  Nonce, and `device` is the same `DeviceDescriptor` a handshake carries.
- `peer_registry.dart` — the peer table, keyed by Fingerprint, with a TTL.
- `beacon_transport.dart` — the seam, plus an in-memory hub for tests.
- `udp_beacon_transport.dart` — the real socket, bound to `discoveryPort`
  (47654) with `broadcastEnabled`.
- `discovery_service.dart` — the policy: probe at start, announce every three
  seconds, answer a probe directly, expire peers after ten seconds of silence.

The wire is deliberately **unauthenticated**. Any host can send a beacon and any
host can read one; nothing about a beacon proves anything about its sender. It
is a presence announcement, not an identity.

## What a beacon carries, and what it must never carry

A beacon carries exactly what a stranger could already work out by watching the
link: that some Device exists, what it calls itself, what platform it is, what
it can do with its clipboard, and which TCP port to open a Session to. It
carries **no Pairing Secret, no Owner identity, and nothing derived from either**
— those never leave the Device except inside a handshake that proves knowledge
of the secret. A test asserts the encoded key set and that no secret-shaped
string appears in it, so the boundary is pinned rather than trusted.

The consequence to keep in mind: **presence is not trust.** A peer appearing in
the list means somebody is there, not that they are ours. Every Device in the
list is a stranger until the handshake succeeds and the user has compared the
SAS. The UI must not blur that line.

## Why broadcast, not multicast

Multicast is the textbook answer, and it is the right one *if* discovery has to
cross subnets. This version does not, and multicast costs a platform lock on
Android that this project cannot acquire without shipping a plugin. It would
also mean choosing, documenting and maintaining a group address — a durable
wire commitment — for reachability this version does not need.

A directed broadcast per interface plus a limited broadcast reaches every Device
on the local link with no configuration and no permission beyond the one Android
17 already requires. Both are sent: some access points forward one and not the
other, and the duplicate costs one small datagram.

## The seam

`BeaconTransport` (`received`, `send`, `broadcast`, `close`) mirrors
`ByteTransport`, for the same reason: the policy above is exercised over a real
socket and purely in memory with no code path difference. Two properties of it
are deliberate:

- **A datagram that does not decode is dropped, not propagated as an error.** A
  stranger can send a malformed packet whenever it likes; taking the receive
  loop down over one would turn a nuisance into a denial of discovery, and the
  layer above could do nothing about it anyway. `Beacon.decode` is where
  malformed input is rejected, and it is tested directly.
- **The in-memory transport drops a datagram nobody is listening for** instead
  of buffering it. A Device that has not started is not on the link yet, and
  "did this Device hear that?" has to have one answer, or a test's ordering
  becomes an accident. A real socket would buffer; the difference is in the
  transport, not in the policy, and the policy is what is under test.

## Alternatives considered

**Multicast, mDNS-style.** The conventional LAN discovery mechanism, and what
LocalSend uses for its own discovery. Rejected for this version: it needs
`WifiManager.MulticastLock` on Android, which is unreachable without a plugin,
and its main advantage — crossing subnets when combined with a reflector — is
not this version's problem.

**A DNS-SD/mDNS plugin (`nsd`, `bonsoir`, `multicast_dns`).** Would give service
registration and browsing for free, with platform-native implementations.
Rejected: adding the first plugin with a Windows implementation is blocked on a
known machine limitation (non-admin sessions cannot create the symlinks Flutter
needs), and it would put reachability behind a native library rather than behind
`dart:io`, which contradicts the decision to keep the core pure Dart and
headless-testable.

**Ask the user for an address — type an IP, or scan a QR code carrying one.**
Trivial to implement and needs no discovery protocol at all. Rejected as *the*
mechanism: it makes the common case manual, and it cannot answer "who is here?"
at all. It is not rejected as a fallback — pairing already uses a QR code for
the secret, so a code carrying an address too is a natural later addition for
networks where broadcast is filtered.

**A subnet sweep — TCP-connect to every address in the prefix.** Uses only
`InterfaceAddress.prefixLength`, needs no new protocol, and finds Devices that
block broadcast. Rejected as the only mechanism: a `/24` is 254 connection
attempts per refresh, it is slow, it looks like scanning to any network monitor,
and it needs the same Android permission as everything else.

**Put beacons on the TCP listen port.** One port to open, one to firewall.
Rejected: a Device that is not accepting Sessions still wants to be visible —
a Device whose clipboard can only be applied to should be discoverable — and a
TCP listener plus a UDP listener is the normal split for exactly this reason.

**A cloud or LAN rendezvous service.** Would solve cross-subnet discovery
outright. Rejected: the product's charter is no server, no account, no cloud.
Recording it here because it is the tempting shortcut, and because it is the
alternative that "cross-subnet discovery is a first-class goal" will keep
inviting.

## Consequences

- Discovery answers "who is on this link", and nothing else. Cross-subnet
  discovery — one of the two gaps this product exists to close (see
  [build-from-scratch-not-fork-localsend](2026-09-29-build-from-scratch-not-fork-localsend.md))
  — is **not implemented**. Broadcast does not cross a router boundary, so a
  phone on cellular-adjacent Wi-Fi and a laptop on Ethernet will not see each
  other. This is a named gap, not an oversight.
- The beacon is a wire format and is now versioned (`beaconVersion`). An
  unknown version is rejected rather than half-understood, so a future change to
  discovery cannot silently interoperate with this one.
- Every Device on the link can see every other Device's Alias and platform, and
  can forge any of it. That is inherent to unauthenticated discovery; the
  mitigation is not to make discovery trustworthy but to keep it untrusted, and
  the UI's job is to show a peer as unverified until the SAS comparison says
  otherwise.
- Android needs two pieces of platform work this increment does not do: the
  `ACCESS_LOCAL_NETWORK` permission request before any socket opens, and a
  decision about whether discovery runs only in the foreground. Both are
  Android-layer concerns, and both are prerequisites for discovery working on
  Android at all.
- Broadcast is chatty by nature: one small datagram per Device every three
  seconds, and the peer table is rebuilt from scratch on every process start.
  That is the price of no server.

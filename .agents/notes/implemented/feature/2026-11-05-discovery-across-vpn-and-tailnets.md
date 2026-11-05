# Agent Note: Discovery across VPNs and tailnets by unicast probe

Status: implemented

English | [中文](2026-11-05-discovery-across-vpn-and-tailnets.zh.md)

## Problem

[Discovery by broadcast](../../implemented/architecture/2026-09-29-lan-discovery-by-broadcast.md)
answers "who is on this link" and nothing else: a beacon is a broadcast
datagram, and broadcast stops at the first routing boundary. Two Devices joined
by a VPN or a Tailscale tailnet are on the same private network from the user's
point of view and on different broadcast domains from the protocol's, so they
never saw each other. The named gap recorded in that note — cross-subnet
discovery — is what this change addresses, without a server, an account, or a
cloud rendezvous.

Three things make the problem tractable without new infrastructure:

- A unicast UDP datagram crosses any boundary broadcast cannot, as long as the
  sender knows an address to send it to. `DiscoveryService.probeHost` already
  proved the round trip: probe one address, receive its announce.
- A Device this one has met before already stores the address it was reached
  at — `KnownDevice.lastAddress`, kept "for redial without Discovery".
- tailscaled exposes its peer table on a loopback local API, so the addresses
  of every Device in a tailnet can be read without configuration.

## Decision

Discovery gains a second, unicast probe path alongside broadcast, in
`lib/core/discovery/`:

- `DiscoveryService` accepts an optional `unicastTargets` provider — a
  `Future<List<InternetAddress>> Function()` — and probes each returned
  address every `unicastProbeInterval` (five seconds, deliberately shorter
  than the ten-second peer TTL so a unicast-only peer never expires between
  rounds). Targets are deduplicated and capped at `maxUnicastTargets` per
  round. A provider that throws is ignored; the broadcast path is unaffected.
- `TailscaleDirectory` (`tailscale_directory.dart`) polls
  `GET http://127.0.0.1:41112/localapi/v0/status` at most every thirty seconds
  and returns the `TailscaleIPs` of online `Peer` entries, IPv4 only. The
  request is loopback, credential-free under a default install, and bounded
  to two seconds; every failure mode — no daemon, non-200, malformed body —
  means "no tailnet", and the last good answer is kept across a blip.
- `LocalTransferController` supplies the provider: the union of every
  `KnownDevice.lastAddress` and every address `TailscaleDirectory` reports.
  Everything downstream is unchanged — an announce answered over the tunnel
  is an ordinary `DiscoveredPeer`, and the existing automatic Pairing and
  Session machinery takes it from there.

`PeerRegistry` now keeps **every address a peer was heard at**, each with its
own timestamp, instead of only the most recent one. A Device reachable over
both a LAN and a VPN is heard on each; each sighting ages out independently,
so the peer shrinks back to the addresses that still answer rather than
flapping between them on every announce. `DiscoveredPeer.address` remains —
it is the freshest sighting — and `DiscoveredPeer.addresses` carries the
full set. A change event fires when the *set* of addresses changes, not when
the freshest one does, so a dual-homed peer does not emit every few seconds.

The beacon format is unchanged (`beaconVersion` stays 1): unicast is a
transport-level difference, not a protocol one.

## Alternatives considered

**Subnet sweep — probe every address in each interface's prefix.** Rejected
for the same reason the broadcast note rejected it as the only mechanism, and
it is worse here: a Tailscale address lives in `100.64.0.0/10`, far too large
to sweep, and a sweep of any VPN prefix looks like scanning to every firewall
on the path. Directed broadcast covers the subnet-style VPNs that do emulate
a LAN; point-to-point links have no broadcast address to send to at all.

**Multicast or mDNS.** Rejected again, for the reasons already recorded:
multicast needs a platform lock on Android that this project cannot acquire
without shipping a plugin, and neither multicast nor multicast-broadcast
crosses a Tailscale or point-to-point VPN anyway.

**A cloud or LAN rendezvous service.** Still rejected: the product's charter
is no server, no account, no cloud. This change is deliberately the
rendezvous-free version of the same idea — the tailnet's own directory and
this Device's own memory are the rendezvous.

**Query `tailscale status` as a subprocess.** Rejected: spawning a process
every refresh is heavier and more fragile than one loopback HTTP request, and
the local API is the documented machine interface. The CLI remains a possible
fallback for a platform where the API is absent, but Android's Tailscale app
exposes neither, so it would buy nothing there.

**Persist every address a peer was ever seen at.** Considered and partly
rejected: `KnownDevice.lastAddress` stays single-valued because the profile
is a record of where a Device was last *reached*, and the live multi-address
truth already lives in `PeerRegistry`. Remembering stale addresses forever
would probe dead endpoints indefinitely; the tailnet directory and fresh
sessions keep the target list honest instead.

## Consequences

- Two Devices on one tailnet find each other with no configuration once both
  run this version — including cold starts, because the Tailscale directory
  needs no prior contact. Devices that have met once also rediscover each
  other across any unicast-reachable network, VPN or not, via remembered
  addresses.
- The feature is asymmetric by design: only the side running this version
  probes. An older peer still benefits — its beacon socket answers the
  unicast probe, records the prober's tunnel address from the datagram
  source, and its ordinary announce reply completes the exchange.
- On Android the Tailscale app exposes no local API, so `TailscaleDirectory`
  is empty there; remembered addresses still work, which means Android
  Devices discover tailnet peers only after meeting them once (manual
  address, QR, or a shared LAN).
- A peer heard on two links holds two sightings. Dialing still uses the
  freshest address; when one link dies its sightings expire on the normal
  TTL and the peer converges back to the reachable address without any
  special failover logic.
- Unicast probes are unauthenticated beacons to addresses a directory or
  memory named — the same trust posture as broadcast: presence is not
  trust, and every peer is a stranger until the handshake says otherwise.
- A tailnet with many peers produces at most `maxUnicastTargets` small
  datagrams per five-second round — bounded, and far below anything a
  network monitor would flag.
- `test/discovery/peer_registry_test.dart` covers multi-address sightings
  and per-address expiry;
  `test/discovery/discovery_service_test.dart` covers the unicast cadence,
  deduplication, the per-round cap, provider failure, and the answered
  probe; `test/discovery/tailscale_directory_test.dart` covers status
  parsing, caching, and failure tolerance.

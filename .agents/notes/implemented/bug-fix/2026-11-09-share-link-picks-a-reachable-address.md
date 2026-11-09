# Agent Note: Share links name the address peers can reach

Status: implemented

English | [中文](2026-11-09-share-link-picks-a-reachable-address.zh.md)

## Problem

`LinkTransferServer._getLocalIp` returned the first non-loopback IPv4
address `NetworkInterface.list` happened to enumerate. On a machine with
several interfaces — a router LAN plus a VPN or tailnet, plus the virtual
adapters hypervisors and containers add — that first address is as likely
to belong to an adapter no recipient can reach as to the real LAN one, so
the generated `http://<ip>:<port>/download/<token>` link was dead on
arrival.

## Decision

The choice moved into a pure, testable function,
`chooseShareAddress` in `lib/core/link_transfer/share_address.dart`, with
two inputs: the local candidates (address plus interface name) and the
addresses Devices were recently heard at.

When peer addresses exist, the winner is the local address sharing the
longest prefix with any of them — the peer's own address says which link
the recipient is on, so the router-LAN case and the Tailscale case are the
same rule. A match requires at least a shared first octet; below that the
agreement is coincidence. Ties fall back to the ranking below.

With no useful peer hint — nobody discovered yet, or only stale records —
the ranking prefers what a LAN recipient can plausibly reach: link-local
and loopback are excluded outright, RFC1918 private ranges beat
carrier-grade NAT (the 100.64.0.0/10 range Tailscale assigns from) and
other globals, and interface names that mark virtual adapters —
`vEthernet`, VPN clients, `tun`/`tap`/`ppp`, WSL, Docker, VMware,
VirtualBox, Hyper-V, cellular — lose to physical ones. The final tiebreak
is the address itself, so the pick never depends on enumeration order.

The hints come from `LocalTransferController.discoveredPeers`, a new
getter exposing Discovery's peer list unmerged — `peers` folds in the
Owner Group, Known Devices, and live Sessions, none of which say which
link a recipient is on. Both share-link call sites (`ShareByLinkPage` and
the transfer context menu's `shareByLink`) flatten every sighting,
freshest first, through `shareAddressHints` and pass it to
`LinkTransfer.createLink` as `peerAddresses`.

## Consequences

- A peer heard at `192.168.x.x` gets a link naming the local `192.168.x.x`
  address even when a Tailscale or hypervisor adapter enumerates first;
  a peer heard at a `100.x` tailnet address gets the tailnet one.
- With no peers at all, the link prefers a physical RFC1918 interface over
  VPN, WSL, and other virtual adapters — the common case the bug report
  described.
- A machine whose only address is a VPN one still gets a working link for
  tailnet recipients: the ranking demotes, never excludes.
- The choice is per-link, not per-peer: with peers on two different
  networks simultaneously, the closest prefix wins and the other network's
  recipients get a link that may not reach them. One URL cannot name two
  addresses; the peer's freshest sightings bias the pick toward the link
  in active use.

## Alternatives considered

**Ask the OS which interface routes to a peer (UDP connect trick).**
Rejected: `RawDatagramSocket` has no `connect`, and a TCP probe to the
peer's session port would open a real connection the Session layer would
have to notice and drop. The prefix match answers the same question from
data Discovery already has, with no traffic and no side effects.

**Generate one link per local address.** Rejected for now: it solves the
multi-network ambiguity completely but doubles the UI surface — the share
page lists links, the menu copies one to the clipboard — for a case
(peers simultaneously on two unreachable-to-each-other links) that is
rare. The hints mechanism leaves the door open.

**Keep first-address but skip known-virtual interface names.** Rejected:
name matching alone cannot tell a Tailscale recipient (which *needs* the
`100.x` address) from a LAN one, and it does nothing when every interface
is virtual. It survives only as the fallback ranking's last tiebreak
input.

**Read the default-route interface via platform channels.** Rejected:
the default route points at the internet-facing NIC, which says nothing
about which private network a given recipient is on, and it would need a
new platform channel on two platforms for a weaker answer.

## Testing

`test/link_transfer/share_address_test.dart` covers the pure function:
LAN peer beats VPN and hypervisor candidates, tailnet peer picks the
tailnet address, unusable hints are ignored, the no-peer fallback prefers
physical private interfaces, a VPN-only machine still answers, and ties
are deterministic. The `dart:io` enumeration in `_getLocalIp` is a thin
adapter over it; the HTTP serving paths are unchanged.

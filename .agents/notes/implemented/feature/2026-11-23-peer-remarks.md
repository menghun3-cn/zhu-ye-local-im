# Agent Note: A user-given Remark names a peer on this Device

Status: implemented

English | [中文](2026-11-23-peer-remarks.zh.md)

## Problem

The conversation list titles a row with the peer's address whenever
Discovery has placed it — deliberately, per
`2026-10-08-a-nameless-peer-shows-its-address.md`, because "which machine is
this" is the question the lists are actually asked. But an address is a poor
contact name: it changes when DHCP hands out a new lease, it says nothing
about whose machine it is, and two Devices the user thinks of as "the NAS"
and "mom's phone" are indistinguishable rows of digits.

The peer's announced Alias does not fill the gap either. It is
self-reported, optional, and identical on every Device that sees it — it
answers "what does the wire call it", not "which of my contacts is this".

## Decision

A **Remark** is a name the user gives a peer on their own Device. It is
stored in `DeviceProfile` as a `remarks` map keyed by Fingerprint hex —
local profile data, never announced on the wire, never synced to the Owner
Group, and invisible to the peer it names. Keying by Fingerprint rather
than by address is the point: a Remark survives the peer's IP changing
underneath it.

`PeerView` carries the Remark as a `remark` field assembled in
`LocalTransferController.peers` from the profile, and `displayName` resolves
in the order **Remark → announced Alias → address → Fingerprint**. Because
every surface reads `displayName` — the conversation list and its search
and sort, the pane header, the Devices cards, the forward picker, the
clipboard page, the Transfers lookup — the Remark appears everywhere a peer
is named without any of them changing. `describePeerTitle` is the one
exception that needed an explicit branch: it prefers the address over the
Alias by design, so it now prefers the Remark over the address.

`DeviceProfile.setRemark` sanitises through the same
`DeviceDescriptor.sanitiseAlias` rules an announced name gets, treats blank
as removal, and refuses `self`. `forgetDevice` drops the Remark with the
rest of the peer's records, so deleting a conversation leaves no orphan
name. The profile JSON gains an optional `remarks` object; a profile written
before it existed reads as having none, and an entry keyed by something
that is not a Fingerprint is rejected like every other peer reference in
the file.

Editing lives where the conversation already keeps its other actions: the
row's context menu and the ⋮ menu in the conversation header both offer
"Edit remark", opening a dialog that writes through
`LocalTransferController.setPeerRemark` — a profile write and a repaint,
with no Session touched and nothing sent.

## Alternatives considered

**Overwriting `KnownDevice.alias`.** Rejected: that field records what the
peer *announced*, and `noteDevice` refreshes it on every observation — a
user's Remark stored there would be silently overwritten by the next
announcement. The two are different kinds of fact and now live in different
fields.

**Syncing the Remark through the Owner Group.** Rejected: a Remark is one
person's private label ("mom's phone" is not a name the phone should
broadcast), and the wire format has no field for it. Local-only also means
no protocol change and no version skew to handle.

**Remark only when the peer announced no Alias.** Rejected: the user asked
for the Remark to replace the IP *and* to be the contact name; making it a
fallback would leave two names competing on screen and a rule the user
cannot see. Remark always wins — clearing it restores the old behaviour.

**A separate per-peer store file.** Rejected: the profile already persists
exactly this kind of user state (favorites, clipboard whitelist, incoming
directory) with atomic writes and corruption handling; a second file would
duplicate that machinery for one map.

## Consequences

* Every place a peer is named shows the Remark — including places the user
  did not ask about (bubble sender names, the forward picker). That is the
  requested behaviour, and it is also the honest one: two names for one
  Device on two screens is worse than one name everywhere.
* The announced Alias and address do not disappear — they remain in the
  facts line (`describePeerFacts`) and the Devices card's subtitle, so the
  Remark never hides the facts needed to tell two Remarks apart.
* `avatarLabel` yields to the Remark's first letter: an avatar keyed to the
  address's last octet would be labelling a name that is not on screen.
* A Remark set for a peer that is later deleted is removed by
  `forgetDevice`; a Remark for a peer never met is impossible to create,
  because the editing entries all live on conversation surfaces.
* `hasRealAlias` still reports only what the peer announced — surfaces that
  say "no name was announced" keep telling the truth about the wire.

## Testing

`test/profile/device_profile_test.dart` covers set/clear/sanitise/self/
round-trip/missing-key/bad-key/`forgetDevice`. `test/app/views_test.dart`
pins the `displayName` and `avatarLabel` precedence.
`test/app/app_controller_test.dart` drives a real paired pair and asserts
the Remark appears on the setter's `PeerView` while the peer's own view of
the Device stays untouched. `test_flutter/ui/labels_test.dart` pins
`describePeerTitle` preferring the Remark over address and Alias.

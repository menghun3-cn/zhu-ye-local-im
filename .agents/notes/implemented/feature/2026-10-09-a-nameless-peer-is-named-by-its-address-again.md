# Agent Note: a nameless peer is named by its address again

Status: implemented

## Problem

A Device that answers Discovery without announcing an Alias has no name to show,
and this is the third time the stand-in has been decided.

On 2026-10-08 the fallback became the address
(`2026-10-08-a-nameless-peer-shows-its-address.md`), on the argument that the
address is the one fact about a peer a person can act on and the one that tells
two nameless machines apart at a glance. On 2026-10-09, as a single line inside
a larger commit, it was taken back to the Fingerprint
(`2026-10-09-auto-connect-and-the-clipboard-whitelist.md`). This request puts it
back on the address, and this time it is a decision of its own rather than a
line inside somebody else's — which is the point of writing it down.

The request named a second problem the earlier notes never touched. The
conversation list draws each row with an `Avatar`, and an `Avatar` takes the
*first character* of whatever it is given. A peer named by its address would put
the first character of the address in the circle — a `1` on every machine on the
network, because every address behind one router begins the same way. An avatar
that is identical on every row identifies nothing, which is the one job an
avatar has.

## Decision

**The fallback is the address, and the Fingerprint stays behind it.**
`PeerView.displayName` is `alias ?? address ?? fingerprint.short()`. The
Fingerprint is not dropped, because the address is the one fallback that can be
*absent*: a Device in the Owner Group that has never been heard from has no
observed address at all, and a row still has to be called something. The
ordering is unchanged from `2026-10-08-a-nameless-peer-shows-its-address.md`;
what this note adds is that it is the standing decision rather than a
one-day detour.

**The avatar is a peer's last number, not its name's first letter — but only for
a peer named by its address.** `PeerView.avatarLabel` is null for a Device that
announced a real Alias, so every named peer keeps the avatar it always had (the
first letter of its name). For a nameless peer it is `lastOctetOf(address)`:
`192.168.1.115` puts `115` in the circle. The last octet is the part of an
address two machines on one network differ in — the network prefix is shared by
everyone on it — so it is the shortest part that is still a fact about *this*
machine.

**`lastOctetOf` returns null rather than guessing.** A bare IPv6 address, an
address with a trailing dot, an empty string — none of them has an octet, and
the helper says so instead of slicing one out of whatever is there. The caller
(`Avatar`) falls back to the name's first character, because a whole address
does not fit in a circle and half of one identifies nobody. This is the same
shape as the rest of the naming code: a fact is offered when it exists and
withheld when it does not, never invented.

**The address is not printed twice.** `describePeerFacts` used to print the
address beside the name; with the name now *being* the address, that would read
`192.168.1.115 · 192.168.1.115`. It now skips the address when the name already
equals it, and shows the port instead — the subtitle's job is to add what the
name does not already say.

## Alternatives considered

**Keep the Fingerprint fallback and leave the address out of it.** It was the
shipped behaviour, stable across networks, and it does identify a peer. It lost
again on the same ground as on 2026-10-08: a user looking at two nameless rows
is asking *which machine is which*, and eight characters of hex nobody chose
answers a question nobody asked. The address is the answer to the question the
list is actually asked.

**Standardise on the Fingerprint everywhere, avatar included.** It would give a
stable avatar too. Rejected because a Fingerprint is not memorable at a glance
and the request was explicit that the list and the avatar speak in addresses.

**Draw the whole address in the avatar.** More faithful, and rejected on
arithmetic: `192.168.1.115` is fifteen characters in a circle sized for one or
two. It would either overflow or shrink to unreadable, on every row.

**Draw the first octet instead of the last.** Taken straight from the address in
order, and it is the network, not the machine: every peer behind one router
would show `192`. The last octet is the one that differs between two machines on
one network, which is the only thing the circle is for.

**Compose the avatar from the port, which is also unique per peer.** The port is
about a *listener* and changes between runs; the address is about a machine and
outlives the session. The address is the more stable fact and the one the user
can act on.

## Consequences

A Devices or Conversations list holding several nameless peers is readable again:
each row leads with an address a person can match to a machine, and the
Conversations sort — which sorts on `displayName` — follows.

The display name is not stable the way an Alias is: a peer that moves networks,
or that is reached over a different interface, changes what it is called. This
was accepted in the 2026-10-08 note and is accepted here; the Fingerprint in the
subtitle is what stays put, and a user who wants a stable name can rename the
Device.

Two notes now exist on this one question and they disagree in the middle — the
2026-10-09 commit reverted the 2026-10-08 note without writing anything against
it. This note is the record of the current state; a future change to the fallback
should name *this* note rather than quietly overturning it a fourth time.

A peer whose address has no octet — a bare IPv6 peer — gets the old
first-character avatar, because `lastOctetOf` returns null and `Avatar` falls
back. That is correct for now (the lists are IPv4 in practice) but it is a real
path, not dead code, and it is pinned by a test.

## Testing

`test/app/views_test.dart` pins the name order (Alias wins over a present
address; the address shows with and without a Session port; the Fingerprint only
when both are absent) and, in a group of its own, `avatarLabel`: the last octet
for `192.168.1.115` and `10.0.0.7`, null for a Device with a real Alias, and null
for an IPv6 or empty address. A second group pins `lastOctetOf` itself against
the same cases plus a trailing dot.

`test_flutter/ui/pages_test.dart` asserts the conversation list row is labelled
by the peer's address and that its `Avatar` is drawn with the last octet, so the
two halves of the change — the name and the circle — are both held at the widget
level rather than only in the view model.

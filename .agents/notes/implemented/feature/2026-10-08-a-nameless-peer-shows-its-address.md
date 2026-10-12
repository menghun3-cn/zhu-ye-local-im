# Agent Note: a nameless peer shows its address

Status: implemented

## Problem

A Device that answers Discovery without announcing an Alias reaches the UI as a
blank, and two such Devices are indistinguishable.

The Alias is self-reported. It arrives inside the `hello` a peer sends, and a
peer that sends an empty one — a fresh install before anyone renamed it, a
client that does not implement the field, or a Device deliberately saying
nothing — has nothing to show. Every surface that renders a name had to invent
something, and the two places that needed it invented *different* things:

- `PeerView.displayName` fell back to the Fingerprint's first eight hex
  characters.
- The Pairing prompt fell back to `pairingRequestUnnamed`, the sentence "a
  Device with no name yet".

Neither is wrong, but neither is a name. The Fingerprint fallback is the worse
of the two on a Devices list: it is stable and it does identify the peer, but
it is read off a *claim* made during a handshake, and to a user looking for
"the laptop I am sitting next to" it is eight hex characters that answer a
question nobody asked. Where the list holds two peers that both announced
nothing, the user sees two rows of hex and has no way to tell which one is the
machine on the desk.

Meanwhile the app already holds a better answer and was not using it. A peer
that answered Discovery, or that dialled in, has an address — the address this
side *observed*, not one the peer supplied. That is the one fact on the screen
nobody on the far end got to choose, and it is exactly what a person needs to
work out which machine they are looking at.

## Decision

A peer's display name resolves in order of how much it tells a person:

1. **The Alias**, when the peer announced one. It is what the peer calls itself
   and the only name anyone recognises.
2. **The address**, when there is no Alias. `PeerView.displayName` is
   `alias ?? address ?? fingerprint.short()`.
3. **The Fingerprint's short form**, only when neither exists.

The address is used whether or not the peer accepts Sessions. A peer seen
through Discovery with no Session port has nothing to dial, but "where it is" is
still worth more than a placeholder, so `isDiallable` does not gate the name.

The Pairing prompt follows the same order, using an address read off the socket
the request arrived on. `PairingRequest` gained `callerAddress` for this: it is
filled from `socket.remoteAddress.address` in `_answer`, so it is a transport
observation rather than anything the caller sent. It is nullable, and the
sentence `pairingRequestUnnamed` remains the last resort for a transport that
reports no remote address — a real possibility, not a theoretical one.

This is deliberately **not** a change to a Device's own default name. A Device
that has never been renamed still calls itself "Unnamed device" in its own
profile: at first launch it has no interface bound yet, so it has no address of
its own to offer, and the address that matters is the one the *other* side
observed anyway.

The Alias stays a claim. This change does not make a nameless peer trustworthy;
it makes it *identifiable*. The Fingerprint is still the only part worth
checking out of band, and the Pairing prompt still says so.

## Alternatives considered

**Keep the Fingerprint fallback and change nothing.** It was already shipped and
already distinguishes peers. It lost because it answers the wrong question: a
user looking at two nameless rows wants to know which machine is which, and the
Fingerprint is a claim, not a place. The address is a place.

**Change the Device's own default Alias to its own address.** This is the
change the request's wording suggests, and it is the wrong half. A Device at
first launch has not opened its listeners yet — the address would have to be
enumerated, and on a machine with several interfaces it would have to be chosen,
which is a decision the user never asked the app to make. It would also write a
transient fact into a profile that is meant to be stable, so a Device that moved
networks would keep calling itself by wherever it used to be. The address the
user actually needs is the peer's, and that side already knows it.

**Show both, like `alias (address)`.** More information, and rejected on
surface area: `displayName` feeds list rows, headers, dialog titles and sort
order, and every one of those already renders the address separately —
`describePeerAddress` puts it in the subtitle, and the conversation header keeps
it on screen for the life of the conversation. Composing it into the name would
print it twice wherever it already appears.

**A distinct placeholder per peer, such as "Unnamed device 2".** It tells two
nameless peers apart, which is the actual complaint, but the number is
meaningless: it depends on discovery order, changes between runs, and tells the
user nothing they can act on. The address does the same job and is true.

## Consequences

A Devices list holding several nameless peers is now readable: each row leads
with an address the user can match to a machine, and the sort order in the
Conversations list follows, since it sorts on `displayName`.

The address is not stable in the way an Alias is. A peer that moves networks, or
that is reached over a different interface, changes its display name. This is
accepted: it reflects reality, the Fingerprint in the subtitle is what stays
put, and a user who wants a stable name can rename the Device.

`PairingRequest` gained a member, so any implementation of that interface must
supply it. There is exactly one — `_Caller` — and the interface is internal to
the pairing package, so the cost is a compile error rather than a migration.

The fallback to `pairingRequestUnnamed` is now reachable only when a transport
reports no remote address. A `Socket` always does, so on the paths this app
actually uses the sentence is dead in practice and live as a guard; removing the
string would be the honest move only if the interface stopped being nullable,
and it stays nullable because the address is a property of the transport rather
than of the request.

## Testing

`test/app/views_test.dart` pins the three-level order: the Alias wins over a
present address, the address is shown with and without a Session port, two
nameless peers with different addresses display differently, and the Fingerprint
appears only when both are absent.

`test/pairing/pairing_service_test.dart` pins `callerAddress` against a real
loopback dial in the click-to-pair test, which is what keeps it honest: the
value has to come off the accepted socket, and a fake would not prove that.

# Agent Note: a renamed device kept its old name on connected peers

Status: implemented

## Problem

Renaming a Device did not reach the Devices already connected to it. `peers`
builds each row by merging four sources of knowledge and letting each later
source overwrite what it knows: the Owner Group, the remembered Known Device
records, Discovery, and finally the open Sessions. The last of those supplied
the name from `session.handshake.device.alias` — and a handshake is a
**snapshot**. It is the descriptor the peer announced at the instant the Session
was opened, and it does not change for as long as that Session lives. That is
not an accident of the implementation; `rename` documents it as the reason a
rename costs a Device every open Session.

The consequence was that a peer that held a Session to the Device that renamed
itself kept drawing the old name, and kept drawing it until that Session went
away — which, for a Session that had quietly become half-dead, could be
indefinitely. Rename a laptop and the phone that was already talking to it went
on calling it by the old name.

The symptom showed up as one test that failed sometimes:
`renaming keeps the group and changes what is announced`. It was seen twice and
recorded as environment-sensitive, on the theory that the real loopback TCP
underneath the pairing was flaky. It is not flaky. It is this: whether the
assertion held depended on whether Bob's Session happened to drop before Alice's
next beacon arrived. The red was the truth, and it was dismissed twice.

## Decision

**Rank those four sources by what they know, not by the order they happen to be
applied in.** `_PeerFacts` gains `fromDiscovery`, set when the Discovery loop
places a Device. The Session loop then supplies `alias` and `platform` **only
when Discovery has nothing to say about that Device** — reached by Manual
Address, say, and never seen on the link. Everything else the Session supplies
is untouched: the address it is actually running on, the session port, and that
the peer is connected. A live Session remains the authority on *where* the peer
is; it is simply not the authority on *what the peer is called*.

The rule that makes this right is freshness, and it is not close. A beacon is
re-announced every three seconds and carries the peer's current name. A
handshake is captured once, and the older of the two can be as old as the
Device's uptime. Where both exist, the beacon is the answer.

**Fixing the loop order instead would have been wrong, and this is the part
worth remembering.** Moving the whole Session loop ahead of the Discovery loop
also puts the Session's `address` last, which is a rule that was put there
deliberately and documented in place: Discovery may have restarted, and a Known
Device record may never have been written, but a live Session is where the peer
demonstrably is. The precedence has to differ *per field*, which is what the
flag records.

## Alternatives considered

**`??=` on the handshake's alias, so it only fills a gap.** Simpler — no new
field — but it ranks the wrong pair. The field it would fill is already
populated by the remembered Known Device record, which is written at pairing
time and can be months old, so this would trade a minutes-old handshake name for
a months-old remembered one. The remembered record is exactly the value
Discovery overwrites whenever the peer is on the link, and this would have
handed the name back to it in the case Discovery never sees the peer at all.

**Stop reading the name out of the handshake entirely.** Then a peer dialled by
Manual Address — which by definition Discovery never placed — would have no name
to show and would fall back to its fingerprint, even though the handshake
carried its name. That is a regression against a case that works today, to fix a
case that does not.

**Re-handshake, or refresh the Session's descriptor, when a Device renames.**
There is no event to hook: the handshake happens once, when the Session is
established. Inventing a way to redo it reopens an authenticated exchange for a
cosmetic change.

**Announce the rename on the wire as its own message.** A new beacon kind or a
control message, to communicate something Discovery already broadcasts every
three seconds. A protocol change to fix a display, and a second source of truth
for a name that already *has* one.

**Move the Session loop ahead of the Discovery loop.** Fixes the name, breaks
the address. Called out above because it is the plausible-looking version of
this change.

**Relax the test — accept either name, or wait longer.** The shape that produced
two rounds of "environment-sensitive". The assertion was correct all along;
loosening it would have made a real bug permanent and invisible.

## Consequences

**A rename now travels within one announce period rather than at the next
reconnect.** The peer's beacon carries the new name, and nothing outranks it any
more, so the other side picks it up in at most three seconds. Before, a connected
peer could show the old name for as long as its Session survived.

**A Device reached only by Manual Address still shows what its handshake said.**
Unchanged behaviour, and the right one: that is the only name anyone has for it.

**For the first moments after a Session opens, the handshake still supplies the
name**, until the first beacon lands. Same as before this change, and the two
agree in practice — the handshake is the same descriptor the peer is currently
announcing, unless it renamed in between.

**Nothing in the transfer or Session layers moves.** This is a precedence rule
inside one getter, in the layer that already owned the question of what to draw.

## Testing

`test/app/app_controller_test.dart`'s "renaming keeps the group and changes what
is announced" is the regression test, and it needed no change to its assertions
— only to its reputation. It was proved pre-existing rather than caused by the
work in flight by exporting a pristine `HEAD` with `git archive` into a
throwaway directory and running the same test there, where it failed
identically; that method touches no working tree and involves no branch switch.

The test now carries a comment naming the mechanism, because the way it fails is
the way it was twice explained away: the assertion goes green or red depending on
whether Bob's Session dropped before Alice's next beacon, so a reading of
"sometimes red" sounds like timing noise. It is not — the red case is the one
where the stale handshake outranks the live beacon, which is exactly the bug.
After the fix the assertion holds whenever the beacon arrives, whichever way the
Session goes.

Also checked by hand, with a throwaway instrumented copy of the same test, that
the two cases really do differ rather than merely both passing: with the fix in
place Bob's list corrects itself while the stale Session is still there, and
without it the list keeps the old name for as long as the Session lasts.

# Agent Note: A Session that ends comes back on its own

Status: implemented

English | [中文](2026-10-20-a-session-that-ends-comes-back.zh.md)

## Problem

Two paired Devices stayed connected until the network went away, and then never
came back on their own. The report was that the app "stays open, but after the
network drops and comes back, the two clients do not reconnect" — no tap, no
restart, nothing.

There were three separate reasons for that, and each one had to be fixed
before the pair came back:

1. The automatic connect was hung off a discovery *change*. `PeerRegistry`
   emits only on something a user could see — a peer appearing, moving
   address, changing name, or expiring. A peer that comes back at the same
   address after a short outage changes nothing, so discovery says nothing at
   all and there is no event for a re-dial to hang off.
2. A Session that ended was only *removed*. `SessionLost` dropped the wired
   session and nothing else; it never turned into a dial, so the peer was
   never looked for again.
3. A black-holed connection never ends at all. When the router reboots or the
   Wi-Fi reassociates onto a network with no route to the peer, the TCP
   socket stays open, the operating system keeps accepting the bytes that go
   nowhere, and the Device goes on showing its peer as connected. Nothing in
   the Session layer notices, because from the socket's point of view nothing
   happened.

The third one is the reason a re-dial alone is not enough: the outage has to
be *noticed* first, and a socket that never errors is a socket that never
reports anything.

## Decision

Fix it in two layers, because the two layers answer two different questions.

**The Session layer learns whether the peer is still there.** A new
`KeepAlive` sends a `PingMessage` every five seconds and waits for the
`PongMessage` in reply. A peer that has vanished never answers, and after
fifteen seconds of silence the Session is closed rather than left open and
looking connected — which is what puts the loss on the wire where the layer
above can see it.

**The app layer keeps the open Sessions in line with the paired peers.** The
automatic connect now runs on a two-second sweep over the Owner Group's
members rather than over Discovery's list. The Group is the record of who
belongs here; Discovery's list is the record of who is reachable *right now*,
and the peer that has dropped off the link is exactly the one that has to be
dialled. A peer that fails to answer is retried with a growing pause — one
sweep, two, four, up to fifteen sweeps, which is half a minute — so a Device
that is switched off costs almost nothing while a Device whose network came
back is picked up promptly. The pause is counted in *sweeps* rather than
measured against a wall clock, so the pause and the thing that runs it are
judged by the same clock. A Session that ends is also re-dialled straight
away, because the common case is a peer that restarted or a network that
blinked, and waiting a couple of seconds for the sweep is a visible delay in
a conversation that should never have ended.

The sweep is what covers the case discovery cannot: an outage that ends the
Session also means the first re-dial fails, and the network coming back
announces nothing — the peer is at the same address it was at before, and
discovery has nothing new to report. Something has to keep trying, and the
sweep is that something.

The probe is a *capability*, not a version bump: the handshake carries a
`ka` flag saying "this Device speaks the probe", and a peer that did not set
it is never probed. A Device on an older build is therefore never sent a
message it would misread, and is not excluded from the Session for that
reason either — it simply goes unprobed, and its disappearance is noticed the
way it was before, when the socket finally errors out. That is why the flag
is only ever read and never required.

The deadline for "the peer has stopped answering" is a timer of its own
rather than a comparison against a wall clock, because the probe and the
deadline then run on the same clock: a widget test drives its own clock as
fast as it likes, and a deadline judged by a different clock would give up on
a Session that had every chance to answer. The deadline is measured from the
last *answer*, not from the last probe — re-arming it on every probe would
push it forward for as long as the peer kept ignoring the probes, and a peer
that never answers would never be given up on.

## Consequences

- Two paired Devices reconnect by themselves after an outage, with no tap and
  no restart on either side.
- A Device that has silently lost its peer stops showing it as connected; the
  Session is closed and the pair comes back on the next sweep.
- A peer that is switched off is dialled once every two seconds at first and
  then once every thirty seconds, rather than once every two seconds for
  ever.
- The probe is only sent to a peer that announced it. A Device on a build
  without it keeps working exactly as before.
- Three tests in `test/app/app_controller_test.dart` guard the app layer: a
  Session that ends coming back with nobody tapping anything, on a link that
  discovery says nothing about; a peer that goes *silent* — a connection
  that stays open and swallows everything written to it, so nothing reports
  the loss — losing the Session and coming back; and a pair that only comes
  back once the network does, which is the case where the first re-dial fails
  and only the sweep can rescue the pair.
- Two tests in `test/session/keep_alive_test.dart` guard the Session layer: a
  peer that stops answering losing the Session instead of keeping a
  connection that no longer works, and a peer that probes *us* being answered
  even when this side never probes in return.

The black-hole case needs a seam to be written at all: a closed socket
reports itself, so it cannot stand in for a connection that has lost its
route. The `LinkManager` therefore takes a wrapper for the socket a
connection runs on, and a test replaces it with one that swallows what is
written to it.

## Alternatives considered

**Rely on discovery events alone** — a peer that comes back at the same
address announces nothing new, so this cannot cover the reported case at all.
It is kept as one of the two triggers, because a peer that moved *is* worth
dialling at once.

**Rely on the socket erroring** — it does not, on a black-holed connection.
The socket stays open and the peer stays "connected" for ever, which is the
other half of the report.

**Use TCP keep-alive** — `dart:io` exposes no `SocketOption` for it, so the
setting would have to be made outside Dart, per platform, in a way this
project does not otherwise reach for. An application-level probe is a few
lines and travels inside the Session that already exists.

**Bump the protocol version instead of adding a capability flag** — a version
bump says "the two sides must match", which would exclude every Device on an
older build from the Session. The two ends of a probe do not have to be the
same build: the only thing that matters is that each side knows whether the
other understands the message.

**Judge the deadline with `DateTime.now()` or a `Stopwatch`** — both are
judged by a clock that is not the one the probe runs on, and a test that
drives its own clock would then see a Session given up on that had every
chance to answer. A `Stopwatch` was tried and rejected for that reason.

**Re-arm the deadline on every probe** — the deadline would then be measured
from the last probe rather than from the last answer, and a peer that never
answers would never be given up on. The deadline is armed once and cleared
by an answer.

**Retry the dial with a fixed short pause** — a Device that is switched off
would then cost a dial every two seconds for as long as it stays off, which
is the same cost as the sweep itself and rather more.

**Measure the retry pause against a wall clock** — the pause and the sweep
that runs it would then be judged by two different clocks, and the two could
disagree about when a peer is due. The pause is counted in sweeps, so the
two are the same thing.

**Answer a probe only when this side is probing too** — a peer that probes us
has said it speaks the probe, and leaving it unanswered would cost it its
Session for no reason. The answer goes out whether or not this side probes.

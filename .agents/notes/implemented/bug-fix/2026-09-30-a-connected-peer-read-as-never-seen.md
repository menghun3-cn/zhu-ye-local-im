# Agent Note: A connected peer read as never seen

Status: implemented

English | [中文](2026-09-30-a-connected-peer-read-as-never-seen.zh.md)

## Problem

A Device with an open Session read, under its name:

```
从未出现 · 最后出现于 3 小时前
```

The same fact said twice, and the second time as a contradiction with the first.
`neverSeen` came from `describePeerAddress`, `lastSeen(…)` from
`describePeerFacts`, and neither knew what the other had already said. The
symptom had three causes, which is why it needed three fixes and not one:

* The peer list merged a Session into the peer with
  `..address ??= session.address?.address`. On a peer Discovery had already
  placed — the usual case, since pairing runs over Discovery — the left side was
  already non-null, so the Session's address was never taken. The card could then
  show an address the Session was not running on.
* `describePeerFacts` appended the last-seen clause whenever the peer had an
  address, whether or not it was connected.
* `describePeerAddress` returned `peerNotAccepting(address)` whenever
  `sessionPort` was null — so a Device with a live Session and no port in its
  beacon was described as "not accepting sessions", which is a strange thing to
  say about a Device this one is demonstrably talking to.

## Decision

A Session is a sighting, and the address it is running on is the best address
this Device has.

* The wired branch of the peer list prefers the Session and falls back to what
  was already known: `..address = session.address?.address ?? entry.address`,
  `..sessionPort = session.handshake.device.listenPort ?? entry.sessionPort`, and
  `..lastSeen = _clock().toUtc()` — a live Session means the peer is here now, so
  the record is stamped rather than left at whatever Discovery last reported.
* `describePeerFacts` adds the last-seen clause only for a peer that has an
  address and is **not** connected. A connected peer reads as its address plus
  `sessionOpen`, and says nothing about time.
* `describePeerAddress` returns the bare address when there is no Session port
  and the peer is connected: the Session is the proof that it accepts this one,
  whatever its beacon advertised.

## Alternatives considered

**Keep `??=` and fix the sentence instead.** Rejected: the address would still be
whatever Discovery last said. A Session opened over a different interface than
the one Discovery reported would be labelled with an address it is not on, which
is worse than a missing label — it is a wrong one.

**Print the last-seen time as well, since it is true.** Rejected: for a connected
peer it says the same thing as "connected", and printing it beside that reads as
a second, competing statement. The list's job is "where can I reach this Device";
time belongs to the Devices that cannot be reached.

**Show only "connected" while connected, with no address.** Rejected: the address
is exactly what a user needs when a Session drops and they want to know which
machine it was.

**Make the card trust `lastSeen` rather than the Session, on the grounds that a
Session can go stale.** Rejected: `isConnected` is read from the live Session
registry on every build — it is the freshest fact on the card — while `lastSeen`
is the one written down.

## Consequences

- A connected Device's card reads `10.0.0.7:47655 · 已连接`, and keeps reading
  that for as long as the Session is up. That address is also what the
  conversation's AppBar shows, from the same `PeerView` and the same function.
- `test_flutter/ui/labels_test.dart` pins the three readings as values, which is
  cheaper and more precise than building three screens for them: a peer that has
  never been placed is described once rather than twice, a connected peer keeps
  its address even with no advertised Session port, and a connected peer never
  reports a last-seen time.
- `test_flutter/ui/pages_test.dart` asserts the same thing from the card: with a
  Session open the card offers the conversation, prints the address, and does not
  print `neverSeen`.

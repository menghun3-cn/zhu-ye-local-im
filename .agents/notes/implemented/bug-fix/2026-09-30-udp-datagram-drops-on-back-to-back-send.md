# Agent Note: The UDP transport re-sends a datagram the socket refused

Status: implemented

English | [中文](2026-09-30-udp-datagram-drops-on-back-to-back-send.zh.md)

## Problem

[`UdpBeaconTransport`](../../../../lib/core/discovery/udp_beacon_transport.dart)
handed every datagram straight to `RawDatagramSocket.send` and ignored what came
back. That return value is the only signal a UDP sender gets: `send` returns the
number of bytes it took, and **0 when the socket still has a write in flight**.
A datagram socket accepts one datagram at a time, so a second `send` inside that
window does not queue and does not fail loudly — it returns 0 and the datagram
is gone. There is no error, and no completion callback to await.

Two paths in this layer send back to back, and both are ordinary rather than
exotic:

- `broadcast` performs one `send` per target. `defaultBroadcastTargets` returns
  the limited broadcast address *plus* every subnet's directed broadcast
  address, which is two or more on any host with a real interface — and the
  duplication is deliberate, because some access points forward one and not the
  other. The dropped datagram is every target after the first.
- `DiscoveryService` answers a probe, and two probes can arrive in the same tick
  as the announce timer fires.

The failure is invisible from the outside. The beacon never leaves, so the peer
is simply not discovered: nothing logs, nothing throws, and a Device that is
present stays missing from the list until its next announce happens to land in
an empty window.

It therefore presented the way this class of defect always does — as an
intermittent test.
[`udp_beacon_transport_test.dart`](../../../../test/discovery/udp_beacon_transport_test.dart)'s
"a malformed datagram is dropped and the receive loop survives" failed once
inside a full-suite run and passed on every isolated re-run. Probes against a
bare socket named the culprit: a round that sends three datagrams and prints
what `send` returned got `[1, 0, 0]`, and a loop doing nothing but `send`
delivered only the first datagram in a majority of rounds.

The first hypothesis was the wrong end of the wire. Draining the *receive* side
(`while ((datagram = receive()) != null)`) is the usual cure for a lost
datagram, and it changed nothing — a control probe still lost 59 of 900. The
datagrams were never arriving.

## Decision

**The transport queues outgoing datagrams and re-sends one the socket refused.**
`send` and `broadcast` enqueue into an outbox; a single drain loop offers the
oldest datagram, removes it once `send` reports the full length, and otherwise
waits one millisecond and offers that same datagram again. Sending is serialised
without a caller-visible change: the interface stays synchronous, the queue
preserves order, and every datagram eventually leaves.

The datagram is copied on the way in, so a caller may keep reusing its buffer —
`DiscoveryService` re-sends one `_announceBytes` to every target and to every
prober.

`close` drops whatever is still queued. A socket that throws on send clears the
queue and stops draining, because by then `send` has already returned and there
is no caller left to tell.

## Testing

Two cases in `udp_beacon_transport_test.dart` pin this, and both fail without
the fix:

- "every datagram in a burst is delivered" pre-encodes 32 beacons and then does
  nothing but `send`. Encoding between the sends hides the window — building one
  beacon takes long enough for the previous write to complete — so the loop has
  to be bare for the defect to show. That is also why this needed a new case
  rather than a tighter assertion on the existing ones.
- "a broadcast sends to every target, not only the first" broadcasts ten times
  to two targets that resolve to the same address, because two sockets cannot
  share one UDP port; what is under test is that one `send` happens per target.

The window is a few hundred microseconds wide, so a single round can slip
through; both cases therefore repeat until it is certain to be hit. Measured
across repeated runs of the whole file: 4 of 4 runs failed before the fix, 5 of
5 passed after it.

## Alternatives considered

**Drain the receive side with a `while ((datagram = receive()) != null)` loop.**
Rejected on measurement: a probe that drained every datagram available on each
event still lost 59 of 900, no better than the 51 of 900 lost without draining.
The loss is on the send side, where the return value is the only evidence, and
`receive` cannot report on it. This is recorded because it is the first thing
anyone will reach for.

**Wait for `RawSocketEvent.write` and send one datagram per event.** Rejected:
the event is one-shot. Measured over five rounds it fires exactly once, 0–7 ms
after bind, and never again however many datagrams complete afterwards — so an
event-driven drain stalls after the first datagram.

**Retry on the spot, without a queue.** Rejected: `send` is synchronous and
cannot await, and spinning until the socket is free would block the event loop
that completes the write. That is a livelock rather than a retry.

**Make `send` and `broadcast` asynchronous and let callers await delivery.**
Rejected: `DiscoveryService.announce` and `probe` are driven by timers and by
arriving datagrams, and neither has anything to do with the result, so the
interface would grow a `Future` whose only consumer discards it. The queue keeps
the delivery guarantee next to the refusal that causes it and leaves the
contract `void`.

**Back off with `Future.delayed(Duration.zero)`.** Rejected on measurement: at
zero delay the retry still loses 2 of 200 rounds, because the write completes in
tens of microseconds and a zero-duration timer does not reliably wait even that
long. One millisecond lost 0 of 200, with at most two retries.

## Consequences

- Beacons that were dropped are delivered. Discovery no longer depends on the
  second broadcast target happening to win a race, which is what the redundancy
  in `defaultBroadcastTargets` was for.
- The transport holds a small queue and a one-millisecond timer while the socket
  is busy. Nothing waits when the socket is free, which is the common case, and
  a datagram pays at most the tens of microseconds its predecessor needs.
- [`BeaconTransport`](../../../../lib/core/discovery/beacon_transport.dart)'s
  `send` and `broadcast` now state the contract that was implicit and unchecked:
  delivery is asynchronous and expected to happen, and "broadcast" means every
  target rather than the one that went first. That missing contract is how the
  defect got in — the interface promised nothing, so nothing was verified.
- Ordering was neither promised before nor is it promised now, but the queue
  makes it hold in practice for datagrams sent through one transport.
- The full suite is trustworthy again as a gate: the intermittent failure that
  surfaced this stopped being intermittent, which is what "flaky" always means —
  the code was wrong on every run and only sometimes observably so.

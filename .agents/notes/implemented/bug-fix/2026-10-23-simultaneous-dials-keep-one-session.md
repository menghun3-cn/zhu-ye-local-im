# Agent Note: Simultaneous automatic dials keep one Session

Status: implemented

English | [中文](2026-10-23-simultaneous-dials-keep-one-session.zh.md)

## Problem

Every paired Device sweeps its Owner Group every two seconds and dials each
member that has no open Session. Two Devices can run that sweep at the same
time and dial each other. Both TCP handshakes can succeed, and each
`LinkManager` then refuses the second Session after it already holds one. The
two ends can complete those handshakes in opposite orders: one keeps the
connection it initiated, while the other keeps the connection it initiated.
Each end has then closed the connection the other end kept. Both local maps
may briefly report a Session, but neither connection remains usable.

The controller retries the same reciprocal dial on the next sweep, so the
pair can repeat this failure indefinitely. On screen the Device moves from
"Connecting automatically" to offline without a transport error.

## Decision

The Session direction is deterministic. The Device with the smaller
Fingerprint initiates the preferred Session; the Device with the larger
Fingerprint is the preferred responder. Both ends derive the same choice from
the identities already exchanged by the handshake.

The first Session is still accepted regardless of direction. This preserves
the case where only one direction has a usable network route. If a preferred
Session arrives while the manager holds a non-preferred one, the preferred
one replaces it. A second Session is refused when it has the same direction
as the stored Session, or when the stored Session is already preferred.

`LocalTransferController` adopts the replacement instead of ignoring a second
`SessionEstablished` event for the same peer. It disposes the transfer
wiring for the old Session and attaches the new Session; attaching the
clipboard channel for the same peer also replaces its old channel.

This is a local duplicate-resolution rule, not a wire-protocol change.

## Testing

`test/session/link_manager_test.dart` dials both directions concurrently. It
checks that both Devices retain the Fingerprint-preferred roles, still hold
open Sessions after the losing connection is closed, and do not replace them
again during the settling window.

`test/app/app_controller_test.dart` repeats the concurrent dial through the
controller, then sends a text Transfer over the surviving Session. That test
covers both the Session choice and the controller replacing its old wiring.

## Alternatives considered

**Delay one side by a fixed interval or random jitter** — it makes the race
less frequent without making the outcome deterministic. A slow handshake can
still cross the delay, and the resulting failure remains difficult to
reproduce.

**Let only the smaller Fingerprint dial** — it removes reciprocal dials, but
breaks a pair whose network route works only from the larger Device to the
smaller one.

**Close both Sessions and retry** — it guarantees a visible disconnect and
allows the same crossed-dial race to repeat on the next sweep.

**Keep whichever Session completed first at each end** — this is the defect.
The two ends are not required to choose the same connection.

## Consequences

- Reciprocal automatic dials converge on one connection instead of leaving
  both ends with closed Sessions.
- A non-preferred Session can exist briefly while a preferred direction is
  unavailable, so asymmetric reachability still has a path.
- A dial race costs one extra TCP handshake, but the unused connection is
  closed and the transfer and clipboard layers move to the surviving one.
- The rule is deterministic and testable without timing-dependent sleeps in
  the connection logic.

## Related

- [Automatic connection and the clipboard whitelist](../feature/2026-10-09-auto-connect-and-the-clipboard-whitelist.md)

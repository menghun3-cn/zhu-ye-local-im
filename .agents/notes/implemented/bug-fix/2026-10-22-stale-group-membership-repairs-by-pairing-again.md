# Agent Note: A stale group membership offers Pair again

Status: implemented

English | [中文](2026-10-22-stale-group-membership-repairs-by-pairing-again.zh.md)

## Problem

Owner Group membership and the group secret are persisted together, but a peer
can still be left with only one side of a Pairing. For example, one Device may
remember the other as a group member while the other has lost its group secret.
The latter consequently tears down its Session listener and announces no
Session port. The former still sees `isInGroup == true`, so it cannot offer the
ordinary Pair action. Because it also has no dialable port, it cannot offer
Connect. The conversation row was therefore a dead end: automatic reconnection
kept failing and the user had no visible way to repair the relationship.

## Decision

The conversation row now distinguishes three actions: Connect, Pair, and Pair
again. A peer that is in this Device's group, has a known address, and announces
no Session port is offered Pair again. The row reuses the existing click-to-pair
dialog, so the governed Pairing exchange remains the only way the missing secret
is restored; no membership or secret is edited locally.

Connect still requires both group membership and a dialable Session port. Pair
still applies only to a discovered peer outside the group. A peer already in the
group but without either an address or a port remains non-actionable, because
nothing in the UI knows where to send a Pairing request.

## Testing

The widget regression pairs two Devices, removes one Device's stored
`session.groupSecret`, restarts both over their same profiles, and opens the
other Device's conversation list. Restarting both keeps the assertion about
the stale membership independent of how long an old Session takes to time out.
It asserts that the Device without a secret is still listed as a group member
with no Session port and that its row offers Pair again, not Connect or Pair.

## Alternatives considered

**Remove the stale member automatically when no Session port is announced.**
Rejected: a missing port is also a transient state while a paired Device is
starting, and a peer that is not currently accepting Pairings does not announce
one either. Automatically deleting membership would turn a temporary
observation into permanent trust loss.

**Pair automatically without the other user's confirmation.** Rejected:
Pairing is the authentication boundary for the whole Owner Group. Silently
starting it would let a Device that merely appears on the LAN trigger the
exchange, and it would remove the one decision that validates the other side.

**Show Connect anyway and let the handshake fail.** Rejected: the peer
advertises no Session listener, so the action is known to fail before it is
pressed. Reporting the failure does not recover the missing secret.

**Leave the row without an action.** Rejected: this is the reported defect.
The user can see both Devices, and the state is recoverable through an existing
protocol flow, so hiding the recovery action strands them.

## Consequences

- A one-sided or stale membership has a visible route back through the normal
  Pairing confirmation.
- Transient startup states are not converted into destructive profile changes.
- A group member with neither an address nor a Session port remains inert until
  Discovery places it; the UI still does not guess an address.
- The three row actions now have one explicit decision point rather than two
  overlapping booleans, so future states cannot silently produce no button.

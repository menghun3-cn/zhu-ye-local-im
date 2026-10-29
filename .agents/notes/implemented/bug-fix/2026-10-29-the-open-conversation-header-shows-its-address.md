# Agent Note: The open conversation header shows its address

Status: implemented

English | [中文](2026-10-29-the-open-conversation-header-shows-its-address.zh.md)

## Problem

A conversation row leads with the peer's address, but opening that row replaced
the address with the peer's self-reported alias. Two Devices can announce the
same host name, so the header stopped answering the question the row had just
answered: which machine is this conversation with? The endpoint below the title
still contained the address, but the primary line invited the user to identify
the peer by the fact that can collide.

## Decision

The open conversation header uses the same title rule as its list row:
`PeerView.address` when Discovery has placed the peer, and `displayName` only
when there is no address to show. `describePeerTitle` owns that rule, and both
the pane header and the pushed `ConversationPage` use it.

The supporting line no longer repeats the address. `describePeerConnection`
shows the listening port, then adds whether the peer is reconnecting or offline
when no Session is open. A peer with no address still says that it has never
been seen. This keeps the two lines distinct: the title identifies the machine,
and the line beneath it describes the current connection.

This extends the rule recorded in
[A conversation row leads with its address](2026-10-23-a-conversation-row-leads-with-its-address.md)
from the list to every conversation header.

## Testing

`test_flutter/ui/labels_test.dart` pins the address-first title, the name
fallback, and the non-repeating connection line. The conversation widget test
asserts that opening Bob's conversation shows Bob's address instead of his
alias in the header and shows the port below it.

## Alternatives considered

**Keep the alias as the title and the endpoint as the subtitle.** Rejected: the
alias is the fact that can be duplicated across machines, so the largest text
would remain the weaker identifier.

**Put `address:port` in the title.** Rejected: the title would mix machine
identity with transport detail, and a long endpoint leaves less room for the
same address the user needs to read.

**Change only the pane header and leave the pushed page alone.** Rejected: the
same conversation would identify its peer differently depending on how it was
opened.

## Consequences

- Every open conversation leads with the peer's network address when one is
  known.
- The alias remains available on Devices and in conversation controls, but it
  is no longer the primary identifier at the top of a conversation.
- The connection line keeps the port and reachability state without printing
  the title address twice.

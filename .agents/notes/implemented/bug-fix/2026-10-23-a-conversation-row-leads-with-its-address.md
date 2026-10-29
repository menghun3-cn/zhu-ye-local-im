# Agent Note: A conversation row leads with its address

Status: implemented

English | [中文](2026-10-23-a-conversation-row-leads-with-its-address.zh.md)

## Problem

The conversation list titled each row with the peer's host name. Two Devices
can announce the same host name, and a host name does not tell a user which
machine on the local network they are about to message. The address was already
available and already appeared elsewhere in the conversation chrome, but the
list made the less useful fact the primary line.

The same list also stopped one interaction short. Picking a conversation opened
its composer beside the list, but left the caret wherever it had been. The
user's next act after choosing a conversation is normally to type, so requiring
a second click on the input box made the list selection feel incomplete.

## Decision

The primary line of a conversation row is `PeerView.address`. A peer that
Discovery has not placed has no address, so `displayName` remains the fallback
instead of leaving the row blank. The row's test finder key remains the display
name; that key identifies the row in the harness and is not a second visible
title.

The open conversation header follows the same address-first rule; see
[The open conversation header shows its address](2026-10-29-the-open-conversation-header-shows-its-address.md).

The list search accepts both the displayed address and the display name, so
changing the title does not make an alias stop being searchable.

Picking a row sets the page's existing composer-focus request in the same state
change that selects the peer. `ConversationView` forwards that edge to
`ConversationComposer`, which asks its own `FocusNode` for focus after the
frame. Reusing that path keeps focus tied to the composer instance that was
actually mounted, including when the selection changes the view's peer key.

## Testing

The conversation-list widget tests assert that a named peer's row contains its
address and not its alias as the title. The row-selection test waits for the
composer's `FocusNode` to hold focus after the row is tapped.

## Alternatives considered

**Keep the host name as the title and put the address only in the subtitle.**
Rejected: the host name is the fact that can collide, and the address is what
distinguishes the machine the user is choosing.

**Show both the host name and address on one line.** Rejected: the row already
has a two-line height budget, and joining two identifiers makes the primary
line harder to scan without removing the ambiguity that motivated the change.

**Use a page-level `FocusNode` for the composer.** Rejected: the composer is
rebuilt when the selected peer changes, so a node held by the page can point at
the previous field. The existing false-to-true `autoFocus` edge is tied to the
composer that is actually mounted.

**Leave focus on the selected row and rely on keyboard navigation.** Rejected:
the user asked to type after choosing a conversation, and the application's
existing arrival behavior already treats that choice as an invitation to type.

## Consequences

- Rows are labelled by the machine's network identity rather than by a name
  that may be shared.
- A peer with no discovered address still has a readable title.
- Search still finds a peer by either its address or its display name.
- Selecting a row, including the row already selected, hands the caret to the
  composer without a second click.
- The visible title and the harness finder key intentionally differ for named
  peers; tests that need to express "the row for Bob" use
  `ConversationRow.peer`.

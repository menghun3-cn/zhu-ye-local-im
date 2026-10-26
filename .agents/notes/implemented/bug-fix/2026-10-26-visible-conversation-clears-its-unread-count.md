# Agent Note: A visible conversation clears its unread count

Status: implemented

English | [中文](2026-10-26-visible-conversation-clears-its-unread-count.zh.md)

## Problem

The Conversations surface marked a conversation read only when its row was
tapped. A conversation could be on screen, and genuinely being read, through
two other roads: returning to the surface kept the previous selection open,
and opening from a Device card arrived through the shell's request. None of
those called the read mark, so a message that arrived while the conversation
was open stayed unread on the list — and stayed there even after the user
replied. The count only went away when the user tapped the row again, which
makes the row look like it is describing a message the user has already read.

## Decision

The read mark follows what is *visible* rather than what was tapped. The shell
tells `ConversationsPage` whether it is the surface on top (`isVisible`), and
the page marks whatever conversation is currently open in the pane read on each
frame it is actually visible. The mark is deferred to a post-frame callback and
re-checks visibility when it fires, so switching away before the write does not
mark a conversation nobody is looking at.

This removes the special case for the remembered conversation. The same
visible-and-open rule now covers arriving back through the rail with the
previous selection, opening from a Device card through `requestedPeer`, and a
message arriving while the conversation is already open. Tapping a row still
marks it read, which makes the visible rule the one source of truth instead of
a second path that has to be kept in step.

## Testing

A widget test sends a message into a conversation the window is already showing
without tapping its row, and asserts that the unread count stays at zero and
that the row shows no unread marker.

## Alternatives considered

**Mark the conversation read when a message is sent into it.** Rejected: the
message may not be delivered, and a reply to a peer with several unread
messages should not silently read the ones this Device cannot see.

**Mark read everywhere a conversation is opened, as an explicit call.**
Rejected: it spreads the rule across every entry point and still misses the
case that motivates the fix — a message that arrives while the conversation is
already on screen.

**Keep the visibility check out of the shell by letting the page observe the
`IndexedStack` itself.** Rejected: the page does not own the stack, and asking
it to infer shell geometry from inside would duplicate the shell's own
knowledge of which surface is on top.

## Consequences

- A conversation on screen is read on the next frame, whatever brought it up.
- A message that lands while the conversation is open clears its count without
  any further tap.
- A conversation hidden behind another surface is not marked read, because the
  shell stays the authority on what is on top.
- Tapping a row keeps marking it read, so the visible rule is the single
  source of truth rather than an addition to the old one.

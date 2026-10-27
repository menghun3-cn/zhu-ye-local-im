# Agent Note: The default conversation focuses on startup

Status: implemented

English | [中文](2026-10-27-the-default-conversation-focuses-on-startup.zh.md)

## Problem

The application opens on the Conversations surface and restores the last
conversation, but the composer did not take focus until the user left that
surface and came back. The shell counted tab switches as arrivals, while the
first frame had no arrival to count. The page therefore selected the remembered
conversation and drew its input box, but left the caret outside it, requiring a
click before the user could type.

## Decision

The initial appearance of the Conversations surface is an arrival too. The
shell starts its arrival counter at one, and `ConversationsPage` consumes that
initial request in `initState` when the surface is visible. The existing
`autoFocusComposer` path still performs the actual focus request, so startup,
tab changes, row selection, and requests from the Devices surface all end at
the same composer behavior.

The focus request still depends on there being a current conversation. A first
run with no remembered conversation continues to show the empty pane, and
picking a row later focuses that row's composer through the existing selection
path.

## Testing

A widget test opens Bob's conversation, tears the window down, and mounts a new
window over the same controller state. It asserts that Bob is the single
default-selected row and that the restored composer's focus node holds focus
without any click or tab switch.

## Alternatives considered

**Set `autofocus: true` permanently on the composer's `TextField`.** Rejected:
the controller rebuilds the page while it is hidden behind another surface, and
a permanent request could pull focus away from whatever the user is doing
elsewhere.

**Focus only after a row is selected.** Rejected: that is the behavior that
already worked. It does not cover the default conversation restored on the
application's first frame.

**Hold a page-level `FocusNode` and focus it from the shell.** Rejected: the
conversation view is keyed by peer and can be replaced, so a node owned outside
it can point at the previous field. The composer's own node is tied to the
instance that is actually mounted.

## Consequences

- A remembered conversation is ready to type in as soon as the application
  opens.
- Returning to the Conversations surface and selecting a row keep their
  existing focus behavior.
- A launch with no selected conversation still shows the empty pane rather than
  inventing a recipient.

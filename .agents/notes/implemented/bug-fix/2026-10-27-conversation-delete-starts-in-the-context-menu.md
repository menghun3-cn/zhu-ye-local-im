# Agent Note: Deleting a conversation starts in its context menu

Status: implemented

English | [中文](2026-10-27-conversation-delete-starts-in-the-context-menu.zh.md)

## Problem

Right-clicking a conversation row raised the destructive confirmation dialog
immediately. There was no menu where the user could choose what to do with the
row, so the first visible response to a right-click was already a question
about deleting its history. The desktop conversation list is expected to open
its row actions first, with deletion becoming a confirmation only after the
user chooses that action.

## Decision

Right-clicking or long-pressing a conversation row now opens a context menu
anchored at the gesture. Its `Delete` item raises the second step: an
`AlertDialog` titled `Delete conversation?` with `Delete` and `Cancel`
actions. `Cancel` leaves the row and its history untouched; `Delete` clears
the same local history the row action previously cleared, including removing
an offline row whose only remaining reason to appear was that history.

The three-dot menu in the open conversation header keeps its separate
`Clear chat history` action and wording. This change is about how a row action
is chosen, not about merging the two entry points.

## Testing

The conversation widget tests open the row menu with a real secondary mouse
click, assert that no dialog is open yet, choose `Delete`, cancel once, and
then confirm once. They also exercise the same menu through a long press and
through an offline conversation whose row disappears after deletion.

## Alternatives considered

**Keep opening the confirmation directly.** Rejected: it skips the action the
user selected and makes a right-click itself look like a delete command.

**Put both `Clear chat history` and `Delete` in the row menu.** Rejected: both
would perform the same local-history operation, so two labels would imply a
difference the application cannot honour.

**Add the menu only to right-click and leave long press unchanged.** Rejected:
long press is the mobile equivalent of the same row interaction, and the two
gestures would otherwise lead to different first steps.

## Consequences

- A row action now has a visible intermediate step before anything is deleted.
- Right-click and long press follow the same menu-then-confirmation flow.
- Cancelling either step preserves the conversation and its messages.
- Deleting still clears only local history and does not forget the Device.

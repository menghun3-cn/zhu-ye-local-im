# Agent Note: Long-press a conversation row to delete it on mobile

Status: implemented

English | [中文](2026-10-23-conversation-row-long-press-delete.zh.md)

## Problem

Desktop users can delete a conversation by right-tapping its row, but Android
has no pointer and no right-click, so there is no way to trigger the existing
delete-conversation confirmation from the conversation list. A mobile user can
open a conversation and clear it from the three-dot menu, but cannot delete one
directly from the list surface where conversations are picked.

## Decision

`ConversationRow` accepts a new `onLongPress` callback alongside the existing
`onSecondaryTap`; both are wired to the same `_confirmClearConversation`, so
the desktop right-tap and the mobile long-press share one confirmation dialog
and one `clearConversation` call. The row's `peer` field remains the test
finder key for "the row for Bob", unchanged by the added interaction.

Deleting from the list follows the same meaning the conversation menu gives
"clear": every message with the peer is removed and clipboard entries stay
put. Because the user asked for the row itself to go away, an offline peer
also leaves the list for this sitting — a session-local `_deletedPeers` set
keeps the row out until Discovery hears the peer again, when the row returns
with its Device. A peer that is online or diallable keeps its row; only its
history is cleared.

## Testing

Widget tests exercise `ConversationRow.onLongPress` and assert the
confirmation dialog appears, that cancelling keeps both the row and the
messages, and that confirming clears the selected peer's history while a
connected peer keeps its row. A second test deletes an offline conversation
and asserts the row leaves the list and returns once Discovery places the
peer again. Desktop `onSecondaryTap` behavior is covered by existing tests.

## Alternatives considered

**Add a separate delete button to each row.** Rejected: a row is only two
lines tall; a third action would compete with the clock and the existing
Connect/Pair button and make the list harder to scan.

**Expose delete only from the conversation's three-dot menu.** Already exists,
but requires opening the conversation first; it does not answer "delete this
row from the list", which is what a mobile user expects from a long-press.

**Reuse `onSecondaryTap` for long-press on mobile.** Rejected: `onSecondaryTap`
has no meaning on a touch screen, and sharing one callback would make the
desktop-vs-mobile intent ambiguous at the call site.

**Persist the deletion by forgetting the peer.** Rejected: deleting a
conversation is not forgetting a Device. Erasing the Known Device record would
throw away the peer's remembered alias and address, would not remove a peer
that is still an Owner Group member, and the row would reappear on restart
anyway. A session-local marker gives the user the list they asked for without
overwriting trust or presentation memory.

## Consequences

- Mobile users can long-press a conversation row to open the delete
  confirmation, mirroring the desktop right-tap.
- Both entry points share one confirmation wording and one
  `clearConversation` call, so the two surfaces agree about what deletion
  means and clipboard entries stay put in both cases.
- An offline peer's row leaves the list after deletion and returns when
  Discovery hears the peer again; an online or diallable peer keeps its row
  with an empty history.
- No change to the visible row title or the test finder key.

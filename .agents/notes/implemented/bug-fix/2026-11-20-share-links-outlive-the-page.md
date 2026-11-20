# Agent Note: Share links outlive the page, and deleting one actually revokes it

Status: implemented

English | [中文](2026-11-20-share-links-outlive-the-page.zh.md)

## Problem

Two defects shared one root: the share-by-link page kept its own copy of
the share list, while the link server kept the real one.

- **Backing out threw the cards away.** `_ShareByLinkPageState` held
  `List<_Share>`; the Transfers sub-view unmounts the page when `_sharing`
  flips back, so the state — and every card — was disposed. The links
  themselves were still alive on the server for their 30 minutes, but the
  sender had no way to see, copy or manage them again.
- **Delete never deleted.** `_removeShare` only removed the card from that
  widget list. The server's `_shares` entry lived on, so the "deleted"
  link kept serving files until expiry — the one control that looked like
  revocation was not.

## Decision

The server is the source of truth for the sender's share list; the page
redraws from it.

- **`LinkTransferServer` learned to describe and revoke its shares.**
  `_ShareEntry` now stores the `url` that was handed out — rebuilt links
  could name a different address after an interface change, so the string
  is kept, not reconstructed. `activeShares()` returns an [ActiveShare]
  per live entry (token, url, fileNames, createdAt), omitting expired ones
  even before the cleanup timer runs; `revokeShare(token)` removes the
  entry so `/s/` and `/f/` answer "expired" immediately.
- **`LinkTransfer` exposes both** as `shares` and `revokeShare`.
- **The page keeps no list.** `ShareByLinkPage` builds its cards straight
  from `LinkTransfer.instance.shares` on every build; creating a share is
  a `setState`, deleting one is `revokeShare` plus a `setState`. `_Share`
  and its `GlobalKey` are gone.
- **`_ShareCard` became stateful** and owns its QR `GlobalKey` itself —
  the key has to survive rebuilds for "copy QR" to find the
  `RepaintBoundary`, and a card that redraws from server data cannot borrow
  one from a page-side model anymore. The copy-QR logic moved into the
  card with it.

## Alternatives considered

**Keep the UI list, but in a longer-lived store** (the controller or a
UI singleton). Rejected: it creates a second copy of what the server
already knows, and the delete button still has to reach into the server to
revoke — at which point the server list was the honest source all along.

**Persist shares to disk.** Rejected: the server is in-process, so every
link dies with the app regardless; a durable list would only preserve
cards that point at dead links.

**Fix only the delete button.** Rejected as half a fix: revocation without
persistence still loses the cards on back-navigation, which was the
reported symptom.

## Consequences

- A share survives leaving the sub-page, switching tabs, and any rebuild —
  until the user deletes it or its 30 minutes run out, whichever comes
  first. App restart still ends every share, because the server does.
- The trash icon now means what it looks like: the link stops working
  immediately, verified server-side rather than assumed.
- Expired shares disappear from the list on the next rebuild even if the
  minute timer has not run yet.
- `activeShares()` ordering is insertion order, matching what the old UI
  list showed.

## Testing

- `test/link_transfer/link_server_test.dart` covers `activeShares`
  (url, fileNames, live flag) and `revokeShare` — including that a revoked
  `/s/` page answers 404 and a second revoke returns false.
- `test_flutter/ui/share_by_link_page_test.dart` drives back-out-and-return
  through the real Transfers sub-view and asserts the card is still there,
  then deletes it and asserts `LinkTransfer.instance.shares` is empty.

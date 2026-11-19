# Agent Note: Share by link lives under Transfers, with an enlarged QR and top toasts

Status: implemented

English | [中文](2026-11-19-share-link-under-transfers.zh.md)

## Problem

The Share by link page shipped under 我的, among the low-frequency cards —
but creating a link is a *sending* act, the same kind of thing the Transfers
tab exists for, and a user looking to hand a file to somebody who has no
app would not think to open 我的 for it. Two smaller frictions rode along:
the 84 px QR on a share card can be scanned at arm's length but cannot be
screenshotted or shown on a second screen, and the page still answered its
hints with bottom [SnackBar]s even though the app had already standardized
on the top toast ([TopToast../../../../lib/ui/top_toast.dart)) for exactly
this reason.

## Decision

The surface moved, the QR grew on demand, and the last SnackBars left the
app.

- **`TransfersPage` is now stateful.** Its default view is the transfer
  list with a share-by-link entry card on top — same card shape as the My
  page's entries (icon, title, one line of what it does, chevron). Tapping
  it flips an in-page flag to `ShareByLinkPage` under a
  [SubPageHeader../../../../lib/ui/widgets.dart) back header, the same
  "surface inside a surface" pattern the My page uses. A flag rather than
  a pushed route: the tab lives in the shell's `IndexedStack`, so leaving
  and returning already preserves state, and backing out of the sub-view
  keeps the share list alive too.
- **`_SubPageHeader` was promoted** from a private widget in `my_page.dart`
  to the shared `SubPageHeader` in `widgets.dart`, because two surfaces now
  need it. `MyPage` lost the share card, the `shareByLink` sub-page branch,
  and the `myCardShareByLink*` strings; the entry reuses
  `shareByLinkTitle`/`shareByLinkDesc`.
- **Tapping a card's QR opens an `AlertDialog`** with the same link rendered
  at 256 px on white, plus copy-QR and close actions. Copy still reads the
  card's `RepaintBoundary`, so the dialog is purely a bigger window onto
  the same code — there is no second QR to keep in sync.
- **Every remaining SnackBar became `TopToast.show`.** Six in
  `share_by_link_page.dart`, one in `screenshot_page.dart` — whose hardcoded
  refusal sentence also became a real localized key,
  `screenshotHotkeyUnavailable`. `flutter analyze` and a grep for
  `SnackBar(`/`showSnackBar(` now find only comments and tests.

## Alternatives considered

**A pushed route for the share page.** Rejected: `Navigator.push` would
discard the share list on pop, and the tab's `IndexedStack` already keeps
pages alive — an in-page flag gets the same "don't lose my links" for free
without a second navigation concept.

**The share UI embedded as a permanent section above the transfer list.**
Rejected by the user in favour of the sub-view: the page already carries a
picker button, a description and a scrollable card list, and pinning all of
that above every transfer card would push the actual transfers below the
fold.

**Keeping SnackBars on this page.** Rejected: the app replaced bottom
snackbars with the top toast earlier precisely because the bottom is where
the input area is; leaving six of them on one page would have been the last
holdout, not a style choice.

**A "save QR as image" button instead of the enlarge dialog.** Rejected as
unasked-for scope: the dialog covers the stated need (screenshot it, show
it), and writing a file adds a save-dialog path for a picture the user can
already copy as PNG.

## Consequences

- 我的 no longer lists link sharing; the Transfers tab does, next to the
  transfers it conceptually belongs with. The feature itself — picker,
  drop, grouped `/s/` page, QR copy — is unchanged.
- A share card's QR is now a click target; the dialog's copy button reuses
  the card boundary, so "copy QR" behaves identically from either place.
- No `SnackBar` remains in `lib/`; the top toast is the only transient
  message surface, matching the convention the earlier toast work set.
- `SubPageHeader` is shared chrome now — a third sub-page surface should
  reuse it rather than growing another private copy.

## Testing

- `test_flutter/ui/share_by_link_page_test.dart` opens the page through
  传输 → 通过链接分享 instead of 我的, gains a case that taps the card QR
  and asserts the dialog draws a `QrImageView` larger than 200 px, and its
  nothing-to-share assertion now looks for the toast in the window overlay.
- The copy-QR and drop tests are unchanged: they exercise the page, not
  the route that reaches it.
- The moved entry is covered indirectly by every existing Transfers-page
  test still passing — the list itself did not change shape.

Cross-reference: the surface this note moves was built in
[share links cover many files and carry a QR code](2026-11-17-share-links-cover-many-files-and-a-qr.md).
Its facts were updated in the same change to point here.
# Agent Note: Share links cover many files and carry a QR code

Status: implemented

English | [中文](2026-11-17-share-links-cover-many-files-and-a-qr.zh.md)

## Problem

The Share by link page could only be fed through the system file picker,
and it answered one link per file: dropping five files on it did nothing at
all, and sharing them meant five cards, five URLs and five copies. The
recipient side had no page either — each link downloaded its one file
directly, so "here are the photos from the trip" arrived as a spray of
unrelated URLs. And the only way to get a link onto a phone was to select
it, copy it, and paste it somewhere the phone could see.

## Decision

One pick or drop is now one share: a single link to a server-rendered list
page, plus a QR code encoding the same link, on one card.

- **`LinkTransferServer.createShare`** (`lib/core/link_transfer/`) keeps a
  second table beside `_links`: `_shares[token] → {files, createdAt}` with
  the same 30-minute expiry and the same cleanup pass. The returned URL is
  `/s/<token>`; `GET /f/<token>/<index>` streams the file at that index —
  indexed rather than named, so non-latin-1 and duplicated names cannot
  break the URL. The list page is rendered in the handler with HTML-escaped
  names and UTF-8 output (the response's default latin1 would have turned
  `报告.pdf` into `??.pdf`), because the recipient is a plain browser that
  may not have the app — or the app's locale; the page is English like the
  single-file index it sits beside.
- **`ShareByLinkPage`** wraps its whole content region in `DropTarget`
  (`desktop_drop`, the same plugin the conversation uses), so files dropped
  anywhere on the page — not only on the empty state — go through the same
  `_sharePaths` road the picker does. Paths are filtered by
  `File.existsSync()` up front: a dropped folder is skipped, and a drop that
  yields nothing gets the "no files to share" snackbar rather than silence
  or a bogus failure.
- **The card** shows the file count, the names, the link as `SelectableText`,
  and an 84 px `QrImageView`. Three actions: copy link (unchanged), copy QR,
  remove. "Copy QR" reads pixels back through the card's `RepaintBoundary`
  at 4× size and hands the PNG to `PasteResolution.paste.writeImage` — the
  same seam screenshot copying already uses, which is why it works on
  Android too and why a widget test can stand in for it.
- **`qr_flutter: ^4.1.0`** is the new dependency: pure Dart, three years
  stable, and it provides both the displayed `QrImageView` and the
  `QrPainter` the boundary rasterises — no second QR implementation.
- The per-file `/download/<token>` path and the conversation's `shareByLink`
  action are untouched: a share *group* and a single-file link are different
  products, and unifying them would have changed a shipped flow for no gain.

## Alternatives considered

**One link per file, kept, with a QR per card.** Rejected by the user: five
files meant five URLs to paste and five codes to show, which is the friction
the feature exists to remove. The list page is what makes "one share" mean
one link.

**A zip archive behind the share link.** Rejected: it needs an archiving
dependency and a server-side pack step, and the recipient still has to open
the archive before seeing anything. Per-file download rows on a list page
are what every LAN share tool converged on.

**File names in the download URL (`/f/<token>/<name>`).** Rejected:
percent-encoding, HTML-vs-URL escaping and duplicate names are three bugs
wearing one trench coat; the index is boring and cannot be wrong.

**Hand-rolled QR rendering.** Rejected: QR version selection and error
correction are a standard with a standard library behind it; `qr_flutter`
is pure Dart and stable, and self-drawing would be the project's third QR
implementation waiting to happen.

**Copy the QR's text (the URL) instead of its image.** Rejected: that is
what the copy-link button already does; "copy the QR code" means the picture
a chat client can paste.

## Consequences

- Dropping files on 我的 → 链接分享 creates a share immediately — no picker,
  no staging step — and the card that appears carries both the link and the
  code for it.
- A recipient on the same LAN opens `/s/<token>` in any browser and sees a
  file list with per-file download buttons; each `/f/` hit streams with the
  same `Content-Disposition` handling the single-file route already had.
- The QR encodes the share-page URL, so scanning it and pasting the link
  land on the same page — one share, two hand-offs.
- Copying the QR needs the `pasteboard` write path; where a platform refuses
  it the card reports the failure sentence rather than claiming success.
- The share page is English-only, matching the existing `/` index; a
  Chinese-first recipient page is a possible follow-up, not a regression.
- There is no cap on files per share, same as the picker never had one.

## Testing

- `test/link_transfer/link_server_test.dart` covers the group: the list
  page names every file (including a non-latin-1 one), `/f/<token>/<i>`
  streams the right bytes with a `filename*` disposition, directories and
  missing paths are filtered, an all-filtered share answers null, and
  unknown tokens and out-of-range indexes answer 404.
- `test_flutter/ui/share_by_link_page_test.dart` drives the real page: the
  picker and a `DropDoneDetails` drop each produce one card with a
  `QrImageView`, a folder-only drop produces the no-files snackbar, and the
  copy-QR button puts PNG-magic bytes on the scripted clipboard.

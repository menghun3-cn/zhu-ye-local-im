# Agent Note: Share-link downloads survive any file name

Status: implemented

English | [中文](2026-11-10-share-link-download-survives-any-filename.zh.md)

## Problem

A share link opened in a browser could die before answering anything.
`_serveDownload` interpolated the file name straight into the
`Content-Disposition` header, and HTTP header values are latin-1 at best:
a name like `报告 final.pdf` made `headers.set` throw `FormatException`
inside the request handler. The throw happened before any response byte
was written, the `HttpRequest` was never closed, and the recipient's
browser reported the page as unreachable — "打不开" — for a link that
was perfectly valid.

Two smaller faults sat on the same path: `/info/` hand-assembled its
JSON, so a name containing `"` or a control character produced
unparseable output, and a handler exception anywhere left the request
hanging rather than answering an error.

## Decision

`Content-Disposition` is now built by `_contentDisposition`: the UTF-8
name travels percent-encoded in the RFC 5987 `filename*` parameter —
attr-char bytes pass through, everything else becomes `%XX` — and
`filename` carries an ASCII fallback with `"`, `\`, and non-printable
characters replaced by `_`. The download also sets `Content-Length`
from the file's stat, so the response no longer relies on chunked
termination.

`/info/` writes its payload through `jsonEncode`, which escapes whatever
the name contains. And `_handleRequest` wraps the whole dispatch in a
try/catch that answers 500 and closes the response when a handler throws
— a dead connection is never the answer to a request the server
understood.

`start()` also stopped reporting the *requested* port: with
`preferredPort: 0` (or any bind that landed elsewhere) `actualPort`
said 0 while the socket listened on an ephemeral port, and `createLink`
would have emitted `http://<ip>:0/download/<token>`. `actualPort` now
always reads `_server.port`.

## Consequences

- Links to files with CJK, emoji, or any non-latin-1 name download
  correctly; browsers that understand `filename*` (all of them) save
  the real name, others fall back to the sanitized `filename`.
- A name that is entirely non-ASCII degrades to an underscore fallback
  rather than failing; `filename*` still carries the true name.
- Handler bugs now surface as a 500 the recipient can see, not a
  connection that hangs until timeout.
- `LinkTransferServer(preferredPort: 0)` is usable in tests and embeds
  the true bound port in generated links.

## Alternatives considered

**Strip non-ASCII from the name entirely.** Rejected: it would "fix"
the crash by silently renaming every CJK file to underscores for the
recipient — a worse product than a correct `filename*`, and the
encoding is a solved standard, not invented machinery.

**Catch the error only around `headers.set`.** Rejected: the same
hang-on-throw existed for every handler (`/info/` JSON, stream
failures), so the guard belongs at the dispatch boundary where one
catch covers all of them.

**Serve the index page at `/download/<token>` instead of the file.**
Rejected: the current contract — open the link, the file downloads — is
the simplest thing that works in every browser and chat app, and the
index page's token-extraction script only ever ran at `/` anyway.

## Testing

`test/link_transfer/link_server_test.dart` runs the real server on an
ephemeral port and asserts over HTTP: an ASCII download keeps its name,
a non-latin-1 name returns 200 with a `filename*` parameter and no raw
non-ASCII in the header, `/info/` returns parseable JSON for a CJK
name, and an unknown token is a 404. The non-latin-1 case fails on the
pre-fix code with the `FormatException` reproduced in the field.

# Agent Note: Tapping a landed file opens it

Status: implemented

English | [中文](2026-11-12-tapping-a-landed-file-opens-it.zh.md)

## Problem

A file this Device received could be seen but not used. On Windows the only
answer the surfaces offered was **打开所在目录** — and on Android even that one
answered "could not open", because `SystemRevealer` was written Windows-only.
A tap on the bubble did nothing on either platform: the file the user had just
accepted had no way to be opened at all, which is the first thing anybody wants
to do with a received APK or document.

The gap was not an accident of one platform. `Revealer`, `LinkOpener` and the
update installer each answered "hand this to the operating system" for exactly
one kind of thing — a folder, a URL, an APK this app downloaded itself — and a
file that arrived over the wire fitted none of them.

## Decision

Opening a file is now a first-class action beside revealing its folder, on
every surface that shows a settled Transfer:

- **`FileOpener` / `OpenResolution`** (`lib/ui/open_file.dart`) mirrors the
  `Revealer` and `LinkOpener` seams: production gets `SystemFileOpener`, a test
  gets a stand-in. Windows asks `explorer` with the same `/`→`\` argument
  conversion the revealer needs, for the same reason — Explorer reads a `/` in
  an argument as one of its own switches, and received paths are `/`-joined on
  every platform. Android asks the runner's own channel. Both refuse a path
  that is not there before any shell is invoked.
- **`SystemRevealer.reveal` learned Android** — and moved to
  `lib/ui/system_reveal.dart`, because the channel it needs there is a Flutter
  import and `reveal.dart` must stay loadable by `dart test`: the folder goes
  to the same channel's `openFolder`, which asks a file manager through a
  `content://` URI.
  A folder inside the app's private storage is one no file manager can browse,
  so false there is an ordinary answer and the existing toast says so.
- **`MainActivity` grew a `files` channel** (`cn.hnasct.local_transfer/files`)
  with `openFile`/`openFolder`. Both hand the target to `ACTION_VIEW` as a
  FileProvider `content://` URI with a read grant — the only kind of address
  Android lets another application open; a `file://` path is refused outright.
  A file is offered under its real MIME type (`MimeTypeMap`, with `.apk` named
  explicitly because a received update is exactly that file), so an APK reaches
  the package installer and a document reaches whatever claims it. A folder is
  offered as `resource/folder`; no taker means false, not an error.
- **`update_paths.xml` exposes what can be opened**: all of `filesDir`
  (received files land in `incoming/` under it, and a destination the user
  typed is under it too), all of `cacheDir` (what a picker hands back), and
  shared storage, because a file this Device *sent* may still live there.
- **The surfaces**: a file bubble opens on tap — except a bare image, whose tap
  is already the preview — the context menu offers **打开** beside
  **打开所在目录**, and the Transfers card carries an open button next to the
  folder one. `localPath` is only recorded after `TransferCompleted`
  (`_recordLocalPath` runs on the transfer's outcome), so a tap can never meet
  a half-written `.part` file.
- Two strings joined the ARB files: `openFile` and `cannotOpenFile`.

## Alternatives considered

**`url_launcher` or `open_file`/`open_filex` plugin.** Rejected for the same
reason `external_links.dart` rejects `url_launcher`: a plugin is a native
registration bought for two calls, and this project already owns the channel
that does them — `paths` for the data directory, `update` for the installer,
now `files` for opening. The Kotlin is thirty lines of `Intent` either way.

**`ACTION_VIEW` on a `file://` URI.** Rejected: Android refuses to hand a
`file://` path to another application — `FileUriExposedException` on modern
versions — which is exactly what FileProvider and its per-URI read grant exist
to replace.

**Save received files to public storage on Android** (Downloads via
`MediaStore`, or SAF) so a file manager could show the folder. Rejected as out
of proportion: it is a storage-model change — permissions, URI persistence,
the picker answers that are `content://` rather than paths — bought to make
**打开所在目录** work, while the user's actual need is to *open the file*,
which the private directory does not prevent. The private `incoming/` remains
the recorded gap it already was.

**Hide 打开所在目录 on Android.** Rejected: the honest answer is already
there — the channel answers false and the toast says the folder could not be
opened — and a user-chosen destination outside the private directory *can* be
shown by a file manager, so the line is not a lie in every case.

**`cmd /c start` on Windows, `explorer /select,` to highlight.** Both
rejections stand as recorded in
`2026-10-10-a-folder-spelled-with-the-wrong-slash-opened-documents` and
`2026-10-09-images-arrive-on-their-own-and-a-file-can-be-shown-in-its-folder`:
`cmd` brings quoting hazards to a peer-influenced name, and `/select,` shares
its token with the path so a space breaks the pairing.

## Consequences

- A received APK on Android now reaches the system package installer — the
  exact file the report was about — and any other type reaches whatever
  application claims it, or Android's own chooser.
- **打开** is offered wherever a path exists, on both platforms, so Windows
  gained the tap-to-open it never had and Android gained the whole answer it
  lacked.
- The FileProvider surface is wider than `update/` alone; the grant is still
  per-URI and per-intent, so widening the paths exposes nothing by itself.
- The Kotlin half is verified by inspection and by the Dart contract around
  it, not by an instrumented run: the widget suite stands in at
  `OpenResolution`, and no gate on this machine builds an APK.

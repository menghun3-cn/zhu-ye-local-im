# Agent Note: a file message copies as a file

Status: implemented

English | [中文](2026-11-26-a-file-message-copies-as-a-file.zh.md)

## Problem

A file message in a conversation could be opened, revealed in its folder,
shared, forwarded and deleted, but it could not be copied the way a file is
copied in a file manager: there was no way to put the file itself on the
system clipboard and paste it somewhere as a file. The picture message already
had 「复制图片」, but that copies the picture's content, not a file — a
different thing, and the one the user did not ask for here.

## Decision

`ClipboardPaste` — the same seam the composer reads Ctrl+V through and the
picture copy writes through — gained `writeFiles(List<String> paths)`. On
Windows and the other desktop platforms it calls `Pasteboard.writeFiles`,
which writes the `CF_HDROP` list a file manager writes; on Android it goes
through the app's own `cn.hnasct.local_transfer/files` channel instead,
because the pasteboard plugin's `writeFiles` expects content URIs rather than
the filesystem paths this app holds. The Android side turns each existing
file into a `content://` URI through the existing `update_file_provider` and
sets one `ClipData` on the `ClipboardManager`; read permission is granted by
Android's `ClipboardService` to each package that pulls `getPrimaryClip`, the
same mechanism the image copy already relies on, so no new provider or
manifest entry was needed.

The menu line is `copyFile` / `cannotCopyFile`, offered only for
`PayloadKind.file` messages whose `names.length == 1` and whose `localPath`
is a real file. Multi-item Transfers and folder sends are deliberately not
offered: their `localPath` names at best the first landed file, and copying
that would look like it copied the message while putting the wrong thing on
the clipboard. Whether the path is still a file is checked both when the menu
is built and again at the tap, because a folder send with a single file still
has a directory as its path. A refused write reaches the user as `cannotCopyFile`; a successful
copy says nothing, because the pasted file is the confirmation.

This is the file-side copy that
[the picture note](2026-10-09-pictures-stand-on-their-own-and-can-be-copied.md)
rejected *for pictures*: 「复制图片」 still means the picture's content, while
「复制文件」 now means the file. The two lines are told apart by `PayloadKind`,
so neither surface has to guess which copy the user meant.

## Alternatives considered

**Windows-only via `Pasteboard.writeFiles`, with Android unsupported.**
Rejected: Android is a v1 platform, and copying a file there is not impossible
— it needs the `content://` URI form the platform's own channel already knows
how to build for open and share.

**Copy the path as text.** Rejected: it is not the file-manager copy the user
asked for, and it is the weaker answer the reveal action already gives in a
more useful form.

**Offer copy on multi-item and folder Transfers too.** Rejected for this
change: `TransferView` does not reliably name every local path for those, so
the only honest single-path answer would copy the first file or the directory
while the message names many. That is a worse lie than no line.

**Change 「复制图片」 to copy the image file as well.** Rejected by scope: the
user asked for file messages only, and the existing image copy already answers
the picture-content question.

## Consequences

- A settled single-file message can be pasted into a file manager or another
  application as the file itself on both v1 platforms.
- The clipboard seam now writes files as well as images; tests assert the
  paths through `ScriptedClipboard.copiedFiles`.
- Android file copy depends on `update_paths.xml` continuing to expose the
  directories received and picked files can live in; narrowing that provider
  would silently break this action.
- Folder sends and multi-file Transfers still have no copy line; if that is
  ever wanted, `TransferView` needs to carry every landed path rather than one.

## Testing

`test_flutter/ui/pages_test.dart` covers a landed file message offering
`copyFile`, handing the landed path to the scripted clipboard, and reporting
`cannotCopyFile` when the write is refused; the picture menu test asserts
`copyFile` is absent. The Android channel itself is verified by compilation
and the same FileProvider path open/share already use.

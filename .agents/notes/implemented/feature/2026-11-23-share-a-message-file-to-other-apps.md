# Agent Note: A landed message file can be shared to another app on Android

Status: implemented

English | [中文](2026-11-23-share-a-message-file-to-other-apps.zh.md)

## Problem

A file or picture that arrives in a conversation — or one this Device sent —
is only useful inside this app: it can be opened, its folder revealed, its
pixels copied. The common next step is handing it to WeChat, and there was no
way to do that short of leaving the app, finding the file in a file manager,
and dragging it into a chat.

WeChat itself offers no share SDK and no URL scheme for receiving a file
from a third-party app, so "分享到微信" cannot be a direct call. What Android
offers instead is the system share sheet: an `ACTION_SEND` intent that every
receiving application — WeChat included — answers, with the user picking the
target. That sheet is the whole mechanism available, and it is also the
honest label for the feature: the menu line says 分享, not "分享到微信",
because the sheet's contents are the device's, not ours.

## Decision

The share rides the platform channel the app already owns rather than a new
plugin. `MainActivity`'s `cn.hnasct.local_transfer/files` channel gained a
`share` method beside `openFile` and `openFolder`: it turns each path into a
`content://` URI through the existing `update_file_provider` FileProvider —
whose `update_paths.xml` already exposes `filesDir`, `cacheDir` and external
storage, which covers where received files (`filesDir/incoming`) and picked
files land — and fires `ACTION_SEND` for one file (real MIME type via the
existing `mimeOf`) or `ACTION_SEND_MULTIPLE` under `*/*` for several, with
every URI carried in the intent's `ClipData` so the read grant reaches all of
them.

On the Dart side the seam mirrors `OpenResolution`/`RevealResolution`:
`lib/ui/share_file.dart` defines `FileSharer` (`supported` + `share(paths)`),
`SystemFileSharer` answers `supported` from `Platform.isAndroid` and filters
the list down to files that still exist, and `ShareResolution.sharer` is the
mutable field tests substitute. `transfer_actions.dart` gained
`canShareTransferFile` (`localPath != null && sharer.supported`) and
`shareTransferFile`, and `TransferContextMenu` draws a 分享 line —
`Icons.share_outlined`, between 打开 and 复制图片 — only where the predicate
holds. A share that comes back false raises the same TopToast sentence the
other file actions use.

Only `view.localPath` is shared — the first item of a multi-item send, the
same answer 打开所在文件夹 and 打开 already give, because the view tracks one
path per message.

## Alternatives considered

**The `share_plus` plugin.** Rejected: it would buy a dependency and a second
FileProvider configuration to do what ~50 lines of Kotlin on the existing
channel already do. The project deliberately ships almost no plugins — the
runner's own channels exist precisely so platform facts arrive without
pulling in packages — and this feature needed nothing the channel lacked.

**A `queryIntentActivities` pre-check before `startActivity`, the way
`openPath` does it.** Rejected for this method: on Android 11+ package
visibility filters query results unless the manifest declares the intent
filters, and a filtered-empty answer would report "nothing can take this"
while WeChat sits right there. Starting the intent resolves the sheet
honestly; an empty one throws `ActivityNotFoundException`, which Dart reads
as the same false either way.

**Targeting WeChat specifically** (its package name, a `weixin://` scheme).
Rejected: WeChat exposes no API for third-party file delivery, and hard-coding
its package would break the moment it is not installed while still pretending
to be a WeChat feature. The chooser is the contract Android actually offers.

**Windows support now.** Deferred rather than rejected: Windows has no
system share contract for arbitrary files. The plausible roads — copying into
WeChat's `FileStorage` directory or writing a `CF_HDROP` clipboard entry —
are fragile or need hand-rolled Win32, and neither was worth bundling into a
change whose demand is Android-shaped. `FileSharer.supported` is where a
Windows implementation would plug in.

## Consequences

* The menu line appears on every surface `TransferContextMenu` serves — the
  conversation bubble and the Transfers card's menu alike — wherever a share
  sheet exists, which today means Android only.
* A file shared this way is read by whatever the user picks under a
  read-only grant scoped to that share; the app keeps no record and the
  bytes never leave the device except through the receiving app.
* `supported` lives on the sharer, not in a `Platform.is` read inside the
  predicate, so widget tests can offer and withhold the line without
  pretending to be Android.
* The Kotlin side added no manifest entries: `update_file_provider` already
  covers every directory this app can write a received or picked file into.

## Testing

`test_flutter/ui/share_transfer_test.dart` drives a real two-Device transfer
through the harness, opens the landed file's menu, taps 分享, and asserts the
sharer received exactly the landed path; it then flips `supported` off and
asserts the line disappears while the rest of the menu stays. The channel
method itself is exercised only on a device — no host test can open a chooser.

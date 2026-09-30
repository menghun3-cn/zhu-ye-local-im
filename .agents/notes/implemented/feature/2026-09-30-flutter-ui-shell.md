# Agent Note: The application has a screen

Status: implemented

English | [中文](2026-09-30-flutter-ui-shell.zh.md)

## Problem

Every layer of the product worked and none of them was reachable. `lib/main.dart`
was a placeholder reading "No devices discovered yet", and the
[application layer](2026-09-30-app-layer-plain-dart-orchestration.md) that
composes Discovery, Pairing, Sessions, Transfers and clipboard mirroring — and
that is exercised by 15 cases over real loopback TCP — had no caller inside the
app. A user could not pair a Device, send a file, or turn clipboard sync on: the
product was a test suite with a window in front of it.

Two constraints shaped what the screen could be. The first is that `flutter test`
cannot start on this machine at all (the zero-trust client strips the headers a
loopback WebSocket upgrade needs), so nothing worth testing may live in a widget.
The second is that this project ships no plugins, so the pieces a desktop
application normally gets from one — a file browser, a clipboard change
notification, an application data directory on Android — have to be built from
what Dart and the platform channels already offer, or be left out and said so.

## Decision

**`lib/ui` is a rendering of `LocalTransferController`, and holds no protocol
state of its own.** It calls the controller and draws what the controller
reports; the four surfaces are Devices, Transfers, Clipboard and Settings, and
each is a `ListView` over a view object the app layer already produces.

What holds it together:

- **`LocalTransferApp`** builds the controller over the seams
  `openPlatformSeams` resolved and calls `start()`. A failure there is a screen
  with the reason on it, never a stack trace before the first frame: a window
  that looks like it works is the one outcome that must not happen.
- **`ControllerScope`** — an `InheritedWidget` over the controller, rebuilt by
  the controller's coarse `changes` tick — is the only way a page reaches the app
  layer. One rebuild per change at the root, no subscription for a page to leak,
  and no per-field stream for two widgets to race over.
- **`HomeShell`** puts the four surfaces on a `NavigationRail` when the window is
  wide and a `NavigationBar` when it is not, with a badge for the Transfers that
  are waiting for an answer — the one thing worth interrupting for.
- **`FlutterSystemClipboard`** reads and writes through Flutter's `Clipboard` and
  watches by polling: a clipboard change notification needs a native window this
  project cannot open without a plugin. The poll loop is
  `PollingClipboardWatcher` in `lib/core`, so what it reports, what it ignores,
  and when it stops are all covered by `dart test`.
- **Where the profile lives** comes from platform facts, in `lib/core`
  (`profileFilePath`): `%APPDATA%\LocalTransfer` on Windows, the app's own files
  directory on Android through a channel this project implements in
  `MainActivity.kt`, and null — run in memory, keep the identity for as long as
  the app does, and say so on the Settings surface — when there is nowhere
  durable. `defaultIncomingDirectory` follows the same shape: Downloads on
  Windows, the app's own directory on Android.
- **Manual Address is reachable**, which needed one new app-layer call:
  `LocalTransferController.connectTo({address, port})` dials without pinning a
  Fingerprint, because the user typed an address rather than choosing a Device.
  The handshake still proves the peer holds the group secret, and a Device from
  another Owner Group is still refused.
- **Pairing is offered whether or not this Device is already in a group.** Adding
  a third Device is a supported flow in the Pairing service — a Device that holds
  a secret hands that secret over, and two Devices from different groups are
  refused — so the screen does not hide it behind a first-run state.
- **Android's `INTERNET` permission is declared in the main manifest.** The
  Flutter template only puts it in the debug manifest, for the tool's own use;
  without it a release build opens no socket, and every socket is the product.

What each surface shows, in the order a user meets them: Devices shows what this
Device says about itself, both directions of Pairing, and the peer list with
Connect, send, and trust; Transfers shows every Transfer with its progress and
answers an offer with a folder to land in; Clipboard shows the mode — with a mode
this platform cannot honour visible and disabled rather than hidden — the entries
waiting to be applied, and what has been applied; Settings shows the identity,
the whole Fingerprint, where the profile lives, and the notices the layers below
have reported.

## Alternatives considered

**Native file pickers, on both platforms.** Rejected for this change. A picker is
either a plugin, which this project does not ship, or two native implementations
this machine cannot verify: an intent and an `onActivityResult` on Android, an
`GetOpenFileName` call in the C++ runner on Windows. Sending a file therefore
takes a path — typed or pasted — and the dialog says why instead of showing a
Browse button that does nothing.

**A router, with a screen per flow.** Rejected. The whole application is four
surfaces and three dialogs; a routing table would be a fifth thing to keep in
step with the controller's state for no gain, because the state that decides
which screen is right already lives in the controller and rebuilds the tree.

**Widgets beside the controller, in `lib/app`.** Rejected; the boundary is its
own decision, recorded in
[the note on confining Flutter to `lib/ui`](../architecture/2026-09-30-flutter-confined-to-lib-ui.md).

**Hide a clipboard mode the platform cannot honour.** Rejected: "why can I not
mirror here" is a question the screen should answer by showing the mode,
disabling it, and naming the platform's reason next to it.

**Answer an offer automatically for a Favorite.** Rejected, as in the layer
below. Accepting a Transfer needs a destination folder, and a Device that
invented one from a peer-supplied name would be spending a permission the user
never gave. The favorite toggle is on the peer list and skips nothing yet, which
is a deliberate debt.

**Let each page subscribe to the streams it needs.** Rejected except for one
case: the Clipboard surface remembers the last twenty entries the mirror applied,
because that is a scroll-back and only a screen wants it. Everything else is read
from the rebuilt views, which is the reason the rebuild is coarse in the first
place.

## Consequences

- `dart test` runs 366 cases, 25 of them added by this change: the poll watcher
  (5), where a profile and a download folder go (8), the view and formatting
  helpers (7), Manual Address over real loopback TCP (3), and the two cases that
  enforce the `lib/ui` boundary. `flutter analyze` reports no issues, and
  `flutter build windows --debug` links a `local_transfer.exe`.
- **What is not verified here, and should not be read as verified.** No widget
  test ran: `flutter test` cannot start on this machine, so the widget tree is
  covered by analysis and by a build, not by driving it. The window has not been
  opened, so "the first frame renders" is unproven. The Android channel is
  unverified code — no Android build was attempted in this session — and its
  Dart side is written to degrade to "nowhere to write" if it is missing.
- Gaps, deliberately left and named: no file browser; no way to forget a Device
  (that needs an Owner Group operation the core does not have); on Android a
  received file lands in the app's own directory, not in Downloads or the
  gallery, which needs a media-store step; `ACCESS_LOCAL_NETWORK` is not declared
  or requested, which Android 17 will require (facts in
  [docs/android-background-constraints.md](../../../../docs/android-background-constraints.md)).
- The discovery socket is bound before the first frame and released only when the
  process ends, so a second copy of the app on one host shows the failure screen
  rather than the application. That is the honest rendering of a well-known
  broadcast port; a per-instance discovery port is the change that would remove
  it.
- Renaming still costs every open Session, which the layer below decided and this
  screen inherits: the Rename action is on the Devices surface, where the cost is
  visible, rather than inside a Session where it would not be.

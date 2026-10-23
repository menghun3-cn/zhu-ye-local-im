# Agent Note: Keep the mobile shell clear of system bars and name the pairing boundary

Status: implemented

English | [中文](2026-10-22-mobile-shell-system-bars-and-pairing-copy.zh.md)

> **Superseded in part** by
> [Discovery connects automatically](2026-10-23-discovery-connects-automatically.md):
> the `SafeArea` decision remains, while the listening fact now reports
> automatic-connection readiness rather than the old pairing boundary copy.

## Problem

The home shell deliberately has no `AppBar`, but its `Scaffold.body` drew the
surfaces without a top `SafeArea`. On Android, the narrow Conversations layout
therefore put its compact back button eight logical pixels from the top of the
window. The status bar covered most of that target and could consume the tap, so
a user could enter a conversation and then be unable to return.

The same surface also reported `监听：不接受连接` for every Device without a
Session listener. Discovery and pairing already remain available while a Device
is unpaired; accepting a Session correctly requires the group secret created by
pairing. The old sentence collapsed that authentication boundary into wording
that made the whole network surface look broken. A real listener failure after
pairing needs a different answer from "pair first".

## Decision

The shell wraps its body in `SafeArea(bottom: false)`. The top and side insets
now apply to every surface because the shell is the one widget always present
around them. `bottom: false` avoids adding a second inset above the
`NavigationBar`, which already accounts for the bottom system area, and above
the composer, which owns its own bottom `SafeArea`.

The listening fact now distinguishes three states:

* an open Session port is reported as `onPort(port)`;
* an unpaired Device says `sessionsNeedPairing`, rendered in Chinese as
  `配对后接受连接`;
* a paired Device with no Session port says `notAcceptingSessions`, preserving
  the honest failure state when listener startup did not succeed.

This is a wording and layout fix, not a relaxation of authentication. Unpaired
Devices still answer pairing requests, but do not accept Sessions without a
group secret.

## Alternatives considered

**Put the inset only on `ConversationsPage._PaneHeader`.** Rejected: the shell
also draws Devices, Transfers, Clipboard, Settings, and About without an
`AppBar`; a fix in one header would leave the same defect on the other surfaces
and invite a second copy of the inset rule.

**Restore an `AppBar` above the shell.** Rejected: the shell intentionally
removed that strip because the window title bar already names the application
and the Device name belongs on the Devices surface. An empty `AppBar` would
reserve space by adding chrome that does not carry information.

**Allow unpaired Devices to accept Sessions.** Rejected: the group secret is the
authentication boundary for messages and clipboard content. Removing it would
make discovery or a local network address sufficient authorization.

**Keep the generic `not accepting Sessions` sentence for both causes.**
Rejected: it tells an unpaired user the app is malfunctioning when the required
next step is to pair, while obscuring the different state of a paired Device
whose listener failed to bind.

## Consequences

Every shell surface now starts below the status bar on Android, including the
narrow conversation header and its back target. The bottom inset remains owned
by the navigation bar and composer, so the change does not create a blank strip
above them.

The Devices and Settings surfaces now name the reason no Session listener is
present. Users can still discover a peer and complete pairing from the
unpaired state; after pairing, the listening fact changes to the actual port.

The widget suite injects a 28-pixel top inset into a narrow window, opens a
paired conversation, asserts that the back button begins below that inset, and
taps it to return to the list. The Devices page test pins the unpaired wording.

## Testing

`test_flutter/ui/shell_test.dart` covers the status-bar inset and back
navigation on a narrow screen. `test_flutter/ui/pages_test.dart` covers the
unpaired listening fact, while the existing paired path continues to assert the
actual port.

# Agent Note: Device, transfer, and conversation controls stay where they are used

Status: implemented

English | [中文](2026-10-23-device-transfer-chat-ux.zh.md)

## Problem

The app exposed the facts and actions that make a local transfer useful, but it
did not always put them where a user could find them.

The Devices surface described the listener without saying which address a peer
should use. A new identity was named `unamed device`, even though the operating
system already knew the machine's host name. The Settings surface repeated the
same self-description, and its two storage locations were drawn differently:
the identity path was a paragraph of text while the incoming folder was an
editable field.

Other gaps were concentrated in the workflows people repeat. The update
interval control clipped on a narrow Android window. A completed file transfer
had no direct way to open its containing folder. A message could be unread
without the taskbar showing anything when the window was hidden. The
conversation list had no search, and an open conversation had no deliberate
way to clear its history. Finally, Android could check for and download an
update, but the About surface had no operation that handed the checked APK to
the system installer.

## Decision

**Identity is visible and starts from the host.** The Devices self card shows
every non-loopback IPv4 address above the listening line, separated by ` · `;
when enumeration fails it says that the address is unavailable. The same card
continues to own the machine's alias, fingerprint, platform, group, sessions,
and listener facts.

`loadOrGenerateLocalProfile` uses `Platform.localHostname` for a newly minted
profile. It migrates a stored `unamed device` alias once, and only while the
host name is usable. Any other stored alias is treated as a user decision and
is not replaced by a later operating-system rename.

**Settings has one copy of each fact.** The duplicate self card is gone. The
remaining storage section has two fields of the same shape: the identity file
is read-only with a lock, and the incoming folder is editable with a folder
button. The identity field can still be selected and copied, but it cannot be
edited in place.

**The update interval scrolls instead of clipping.** The four choices remain a
`SegmentedButton`, inside a horizontal `SingleChildScrollView`. This preserves
the existing control and selected state while giving a 360-pixel Android window
the width it needs.

**A completed transfer offers its folder directly.** The card shows a
`folder_open_outlined` button only when the transfer completed and its path can
be revealed. The existing context menu remains, so the icon is an additional
shortcut rather than a replacement.

**Unread is a window state, not another in-app badge.** `LocalTransferController`
exposes `totalUnread`; `HomeShell` combines it with the native window activity
stream and calls the `HostShell.setUnread` seam. Windows draws a red taskbar
overlay through `ITaskbarList3`, and clears it on `WM_ACTIVATE` before Dart has
to make a round trip. Dart also tracks the same activation fact so the two
sides cannot disagree about whether the window is being watched.

**Conversation search filters the list, not the history.** The search field
matches the peer's displayed name, message text, and attachment names,
case-insensitively. A matching message becomes the row preview, so the result
shows why it matched. An empty search keeps the normal list; a non-empty search
with no matches gets a dedicated empty state.

**Clearing a conversation is deliberate and local.** The three-dot menu is
shared by the compact and full conversation headers. It keeps the existing
trust action and adds Clear chat history, which asks for confirmation. Clearing
removes non-clipboard messages for that peer, forgets the read watermark, and
dismisses in-flight conversation transfers so a late completion cannot
resurrect them. Clipboard history is separate and is not cleared.

**Android updates end at the system installer.** `PlatformUpdateInstaller`
now has an Android path: it selects the release APK, requires the published
SHA-256, fetches it into the app-private `update` folder, verifies it, and calls
the Android method channel. The runner exposes that folder through a
non-exported `FileProvider`, checks `canRequestPackageInstalls()`, opens the
per-app unknown-apps setting when permission is missing, and otherwise starts
the package installer with a read grant. The About page changes its wording
and error messages for Android instead of promising a process restart.

## Alternatives considered

**Guess one local address, or advertise only the address used by the listener.**
Rejected: one machine can have Wi-Fi, Ethernet, and VPN addresses, and guessing
which one a peer can route to would turn a missing fact into a wrong one. The
card lists what the operating system reports.

**Always overwrite the alias from the host name on every start.** Rejected: a
name the user entered is a decision. Overwriting it because the machine was
renamed would silently change how the Device appears to every peer. Only the
old generated placeholder is migrated.

**Keep the duplicate self card in Settings for discoverability.** Rejected:
both cards would compete for the same facts and could drift. The Devices
surface is the place where the user needs identity and listener state; Settings
keeps only storage and application settings.

**Render the identity path as a plain fact line and style only the editable
folder as a field.** Rejected: the user is comparing two locations, so equal
shapes make the comparison easier. A lock states the difference without making
the identity path look like a different class of information.

**Wrap the interval choices or replace them with a dropdown on Android.**
Rejected: wrapping splits one control across lines and a dropdown hides the
available choices. Horizontal scrolling keeps the segmented control intact.

**Make the whole completed card open the folder.** Rejected: the card also
carries selection and details, and a large click target would make the
destructive or menu actions easier to hit by accident. A dedicated trailing
icon is direct and unambiguous.

**Keep the unread marker entirely in Flutter.** Rejected: a widget cannot
change the native taskbar icon while the window is hidden. The controller
still owns the count; the host owns the presentation.

**Clear only messages currently visible in the conversation.** Rejected: the
conversation is backed by persisted history, so a UI-only clear would make old
messages reappear on the next load. The persisted non-clipboard records and
the read watermark are removed together.

**Open the downloaded APK through a browser or an ordinary file URL.**
Rejected: Android requires a content URI grant for the system installer, and a
plain file URI fails under the platform's file URI restrictions. The
FileProvider and native channel are the supported path.

## Consequences

- The Devices surface tells a user what to type on another machine, including
  multiple interfaces, and degrades to an explicit unavailable state.
- New identities are recognizable without a first rename. Existing generated
  identities are migrated once; custom names are stable.
- Settings has less duplication and visually comparable storage locations.
- The update interval remains usable at narrow Android widths.
- Completed transfers take one tap to reach their folder.
- Windows can signal unread messages while hidden and clears the signal as
  soon as the user activates the window.
- Conversation search can find a message or attachment that is no longer the
  newest item in a row.
- Clearing a conversation cannot be undone and does not claim to delete files
  on disk or clipboard entries.
- Android update installation depends on the user granting unknown-apps
  permission and on the system installer being available. Both failures have
  explicit, actionable messages.
- `test/` covers the pure profile, reading, controller, and installer behavior.
  `test_flutter/ui/pages_test.dart`, `about_page_test.dart`, and
  `unread_badge_test.dart` cover the surfaces and the taskbar seam. Android
  method-channel names and the FileProvider contract are checked by the
  platform bridge tests.

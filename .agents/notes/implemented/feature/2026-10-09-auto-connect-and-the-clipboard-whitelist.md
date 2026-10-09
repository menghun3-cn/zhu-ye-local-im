# Agent Note: auto-connect, and the clipboard whitelist

Status: implemented

## Problem

Six complaints arrived from using the packaged Windows build on two machines,
and they turned out to be one problem about consent and three about surfaces.

**A Device that could not be dialled was the one that had to be.** Clicking
Connect from one machine to the other failed with `Connection timed out`, while
the same click in the opposite direction connected at once. Nothing in the
code could fix that: the failing side's inbound port was unreachable and even
ICMP was dropped, so its firewall was refusing the connection. What the app
*could* fix was not needing that direction at all — two Devices that have
already agreed to share an Owner Group, and that can each see the other on the
LAN, have no reason to wait for a person to click.

**Being paired was reading as permission to read the clipboard.** The Owner
Group was the only gate on Clipboard Mirroring, so admitting a Device for the
purpose of sending it a file also handed it every copy made on this machine
from then on. That is not what a user believes when they tap "pair".

**Three surfaces were describing the same thing in the wrong place.** The
Transfers menu listed text messages alongside files, though a text message is a
conversation and the menu could not show its context. A text bubble carried a
`text · completed` line, which is transfer bookkeeping over a thing that is not
a transfer. The Conversations destination in the navigation rail had no icon,
and a nameless peer in the conversation list was labelled `Unnamed device` — a
placeholder that tells two nameless Devices apart not at all.

## Decision

**A discovered peer in the Owner Group is connected to automatically.** A new
listener on `PeerRegistry.changes` calls `_autoConnectPeers`, which dials any
peer that is in `profile.group`, is not already wired, and is not already being
dialled. Both ends do this, so the two dials race, and the loser is refused by
the Session layer for a Session that already exists — which is the race
resolving the good way, not a failure. An unpaired Device is never dialled:
discovery must not be a way to join without being asked, and the Pairing flow
is what collects that consent.

The automatic connect is deliberately quieter than the button: three attempts,
400 ms apart, then silence. The button stays on the row for the cases where a
person wants to try again, and a firewall is not worth a notice every time the
app starts.

**The clipboard gains a fourth gate: a sharing whitelist.** `ClipboardMirror`
now checks the Owner Group, then the whitelist, then the capability, then the
origin tag. The whitelist is a set of Fingerprints persisted on
`DeviceProfile.clipboardPeers`, **empty by default**, and it is checked in both
directions: an entry leaves only for a peer on this Device's list, and an entry
is applied only when its origin is on it. Two Devices therefore share a
clipboard when each has added the other, and never otherwise. The Clipboard
surface renders the list as checkboxes over the paired peers, so the decision
has a place to be made; `setClipboardPeer` writes the profile *and* updates the
running mirror, because a setter that touched only one would make the switch
lie about itself until the next restart.

**Transfers is for files.** `TransfersPage` filters `controller.transfers` to
`PayloadKind.file`. Text lives in the conversation it was said in, and a
clipboard entry is mirrored rather than moved; both travel the same machinery,
both appear in the controller's list, and both are filtered out here so the menu
does not restate what two other surfaces already show, minus the context.

**A text bubble carries no status line.** `MessageBubble` draws the
`kind · state` row only for a non-text kind. A chat bubble says what it says,
and its direction is already the side of the pane it sits on; the `text ·
completed` line was transfer bookkeeping applied to something that is not a
transfer. A file keeps the row, because there it is the receipt the user reads.

**A nameless peer is named by its Fingerprint, not its address.** This reverses
the order set by `2026-10-08-a-nameless-peer-shows-its-address.md`:
`PeerView.displayName` is `alias ?? fingerprint.short()` again, with
`DeviceDescriptor.fallbackAlias` treated as no name rather than as one.
`PeerView.hasRealAlias` distinguishes the two, and `describePeerFacts` uses it.
The address is a fact about *where* a Device is, it is a different fact from
*which* Device it is, and every surface that shows the name shows the address
beside it in the subtitle — so the fallback no longer has to carry it, and two
nameless Devices are told apart by something neither of them chose.

## Alternatives considered

**Fix the dialling direction instead of connecting automatically.** There was
nothing to fix: the refusal was a firewall on the peer's side, and the app's
error copy already said so. Auto-connect is what makes the user's problem go
away, and the Manual Address path still exists for a network that blocks
discovery.

**Seed the clipboard whitelist with the Owner Group on pairing.** This is what
the previous behaviour effectively did, and it is what the request asked to
stop. The wording — "only the Devices added in the Clipboard surface may share"
— is a security requirement, and granting on pairing would rebuild the same
default-allow under a new name.

**Key the whitelist on the Owner Group and a mode, rather than a per-peer
list.** Coarser and cheaper, but it cannot express "this laptop yes, that one
no", which is the decision a user actually makes.

**Give the Conversations destination a different icon.** The icon was never
wrong: `Icons.forum_outlined` is what the code asked for, and every committed
version with the destination used it. What was wrong was the font. See the
consequences below.

**Leave text in the Transfers menu and only filter the empty state.** A menu
that lists a thing the user cannot act on from it — there is no conversation to
open from a Transfers row — is worse than one that omits it.

## Consequences

**The packaged build's Material Icons font is stale and tree-shaken, and the
fix is to invalidate the assets step — not to clean.** The shipped
`data/flutter_assets/fonts/MaterialIcons-Regular.otf` is 4848 bytes with 36
glyphs, and every icon introduced by the Conversations work is missing from it
(`forum`, `forum_outlined`, `notes`, `send`, `attach_file`,
`description_outlined`), while every pre-existing one survived. The font's
mtime predates that work by eight days: `flutter build windows --release` is
incremental, and the icon tree-shaker had not re-run. The code was never at
fault — the glyphs were simply never cut into the font. The first instinct,
`flutter clean`, does not work on this machine: the sandbox's safe-delete
policy refuses bulk deletions, the tool prints "Failed to remove ...\build"
and still exits 0, and the stale font survives untouched. What does work is
touching `pubspec.yaml` — the assets step's cache key includes it, so its
mtime alone forces the step, and the tree-shaker with it. The portable-package
script now touches the file before every build, and its zip verification
parses the font's cmap and fails when any required glyph is missing (a size
threshold cannot tell the good 5404-byte font from the bad 4848-byte one).

**Auto-connect changes what a test can assume.** A paired peer no longer sits
in a "found but not connected" state, so the tests that asserted one — and the
helpers that dialled by hand — had to tolerate a Session that already exists.
Two shapes of "already connected" come back, and which one depends on which
end won the race: `AppStateException` when the controller checked before
dialling, `HandshakeException` when the LinkManager found the Session already
established. `connect`, `connectDevices` and `openTab` all had to learn that,
and the last of them also had to wait out a Pairing question that was still
fading, because a modal barrier swallows a tap aimed at the rail and reports it
as a hit-test failure about coordinates.

**A fourth gate is one more thing to remember when adding a caller.** The
whitelist is read at construction from the profile and re-read wherever the
profile changes; anything that builds a `ClipboardMirror` outside
`LocalTransferController.start` starts with an empty one, which is the safe
reading but a silent one.

**The whitelist is per Device, so it is not symmetric by construction.** Two
Devices share a clipboard only when each has added the other. This is the
intended reading of "consent", and it means a user who ticks one box and not
the other gets silence rather than a partial transfer.

## Testing

`test/clipboard/clipboard_mirror_test.dart` grows a "the sharing whitelist"
group: nothing mirrors while it is empty, an entry flows once a peer is added,
a peer taken off it goes quiet without its Session being dropped, and an
inbound entry from a peer not on it is refused with `whitelist` in the notice.
Every older test in that file now asks for `allowEveryoneInGroup`, so a passing
assertion about the group gate cannot be an empty whitelist's doing.

`test/app/app_controller_test.dart` adds "connecting to a peer as soon as it is
discovered" — both Devices get a Session with nobody asking, and an unpaired
peer gets none — and "the clipboard-sharing whitelist" — nothing travels until
both sides have added each other.

`test/profile/device_profile_test.dart` pins the round trip, the default of
empty, and that a non-string entry is rejected rather than ignored.

`test_flutter/ui/pages_test.dart` pins the text bubble carrying no status line,
the Clipboard surface listing the group with every box clear, and a nameless
Device being listed by Fingerprint with the placeholder never reaching a screen.
`test_flutter/e2e/two_window_e2e_test.dart` ticks a real checkbox through a real
window before a real copy crosses a real socket.

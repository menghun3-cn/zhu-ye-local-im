# Agent Note: The conversation looks like WeChat

Status: implemented

English | [中文](2026-10-09-the-conversation-looks-like-wechat.zh.md)

## Problem

The conversation worked and looked like a form.

A message was a flat grey rectangle with the body text and, underneath it, a
line reading "text · sent". Both sides of the conversation used the same
rectangle, so the only thing that said who had spoken was which edge of the
column it hugged. There was no avatar, no tail, no bubble, no brand colour
anywhere in the product — the theme came from
`ColorScheme.fromSeed(seedColor: Colors.deepPurple)`, which is a Material
default that has nothing to do with this application. The composer was a
`TextField` and an icon button with no grouping, so there was no visual answer
to "where do I type" versus "what do I press".

Sending was also narrower than the thing being sent. A file could be sent, but
a picture could not, and nothing could be dragged onto the window. Picking a
file went through a dialog of our own making that asked for a path in a text
field — which is a worse file picker than the one every desktop already has,
and it made the common case (attaching a photo somebody just took) impossible.
A user who dragged a screenshot onto the window got nothing at all, because
Flutter's own `DragTarget` never sees a drop that comes from outside the
application.

## Decision

The conversation surfaces are brought to parity with WeChat, and the product
gets the two ways of sending an image a desktop user reaches for first.

### One place holds the visual language

`lib/ui/wechat/theme.dart` defines `class WeChat`: a private const constructor
holding every colour, size and metric the conversation surfaces use, and
`static ThemeData theme()` that builds the application's `ThemeData` from an
explicit `ColorScheme.light(primary: brand, …)`.

Explicit rather than seeded, and this is the substance of the decision.
`ColorScheme.fromSeed` derives a whole palette from one colour by an algorithm
that is free to pick a different tone than the reference — which is exactly what
"match WeChat's colours" cannot tolerate. Every token that matters is written
down: brand green `#07C160`, outgoing bubble `#95EC69`, incoming bubble white,
bubble text `#1A1A1A`, page `#EDEDED`, sidebar `#F7F7F7`, divider `#E7E7E7`,
secondary text `#888`, selected row `#C9C9C9`, hover `#E9E9E9`, badge
`#FA5151`; body 15 over line-height 1.4, preview 13, meta 12, avatars 40,
bubble radius 6, bubble padding 12×9, bubble max width 60%, message gap 16,
list width 250, row height 64.

Both `MaterialApp`s — the live one and `StartupFailureApp` — take
`WeChat.theme()`. The failure window is styled the same way on purpose: a
window that fails to start is the one place a user is most likely to be looking
at the app for the first time, and handing them Material purple there would be
the app introducing itself wrong.

### A bubble is a bubble on both sides, with a face and a tail

`lib/ui/wechat/bubble.dart` holds `Avatar` and `MessageBubbleShape`. The
outgoing bubble is the brand green with a tail on the right; the incoming one is
white with a tail on the left; both carry the same near-black body, radius and
padding. The tail is a small square rotated 45° and tucked behind the bubble's
corner (`Transform.rotate(angle: 0.785398)`, offset by `_tail * 0.7`) rather
than a `CustomPainter` triangle: the rotation is one transform the engine
already knows how to antialias, while a hand-built triangle path has to get its
own edge joins right and shows a seam against the bubble at the corner.

The receipt line — "kind · state" — is now drawn **only for files**. A text
message has nothing to report: it is accepted on arrival, it has no sink and no
digest, and a line under every bubble saying "text · sent" is noise that is
the same on every single one of them. A file is the kind that can be refused,
can fail, and can be waiting on an answer, so a file is the kind whose state a
reader needs. `_showsReceipt` is `view.kind == PayloadKind.file`, and it is the
single predicate that decides this.

### An image is a payload kind, and the picture is the message

`PayloadKind` gained `image('image')`. This is additive on the wire and
deliberately so: an image travels exactly the way a file does — a digest in the
offer, bytes through a sink — so nothing in the engine branches on the kind, and
a receiver built before this change can still place the bytes correctly.
`wireProtocolVersion` was **not** bumped, because there is no message an old
peer would misread.

What the new kind changes is where the bytes are *shown*. `TransferView` gained
a nullable `localPath`, set for images only: the sender's own file once it has
been offered, and the receiver's landed copy once it has been written and
verified. An image bubble draws the picture at that path and opens a
tap-to-enlarge viewer; with no path yet — an offer that has not been answered —
it falls back to the same name row a file uses, because there is nothing else
honest to draw.

### The picker is a seam, because a native dialog cannot be tested

`file_selector` opens the operating system's own dialog, and `desktop_drop`
bridges `WM_DROPFILES` into Flutter's drag system. Both are the right choice for
the user and both are undriveable from a widget test: a native dialog runs
outside Flutter's event loop and never returns to a `testWidgets` body.

So the picker is resolved through `lib/ui/pickers.dart`:
`abstract interface class FilePicker`, `final class SystemPicker` (the only
place that calls `openFiles`/`openFile`), and a static substitution point
`PickerResolution.picker` with `reset()`. Tests install a `ScriptedPicker` and
drive the real button, which means the classification of what came back, the
offer, the wire and the landing are all still on the tested path — the only
thing replaced is the dialog itself.

### One drop target, and it says what it will do

The history is wrapped in a `DropTarget`, enabled only when there is a peer to
send to. A drag that enters tints the area and shows a hint; the drop is
classified into images and other files and each is sent as what it is. The
classification lives in `pickers.dart` next to the picker rather than in the
page, so "what counts as an image" is answered in one place for both the dialog
and the drop.

## Alternatives considered

**Keep the seeded colour scheme and override the handful of colours that
look wrong.** Rejected: the derived palette is not just a primary colour. It is
every surface, outline, container tone and disabled state, and each one is a
place the app can drift from the reference. Naming the tokens means the
comparison against WeChat is a comparison of written-down values, which is a
thing a reviewer can actually check.

**Draw the tail with a `CustomPainter` triangle.** Rejected: a triangle path has
to be joined to the bubble's rounded corner by hand, and the join shows a seam
at the corner because two antialiased edges meet there. The rotated square goes
behind the bubble, so the bubble's own rounded edge is what the eye sees.

**Keep the in-app path dialog for sending a file.** Rejected: the operating
system's picker is better than ours in every way a file picker can be — it
remembers where the user last was, it browses, it shows thumbnails, it filters
by type. The dialog existed because the product had no way to reach the real
one, not because asking for a path was good.

**Put the picker behind the controller instead of the UI.** Rejected: the
controller is the thing that does not know what a dialog is, and threading a
file-picking dependency through it would make the transfer engine's tests carry
a UI concern. The seam belongs where the dialog is opened.

**Send an image as a `file` and let the UI decide whether to draw a
thumbnail.** Rejected: the kind is what the receiving side needs in order to
know what it has. A receiver that gets `file` has to guess from the extension,
and a guess that disagrees with the sender is a picture shown as a filename. The
enum is the place the answer is written down once.

**Bump `wireProtocolVersion` for the new kind.** Rejected: version bumps are for
changes an old peer would misread, and this one is not that. An old receiver
handles an image exactly as well as a receiver that knows the kind — it receives
bytes against a digest. Bumping would refuse a peer that would have worked,
which turns a display difference into a connectivity failure.

## Consequences

- `lib/ui/wechat/theme.dart`, `lib/ui/wechat/bubble.dart` and
  `lib/ui/wechat/image_bubble.dart` are new. The conversation's colours, sizes
  and shapes now come from one class rather than from `Theme.of(context)` at
  each call site.
- `PayloadKind.image` is a new enum member, which every exhaustive `switch` over
  the kind had to answer for: `iconForKind` and `labelForKind` in
  `lib/ui/labels.dart`, and the kind branch in
  `lib/core/transfer/transfer_limits.dart`. The branches that are an `if`
  rather than a `switch` — `transfer_engine.dart`, `conversation_view.dart`,
  `transfers_page.dart`, `app_controller.dart`, `messages.dart` — were checked
  by hand, because the compiler does not point at them.
- `TransferEngine.sendFiles` is now a thin wrapper over a private
  `_sendStreams(PayloadKind, items)`, and `sendImages` is the same call with the
  other kind. A new kind that travels like a file costs one enum member and one
  line, not a second copy of the digest and offer logic.
- `_Tracked` in `app_controller.dart` carries a mutable `localPath`, written
  when an outgoing image is sent and after an incoming one is written and
  verified. `acceptInto` records the path it landed at, which is what makes the
  receiver's bubble able to show the picture it just received.
- `ConversationComposer` became a `StatefulWidget` holding a `FocusNode`, and
  re-requests focus after a send. Enter sends and Shift+Enter breaks the line,
  through a `Shortcuts`/`Actions` pair around the field rather than a key
  handler on the field itself — so the behaviour is the same wherever the caret
  happens to be.
- Buttons that were restyled are `TextButton`s with explicit `ButtonStyle`s, not
  `Material` plus `InkWell`. A hand-rolled button loses its focus ring, its
  keyboard activation and its tooltip semantics, and the widget tests that
  could no longer find the send button were reporting a real regression rather
  than a test that needed updating.
- `file_selector` and `desktop_drop` are new dependencies, and `pubspec.yaml`
  records why: the pickers are the operating system's own, and an external drop
  arrives as `WM_DROPFILES` and never becomes a Flutter drag.
- The widget suite gained a `ScriptedPicker` and finders keyed on the row and
  the send button by name. The conversation list row is no longer a `ListTile`,
  so the helpers that reached a peer through one were rewired to a
  `ConversationRow` carrying its peer's name.

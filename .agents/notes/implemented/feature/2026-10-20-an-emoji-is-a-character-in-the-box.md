# Agent Note: An emoji is a character in the box

Status: implemented

English | [中文](2026-10-20-an-emoji-is-a-character-in-the-box.zh.md)

## Problem

The emoji picker sent a face the moment it was tapped.

That was a decision, not an accident: the note that introduced the feature
([emoji in conversations](2026-10-19-emoji-in-conversations.md)) said so
outright — *"Picking a face sends it immediately as its own message — it is
not staged into the box, because a face is a complete message the way a sent
file is"* — and it recorded the alternative as rejected: *"Stage the face
into the text box and let 发送 release it. Rejected: a face typed into the box
reads as text a person has to finish sending."*

The argument was that WeChat sends the face immediately, and that "tap, face
appears" is the behavior users know.

It is also what made the feature awkward to use. A face is a character, and
the one place a character belongs is the text box. As a message of its own, a
face could not be part of a sentence: a person who wanted to write 到了
followed by a face had to send twice, and the two halves arrived as two
separate bubbles — the first one a word, the second one a sticker-sized
face. The feature offered a palette of faces and the sending of a face, and
not the thing a person actually wanted, which was the face *in the sentence*
they were writing.

There was a second, smaller thing in the same area. The picker was drawn as
a disabled menu item, which is the only way to put a panel in a Material
popup — an enabled item pops the menu the moment it is tapped, and a panel
is not a choice. A disabled item is drawn dimmed: its text takes the
disabled colour and its icons lose 38% of their opacity. The faces therefore
sat behind a grey veil, and the panel read as a sheet of frosted glass laid
over them rather than as the faces themselves.

## Decision

**A picked face goes into the composer, and leaves with the message.** The
picker inserts the face at the caret, by the field's own rule — a selection
is replaced, and the caret lands after what was inserted — so a face lands
where the person was writing rather than at the end of the line.

The face is then part of the text, and the message travels as
`PayloadKind.text`. There is no separate "send a face" path any more.

**The wire kind stays.** `PayloadKind.emoji` remains on the wire, and a
bubble still draws a face of that kind large (`emojiBubbleFontSize`). Two
released versions send it: `v0.1.10` and `v0.1.11` both put a face in a
payload of its own, and a peer running either of them still sends that. A
build that dropped the kind would draw a face that another machine sent as a
sticker-sized face as an ordinary line of words — and a face is the one
thing in a message where the difference in size is the whole point.

So the kind is kept for reading, and the composer no longer produces it. What
replaced it is a decision about *writing*, not about the format.

**The panel is drawn as a panel.** The picker is a popup entry of its own
(`_EmojiPanelEntry`) rather than a `PopupMenuItem`. That is what removes the
veil: there is no disabled menu item anywhere in it, so nothing in it takes
the disabled colour or the dimmed icon opacity. The panel also brings its own
surface, so the faces sit on a clean sheet rather than on the menu's tinted
item background.

The entry is not a choice, so it does not close the menu when the panel is
tapped. The panel closes itself, by popping the route, once a face has been
picked — which is the same thing it did before.

**The recents are still updated on the tap.** Nothing about that changed: the
strip is the fast path to the faces a person actually uses, and it moves the
chosen face to the front on the same tap that inserts it.

## Alternatives considered

**Keep the face as a message of its own and let the user write around it.**
Rejected: it is what the previous note decided, and it is what the request
that produced this note was about. The reasoning behind it — that a face
typed into a box reads as text somebody has to finish sending — turns out to
describe the box's behaviour rather than the face's. A face in the box is
sent by the same 发送 that sends the words, and nobody has to think about
it.

**Send the face as its own payload but insert it into the box first.**
Rejected: it keeps the two-halves problem. The face would still arrive as
its own bubble rather than as part of the sentence it was written into.

**Draw the panel undimmed by keeping the menu item enabled and swallowing
the tap.** Rejected on the merits and on the mechanics. On the merits, an
enabled menu item is still a *choice* as far as the framework is concerned,
and it brings the menu's item padding, its highlight colour and its ink
styling along with it — the panel would still read as a menu entry with a
panel in it. On the mechanics, swallowing the tap means intercepting it
before the framework's own handler sees it, which is exactly the kind of
arrangement that breaks the next time the framework changes.

**Build the panel as an overlay instead of a popup.** Rejected: it means
owning the positioning, the clamping into the window, the dismissal on an
outside click, and the animation. `showMenu` already does all of that, and
the only thing it was getting wrong was the dimming — which a custom entry
fixes without giving any of it up.

**Keep `PayloadKind.emoji` off the wire entirely.** Rejected: see above.
`v0.1.10` and `v0.1.11` are out there and send it.

## Consequences

- **A face can be part of a sentence.** 到了😀 is one message and one
  bubble, and the face is drawn at the size of the words around it.
- **`PayloadKind.emoji` is now read-only in this application.** The engine
  and the controller still offer `sendEmoji`, and the kind still has a
  bubble, an icon, a label and a landing rule — all of it for the faces
  another build sends.
- **The picker is drawn plainly.** No disabled state anywhere in it, and the
  faces sit on the panel's own surface.
- **The wire format is unchanged.** A build that speaks the old behaviour
  and one that speaks the new one understand each other: the new one sends
  text where the old one sent a face, and both draw the other correctly.
- **The tests moved with the behaviour.** The composer tests assert that a
  picked face is in the box and that nothing went out; the two-window test
  asserts that the face travels as text, and a second one asserts that a
  face arriving as a payload of its own is still drawn large.

# Agent Note: A divider the user can drag

Status: implemented

English | [中文](2026-10-20-a-divider-the-user-can-drag.zh.md)

## Problem

The Conversations surface is a list on the left and a conversation on the right,
and the split between them was a fixed 300 pixels with a one-pixel line drawn
between the two panes. A user who reads mostly on the list side — a person
scanning who has twenty Devices and opens one occasionally — had no way to
give that space back. A user who reads mostly the conversation side had a
column narrower than the window they had.

There was a second, quieter problem, and it was the reason the split was
fixed in the first place. The bubble cap is a share of the chat area, so the
chat area's width decides how a message is drawn — and with a fixed list
width, the only way to change how a message is drawn was to resize the
*window*. A user who wanted wider messages had to make the whole application
wider, including the navigation rail and the conversation list, neither of
which was what they were asking about.

## Decision

**The line between the panes is a splitter the user can drag, and the chat
area's width is whatever the splitter leaves.**

- `PaneSplitter` (new, `lib/ui/wechat/splitter.dart`) replaces the
  `VerticalDivider` that stood between the list and the conversation.
- **The drawn line is one pixel and stays one pixel.** What the pointer is
  over is an 8-pixel band centred on it, because a one-pixel target cannot
  be reliably grabbed by a mouse. The wide part is the catchable area, not
  the visible thing: a messenger's conversation reads as one surface, and a
  wide visible divider would be a stripe through it.
- The splitter **announces itself by changing colour, not by growing** —
  a tint of the line's own colour on hover, the brand green while it is
  held. The cursor is `resizeColumn`, because a drag nobody knows about is
  a feature nobody finds.
- The list's width is held as a number (`_listWidth`), not as a share of the
  window: a list has a width a person can recognise — the same 300 pixels on
  every screen — and a share would make it wider on a wide screen for no
  reason the user asked for.
- **Every limit is applied in one place**, `_clampedListWidth`: the list's
  own floor (220), the list's own ceiling (480), and what the conversation
  still needs (320). The drag handler does not clamp. A clamp in the drag
  and a clamp at the draw site are two rules that can disagree, and a test
  that breaks one of them would then be testing the other.
- The **conversation is the one that gives way**. A list dragged to 480
  pixels in an 800-pixel window would leave the conversation 300 pixels of
  which the rail has already taken 84 — the messages would be a two-word
  column. The conversation is what this surface is *for*.
- The splitter is **not draggable when there is no room to give**: a window
  so narrow that the list is already down to the conversation's minimum has
  nothing left to hand over, and a splitter that moves nothing is a divider
  pretending to be something else.
- The user's choice survives a window that shrinks. `_listWidth` keeps what
  was dragged; the *drawn* width is what `_clampedListWidth` allows. A
  window that shrinks therefore gives the room back without throwing the
  choice away, and widening the window again gives the choice back.

The bubble cap needed no change for any of this, and that is the point of how
it was built. The cap is a share of the chat area, measured by the
conversation's own `LayoutBuilder`; the splitter changes the chat area's
width; so the cap follows the splitter without either knowing the other
exists.

## Alternatives considered

**A handle in the middle of the divider.** Rejected: a handle is a thing to
hunt for. The whole of the boundary is catchable, because the whole of it is
where a user would aim.

**Making the visible divider wider to match the hit area.** Rejected: the
width of the drawn line is a visual decision and the width of the hit area
is a usability one. Coupling them makes the interface stripey for the sake
of a target nobody can see.

**Letting the list be dragged to zero.** Rejected: a list one pixel wide is
not a list, and the user who did that wanted the *conversation* wider, not
the list gone. A floor of 220 keeps the list usable — a name and a preview —
and hands the rest to the conversation.

**Storing the width in the profile.** Rejected: not asked for, and it is
not a preference the user would want carried from one window to another. A
pane's width is a property of the window it is in.

**Letting the user drag the *conversation* wider than the window allows.**
Rejected: there is no room beyond the window, and the clamp that stops it
is the same clamp that stops the list from eating the conversation.

**Resetting the width when the window is resized.** Rejected: resizing a
window is not a request to forget a layout choice. The choice is kept and
the limits are re-applied, so a window that shrinks gives the room back and
a window that grows gives the choice back.

## Consequences

- The conversation list's width is now the user's to set, and the conversation
  column's width follows it.
- A long message re-wraps as the splitter moves, because the cap is a share
  of the chat area. This is the visible proof that the cap is tied to the
  chat and not to the window.
- The Conversations surface in a narrow window is unchanged: below 720
  logical pixels there is one pane at a time, and there is no splitter to
  drag.
- `test_flutter/ui/pane_splitter_test.dart` (new) pins four facts: the drag
  moves the list by the distance it was dragged, the list cannot go below
  its floor, the list cannot go above its ceiling, and the conversation
  never drops below the width it needs to be read — including in a window
  with only just enough room. Each was checked by breaking the clamp it
  belongs to and watching that one test fail.
- `test_flutter/ui/bubble_width_test.dart` gained a test that drags the
  splitter and asserts the bubble is still exactly the cap of the *new*
  chat area — the two decisions meeting.
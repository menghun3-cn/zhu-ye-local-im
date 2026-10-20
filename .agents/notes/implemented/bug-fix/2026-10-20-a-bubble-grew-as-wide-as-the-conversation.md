# Agent Note: A bubble grew as wide as the conversation

Status: implemented

English | [中文](2026-10-20-a-bubble-grew-as-wide-as-the-conversation.zh.md)

## Problem

`WeChat.bubbleMaxWidthFactor = 0.6` was written down, given a comment
explaining why a ratio beats a fixed pixel count, and then never used. Nothing
in the repository read it.

So the conversation drew a text bubble at whatever width its text wanted. A
short message hugged its words, which looked right; a long one ran to the
full width of the chat column, and on a wide window that meant a single line
of text stretched across most of the screen with a wide margin of empty
bubble on either side. The bubble was no longer a bubble in any useful sense
— it was a stripe.

The record said otherwise. The note that introduced the WeChat conversation
lists "bubble max width 60%" among the tokens the design is made of, so the
decision had been made and written down; the code simply never applied it. A
bubble that ignores the cap also has no floor: a one-character message draws
a bubble barely wider than the glyph, which reads as a speck rather than as
something somebody said.

## Decision

**A bubble is capped at 60% of the chat area and floored at a bubble's worth
of width.**

- `WeChat.bubbleMaxWidthFactor = 0.6` is applied, and `WeChat.bubbleMinWidth
  = 48` is added beside it. The floor is 48 because that is a bubble's
  smallest sensible body: 48 minus the 12 pixels of padding on each side
  leaves room for one character and for the rounded corner to read as one.
- The cap is a share of the **chat area** — the column the conversation is
  drawn in — and not of the space the text has left. The text's own space
  has already had the avatar taken out of it, so a cap taken from there would
  be narrower than WeChat's by the width of an avatar.
- The chat area is measured **once**, by the conversation, and the resulting
  cap is handed to every bubble in it. Each bubble measuring for itself would
  measure the message list's inner width instead — the list's own padding
  would then be part of the rule, and the cap would shift whenever the
  padding changed rather than whenever the window did.
- The measurement is a `LayoutBuilder` around the history, so the cap is
  re-read on every change of the chat area's width. Resizing the window — or
  dragging the divider between the conversation list and the conversation —
  moves the cap with the area rather than leaving it behind.
- `MessageBubbleShape` takes the cap as `maxWidth` and applies it as a
  `BoxConstraints` on the bubble, alongside the floor. The bubble grows
  downward when the text no longer fits on one line, which is what a message
  in a column is supposed to do.

The floor yields rather than fights the layout: `ConstrainedBox` enforces
its own constraints against the ones it is given, so a chat area too narrow
to hold a 48-pixel bubble gets a narrower bubble rather than an overflow.

## Alternatives considered

**A fixed pixel cap (500, say).** Rejected: the whole reason the token is a
ratio is that a number that reads well on one window is wrong on the next —
short in a 2560-pixel window, long in a 600-pixel one. This was the original
reason for `bubbleMaxWidthFactor` and it has not changed.

**Cap the text rather than the bubble.** Rejected: the cap belongs to the
whole bubble, because the bubble is what the reader sees. A text capped
inside an uncapped bubble would leave the same stripe of empty fill around
the words.

**Let the user drag a divider that sets the bubble width.** Rejected as
beyond the decision: the cap is a rule, not a preference, and a per-window
setting would have to be stored, restored and explained. The window's own
resize already moves the cap, which is what was asked for.

**Cap as a share of the whole window.** Rejected: the window also holds the
navigation rail and, in the Conversations surface, the conversation list.
Those are not the chat, and a bubble sized against them would be sized
against a number the reader never sees.

**No floor.** Rejected: a bubble around a single character is a dot. The
floor is what makes the smallest message look like the same object as the
largest one.

## Consequences

- A long message now wraps at 60% of the chat area instead of running across
  it, and the bubble grows taller instead of wider.
- Resizing the window re-computes the cap, so a bubble that fits a narrow
  column does not sprawl across a maximized one.
- The transfer bubble keeps its own measure. `transferBubbleMaxWidth` (280)
  and `transferBubbleMinWidth` (160) are unchanged, and the new cap is
  applied *outside* them: a file bubble is still drawn to the width its name
  takes, subject to the cap, and in a chat area wide enough for the cap not
  to bind, nothing about the file bubble changes.
- The picture message is still drawn without a bubble, and is still bounded
  by `imageMaxSide`. The cap is a rule about bubbles, and a picture is not
  one.
- `test_flutter/ui/bubble_width_test.dart` pins the three facts: a long
  message fills the cap exactly and wraps, a short one takes only the width
  its words take, and the cap moves when the window does. The width
  assertion is against the *chat area* rather than the window, so a cap
  taken from the wrong one would fail it.

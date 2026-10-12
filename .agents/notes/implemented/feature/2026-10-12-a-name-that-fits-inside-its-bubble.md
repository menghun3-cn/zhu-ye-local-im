# Agent Note: A file name that fits inside its bubble

Status: implemented

## Problem

A file bubble is drawn to a fixed width — measured from the name, floored at
`transferBubbleMinWidth` and capped at `transferBubbleMaxWidth` (280) — and the
name inside it was a `Text` with `maxLines: 1` and `TextOverflow.ellipsis`. Any
name wider than the cap was therefore cut down to a prefix plus `…`, and what
got thrown away was always the end: the extension, the version, the platform
tag. For the names this app actually moves — `…-windows-x64-portable.zip` — that
is precisely the half a user reads the bubble to find out.

The width itself was right and stays. A bubble that grew with its name would
stretch across the pane, and the progress bar inside it has no width of its own
to fall back on. What was wrong was spending the whole cap on *one* line, in a
block whose height cost nothing.

## Decision

**A name that does not fit on one line wraps, up to three.**

- `WeChat.transferNameMaxLines = 3`, taken as `maxLines` by both name `Text`s —
  the file block in `_body`, and the name beside the picture glyph in `_image`.
  `TextOverflow.ellipsis` stays, so a pathological name still stops.
- The name's style gains `height: WeChat.lineHeightBody`, the line height the
  message body already uses. One line grows by about 3px; two and three lines
  are readable rather than stacked.
- Nothing about the **measure** changed. `_transferBubbleWidth` still measures
  the name *unwrapped* and still clamps. That is not an oversight: the cap is
  what makes a long name wrap, so the one-line width is exactly what decides
  whether the cap applies at all. Measuring a wrapped height instead would be
  circular — the width would depend on where the lines break, and the breaks on
  the width.
- Because the width is still measured from the name, a name that *does* fit is
  still drawn on one line at its own width. Wrapping only ever adds lines to a
  name that had no room; it never adds a line's worth of slack to one that did.

The three lines are not a fourth measurement: they are what the cap already
implied. A name up to 18 half-width characters fits the capped width on one
line; three lines is the same cap carried downwards, and it covers every name
this app produces.

## Testing

`test_flutter/ui/transfer_bubble_test.dart`, which already owns the bubble's
width:

- New: "a name too long for the bubble wraps instead of losing its end". A
  `local-transfer-1.0.0-windows-x64-portable-full.zip` offer, pinning four
  things: `maxLines` is `transferNameMaxLines`, the overflow is still the
  ellipsis, the drawn width does not exceed the cap (wrapping must not widen the
  bubble), and the drawn height is more than one line (it really wrapped).
- Extended: the existing width test now also asserts that its five-character
  name is drawn on one line. A cap on its own cannot tell a short name from a
  long one; the measure is what does, and this is the assertion that would fail
  if the measure were ever replaced by the cap.

## Alternatives considered

**Raising the cap so more names fit on one line.** Rejected: it moves the
funnel rather than fixing it. Some name is always longer than any cap, and 280
is already about the width at which a file card stops reading as a file card.

**A wider cap for long names only.** Rejected: that is what the existing
measure already does, up to the cap. Past it there is no width left without
turning the bubble into a full-width row, which is the one thing this bubble was
built not to be — so lines are the only currency left.

**Scrolling or marquee text for the name.** Rejected: a name the user has to
chase is worse than one that is two lines tall. The tooltip already carries the
whole of it for a name too long even for three lines.

**Ellipsising from the middle (`…-portable.zip`).** Rejected: it is a rendering
the platform has no primitive for, and a name is not a path — cutting it in two
places makes it harder to read at a glance, not easier.

**Three lines for every name, always.** Rejected: that is the same mistake in
the other direction — a short name would carry two empty lines, and the bubble
would be the height of its worst case rather than of its content.

## Consequences

**Bought.** The end of a file name is legible again: the extension, the version,
the platform. A bubble that was already carrying a name, a size line, a bar and
two buttons grows by at most two lines of text.

**Given up.** Vertical compactness for very long names — a conversation with
several of them is taller than it was. Three lines is the ceiling, so the cost
is bounded and predictable.

**No user-visible string changed**, so the packaging probes needed no edit; the
probe count stays at 29.

**The new test has never been run.** `flutter test` does not start on this
machine (`CreateFile failed 231` on any piped `Process.start`); the run is owed
on a machine where the toolchain works, like the bubble tests beside it.

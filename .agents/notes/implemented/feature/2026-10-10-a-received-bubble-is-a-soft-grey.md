# Agent Note: a received bubble is a soft grey, and its track is the bubble's own ink

Status: implemented

## Problem

The repaint (`2026-10-10-two-greens-one-scale-and-a-white-received-bubble.md`) moved the received
bubble onto the conversation board's own white and gave it a hairline so that it could be seen at
all. That is a coherent pair of numbers and an incoherent thing to look at: on the light page the
board is white, so a received message is a white rectangle outlined in `#E7E9EE`. Read in a window
rather than in a swatch sheet, a message with no fill of its own reads as an empty box that has
been drawn around some text, not as a thing that arrived.

The earlier note's objection to a grey bubble was an objection to *the page-background grey*, which
was the alias the bubble used to wear. That value does read as a disabled control. A grey that is
merely a step below the panel does not, and the two had been treated as one option.

Changing the fill exposed a second problem that was already there. The bar inside a transfer bubble
draws its track in `surfaceSunken`, and in the light palette that is now *exactly* what a received
bubble's fill is, so the track would vanish inside one. Checking the dark palette for the same
mistake found it: `surfaceSunken` (`#20252E`) and `bubbleIn` (`#21262F`) are one step apart, so on
the dark page the track has been invisible inside a received bubble since the bar was repainted.
Nothing caught it, because the assertion the suites could make was about the *widget* naming a
token, not about that token differing from the surface it lands on.

## Decision

**A received bubble is the panel's sunken step.** `bubbleIn` in the light palette is `#F0F1F4`, the
value `surfaceSunken` and `listHover` already carry, so the role reads as "one step below the
panel" and the board keeps its white. The hairline stays, but it is no longer load-bearing. What
the two themes share is the job rather than the direction: on white paper the bubble is a step
darker than the board, on dark paper a step lighter.

**A progress track is the bubble's own ink, thinned.** `WeChat.progressTrackAlpha` (0.16) times
`bubbleText` or `bubbleOutText`, whichever the bubble's direction calls for. A track has to read on
four fills — `bubbleIn` and `bubbleOut` in each theme — and no single palette colour sits a fixed
distance from all four. Derived from the ink, the track is a fixed distance from whatever the
bubble happens to be, in every combination, and that is the property the new test pins.

**The bare image's track keeps `surfaceSunken`.** It is drawn on the conversation board rather than
inside a bubble, and on the board that is the right step. The two tracks therefore differ, and
deliberately: the rule is that a track must be a step off whatever it is drawn on, not that both
call sites name one colour.

## Alternatives considered

**Keep the white bubble and rely on the hairline.** Rejected: that is what shipped, and what it
looks like in a window is an outlined empty box. A one-pixel line is enough to separate two
adjacent fills in a table; it is not enough to make a message read as a message.

**Use the page-background grey, `#F4F5F7`.** Rejected: that is the alias the previous note rejected,
and re-taking it would restore the very relationship the previous test guarded against — bubble and
page sharing one value. It would also put the bubble within a step of `pageBackground`, which is
the colour of every *other* page in the app.

**Use `divider` for the track.** Rejected: it is a plausible fixed colour and it is not a fixed
distance. Over the light bubble it is about ΔRGB 8 and over the dark bubble about 6 — visible if
looked for, invisible in motion — while the same value is strong over both greens. It would have
been right for two of the four fills.

**Give the bubble a grey of its own, some value that is neither.** Rejected: what makes a palette a
palette is that its values are reused. `surfaceSunken` already means "one step below the panel",
which is exactly what this is; inventing a fourth near-white hex to say the same thing is how a
palette stops being one.

## Consequences

**Everything downstream of `bubbleIn` re-paints, and nothing else does.** The bubble's fill, the
hairline's job, and the in-bubble track's colour. No layout, no size, no string, no wire change.

**Two assertions in `shell_test.dart` had to be reversed.** One pinned `bubbleIn ==
conversationBackground`; the other pinned the light bubble's luminance *equalling* the board's.
Both now pin the opposite relationship — different fills, in the direction each theme needs — and
the first also pins that the bubble is not `pageBackground`, so the rejected alias cannot come back
unnoticed.

**A test now guards the track rather than the token.** It composites the ink at
`progressTrackAlpha` over each of the four fills and requires a luminance difference, so the
assertion is about the result and would survive a change to either the ink or the alpha. The
dark-theme defect it would have caught had been shipping.

**Whether `#F0F1F4` is grey enough is an eye question.** As with the repaint, neither the analyser
nor the suites can answer it; if the answer is no, it is one token.

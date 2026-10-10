# Agent Note: two greens, one scale, and a white received bubble

Status: implemented

## Problem

The application was dressed as the WeChat desktop client, token for token. That was
a deliberate choice and it is now retired: on 2026-10-10 the look was re-decided as a
Material 3 skeleton with a restrained, Linear/Vercel flavoured scale — hairline
dividers, one accent colour, weak shadows, and a type scale in which a title is
visibly a size above its body. A high-fidelity web draft was produced, iterated four
times against review, and signed off. This is the first PR of that landing, and it is
the *repaint*: the token layer, plus the one component whose paint the tokens cannot
express.

Four things were wrong with what the tokens said, and they are worth naming
separately because they are four different mistakes:

**One green was doing two contradictory jobs.** `brand` (`#07C160`) is right as a
fill and as an identity mark, but it was also the background of every filled button,
which carries white text — and white on `#07C160` is 2.4:1, well under AA. A ratio is
a property of a *pair*, so no amount of adjusting the text fixes it.

**The received bubble wore the background's grey.** It had been arranged the other way
round from WeChat — a white board with a grey bubble — and the grey read as
*disabled*: a fill that says "this is not available" on top of a message that is
simply there.

**There was no type hierarchy.** Body and a conversation title were both 15. A
heading that is the same size as its paragraph is not a heading.

**Nothing had depth.** Cards were flush with no shadow and an 8px corner, controls
4px, and every pressable surface therefore looked like the one next to it.

## Decision

**A green to identify, a green to press.** `brand` (`#07C160`) keeps its value and its
job — fills, marks, the progress bar. `brandStrong` (`#0A7E43`) is the action colour:
filled buttons, links, the selected icon and label on the navigation rail, and the
`ColorScheme.primary` slot Material reaches for. White on it is 5.2:1.
`brandSoft` (`#E8F8EF`) is the selected background and the focus glow, `onBrand`
(`#06291A`) is the ink that sits on a brand fill, and `brandLine` (`#BFE9D2`) is its
border. The same split runs through every control theme: switch, checkbox and radio
all moved from `brand` to `brandStrong`, because a control you can press wears the
same green as a button.

**A received bubble is white, and its line is what makes it visible.** `bubbleIn` went
from the page-background grey to `#FFFFFF`, and `MessageBubbleShape` draws a one-pixel
`divider` border on an incoming bubble to match. This is the one change the token
layer could not make on its own: white on the board's white with no line is a message
nobody can see. It also retires a documented invariant — see the test note below.

**The tail is gone; a tucked corner says the same thing.** The bubble had a rotated
square behind its corner, which is cheap and antialiases well but reads as a cartoon
speech balloon. `MessageBubbleShape` now rounds three corners at `bubbleRadius` (14)
and tucks the corner beside the avatar to `bubbleTuckRadius` (3). The avatar left
`bubbleRadius` for a token of its own, `avatarRadius` (10), so that a bubble and the
square initial beside it stop sharing one number.

**One scale, in two places.** The type scale dropped to body 14, title 16, label and
preview 13, meta 12 — a title is now two steps above a paragraph. The radii went up
one step across the board: `controlRadius` 4→8, `cardRadius` 8→14, `imageRadius` 4→8.
Cards took one step of shadow (`elevation: 1`) and dialogs three, so a card reads as a
card and a modal reads as above one.

**`badge` is gone; `danger` (`#C33B3B`) replaces it.** One name was covering two
ideas — an unread count and an error — and the name described neither.

**An outgoing bubble's text is `bubbleOutText` (`#17240F`), not `bubbleText`.** Text on
a tinted fill wants that tint's own dark; a neutral near-black on pale green reads
faintly blue.

## Alternatives considered

**Keep one green and lighten the button's text.** Rejected: the contrast ratio belongs
to the pair, so the only ways out are a darker fill or a dark label, and a dark label
on a green button reads as a disabled control.

**Keep the grey received bubble and skip the border.** Rejected: the grey is exactly
what made it look unavailable, and the design's whole structural language is a
hairline. Adding the line while keeping the grey would have been the worst of both.

**Ship the entire redesign — repaint, layout and dark mode — as one PR.** Rejected on
the project's "one PR, one thing": the repaint is verifiable by itself (analyse plus
the two test suites) and touches a handful of files, while the layout half reaches
into six pages and the dark mode needs a second scheme. Splitting also keeps each
step reviewable as a diff rather than as a screenshot.

**Rename `WeChat` and `lib/ui/wechat/`.** Deferred, not rejected: the class no longer
describes WeChat, and the doc comment says so. But the name appears at every call site
and the conversation surfaces still borrow WeChat's structure, so renaming it is a
mechanical chore that belongs in its own PR rather than in a repaint.

## Consequences

**One test enforced an invariant that this change deliberately reverses.**
`test_flutter/ui/shell_test.dart` asserted "the conversation board and a received
bubble have traded fills" — `bubbleIn == pageBackground`, and the board different from
the bubble. Both halves are false now. It is replaced by a test that pins the new
relationship instead: the bubble takes the board's white, and `divider` is not that
white, so a future edit cannot leave a white bubble on a white board with nothing to
see. Two more assertions in the same file moved with the design: `cardTheme.elevation`
is 1, and the rail's selected icon is `brandStrong` rather than `brand`.

**Every surface changes appearance at once, and no page was edited.** That is the
whole point of a token class — and it is also the risk. Nothing in the analyser or the
suites can tell whether a 14px corner looks right; the acceptance for this is the
before/after screenshot comparison agreed with the reviewer.

**The token set grew by ten and lost one.** `brandStrong`, `brandSoft`, `brandLine`,
`onBrand`, `surfaceSunken`, `borderStrong`, `bubbleOutText`, `danger`, `avatarRadius`
and `bubbleTuckRadius` are new; `badge` is gone. Anything that wants "the accent
colour" now has to say which of the two greens it means, which is the point.

**Still to come, in their own PRs.** The layout half — conversation list 250→300, the
fixed row height dropped, navigation labels, the tag component, the in-app page top
bar, the directory field in settings, a duration on a transfer — and then dark mode.

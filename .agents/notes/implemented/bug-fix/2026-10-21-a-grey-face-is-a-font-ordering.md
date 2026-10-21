# Agent Note: A grey face is a font ordering

Status: implemented

English | [中文](2026-10-21-a-grey-face-is-a-font-ordering.zh.md)

## Problem

The emoji picker went grey.

Not all of it — the faces that are genuinely pictographs kept their
colours, and the ones a user would call "the symbols" came out flat:
the raised hand, the cross mark, the check mark, the question mark, the
star, the lightning bolt. A picker of grey outlines, next to the same
picker a version earlier had drawn in colour, reads as a rendering bug
that nobody can point at: there is no wrong line in this repository, no
exception in the log, no colour set to anything but black.

The cause was a single entry in one list.

The theme's font fallback chain is how a character that the Chinese
face does not have gets drawn at all. It had three entries, and then a
fourth: `Segoe UI Symbol`, added to give the composer's `☺` button a
glyph — the Chinese face has no `☺` in it, and without a symbol face
the button would have been an empty box. That was a real fix, for a
real problem, and it was right.

It was also, accidentally, the end of colour in this application.

`Segoe UI Symbol` is a *monochrome* symbol face, and it covers every
emoji code point as a plain outline. The machine also has
`Segoe UI Emoji`, which draws the same code points in colour, by way of
COLR colour layers. Both fonts claim the code points, so the chain's
order decides which one wins — and the chain is consulted in order,
first match first. The monochrome face was in front.

So every pictograph that had no monochrome outline to fall back on
stayed coloured, and every code point the symbol face *did* have an
outline for became a grey outline. The faces that went grey were
exactly the faces the symbol face covered. Nothing about the picker,
the table, or the bubble had changed — a font ordering had.

The change that broke it was a commit about something else entirely: the
README's screenshots, and the labels in them that were coming out in
the platform's default face. It added the symbol face to the chain as
the last step of a font fix, and the colour went with it. `v0.1.11`
had a chain of three and drew its faces in colour; `v0.1.12` had a
chain of four and drew them grey.

## Decision

**The colour face goes in front of the monochrome one.**

`Segoe UI Emoji` now precedes `Segoe UI Symbol` in
`WeChat.fontFamilyFallback`. The symbol face stays on the chain — it is
what draws the `☺` on the composer button, and the arrows and the
mathematical signs that no other face carries — but it now draws only
what the colour face has no glyph for.

This is the whole fix, and it is a single-element reordering. The
chain was already right about everything else; it was wrong about one
thing, and that one thing was the difference between a colour and a
grey.

**Two things about the faces themselves are pinned down.**

*A code point whose Unicode default is the text presentation carries
the variation selector U+FE0F.* `✋` on its own is a plain outline,
because that is what Unicode says it is by default; `✋️` is the raised
hand. The same goes for `❓` `❗` `⭐` `⚡`. Four faces in the table
were carrying the text presentation, and they now carry the selector.
`✌️`, `❤️` and `☀️` already had it.

*Every face in the table has a colour glyph to be drawn with.* A code
point that no installed colour font covers comes out as an empty box,
and no chain ordering can fix that — the face has to be replaced. One
was: `🫡` (saluting face) is in no font on the machine, so it was
replaced with `🙌` (raising hands), which every relevant font draws in
colour.

**The table's font is the theme's font.** The emoji tiles name no
family of their own, so they inherit the theme's chain — which is
where the ordering lives. One place names the chain explicitly: the
composer button's `☺`, which asks for the theme's family and the
theme's chain rather than the platform default.

## Alternatives considered

**Draw the emoji in the picker's own font, and leave the chain alone.**
Rejected: the same faces are drawn in three other places — the
composer, the bubble, and the recent strip — and each of them would
need its own copy of the rule. The chain is the one place that says
"how does this machine draw a character this application does not
have", and the defect was that one answer was wrong. Fixing it in
three places would have left the fourth place wrong.

**Take the symbol face off the chain and give the `☺` button its own
font.** Rejected: the chain is not only there for the emoji button.
The arrows, the mathematical signs, the box-drawing characters — they
are all characters the Chinese face does not have and the platform
default might not have either. Removing the face would have fixed
the colour and broken the coverage the face was added for.

**Ship the emoji as images instead of code points.** Rejected: the
table is code points on purpose — a code point is a fact about
Unicode that the receiving platform renders, so two builds never have
to agree on a pixel. Bitmaps would mean shipping, versioning and
licensing a set of pictures for sixty-one faces, and would have
changed what goes over the wire.

**Replace the grey faces with different code points — drop `✋`, use
`🖐️` instead.** Rejected: it treats the symptom. The faces were not
wrong; the drawing of them was. Replacing code points to dodge a
font-ordering problem loses the faces a user actually reaches for
(the raised hand is a raised hand), and it leaves the ordering wrong
for whatever is added next.

**Replace the grey faces with different code points — keep the change
to the table.** Rejected, and this is the one that was done for
`🫡` only: a face that *no font can draw* has to go, because there is
nothing to order. The grey faces had glyphs — coloured ones, in a
font the chain simply was not asking first.

## Consequences

- **The faces are in colour again**, and the reason is in the diff: the
  chain says so.
- **The chain's order is now a correctness requirement, not a
  preference.** A test asserts that the colour face comes first,
  because a future "let me tidy the fallback list" commit would
  otherwise put it back silently.
- **A face with no colour glyph is caught at build time.** The test
  reads the system's colour font and checks that every face in the
  table has a colour layer; it fails by name when one does not. The
  check was verified by putting `🫡` back: it failed, and it named
  the face.
- **The check reads the machine's fonts, so it skips when they are
  absent.** A machine without `Segoe UI Emoji` cannot answer the
  question, and a skipped question is honest — failing there would
  make the suite depend on the machine rather than on the code.
- **The parser lives under `test/`, not in `lib/`.** Nothing in the
  shipped application asks whether a face is coloured; the
  application hands the code point to a chain and the chain decides.
  A font parser in the package would be weight for a question nobody
  asks.
- **The faces that changed their code points changed it on the wire.**
  `🫡` and `🙌` are different characters, so a peer that has `🫡` in
  its recent strip will not match it against `🙌`. The recent strip
  drops faces the current table does not have, which is what it
  already does with a face from a build that no longer offers it.

# Agent Note: The hero leans into 3D after all

Status: implemented

## Problem

Within hours of the two-column hero landing
(`2026-10-13-the-hero-finally-shows-the-thing.md`), the tilt was wrong twice
over. First it read left-low/right-high; flipping it to clockwise fixed that,
and the follow-up request then said what the flat rotation could never deliver:
the screenshot should feel like a screen *standing up*, seen from the side.
A 2D `rotate()` is a sheet of paper turned on a table — it has no depth, so no
amount of angle tuning makes it read as a upright display.

## Decision

**Swap the 2D rotation for a real perspective, on the picture's own terms.**

- `.hero__art` gets `perspective: 1100px; perspective-origin: 80% 50%`; the img
  gets `transform: rotateY(20deg) rotateX(3deg)` (12°/2° under 860 px). The
  vanishing point sits toward the outer edge so the screen's near side — the
  device list, where the reading starts — is the crisp one, and the far side
  falls away like a display turned slightly from the viewer.
- **The earlier "no 3D" reasoning is overruled — by its author's user, not by
  forgetting it.** That note rejected perspective because it softens the glyphs
  inside the interface, and legibility was the whole point of the picture. The
  user has now seen the flat version and asked for depth anyway; softening is
  the price they chose. The reasoning was never wrong, it was outvoted.
- `rotateY` *narrows* the painted width (×cos of the angle), so the 32 px
  column gap and the section padding still absorb the projection with nothing
  overflowing — verified, not assumed.
- Narrow screens keep the same reading at 12°: a bare flat screenshot under the
  copy would have looked like a different, plainer page.

## Testing

- Headless Chrome, 1280×900 light and 390×1400 narrow. Both read as an upright
  screen seen from its left-front; no collision with the copy, no horizontal
  overflow, the pill row below is untouched.
- Dark theme shares the geometry — only the border colour differs — and was
  verified in the previous note; not re-shot.

## Alternatives considered

**Keep 2D rotation and just increase the angle.** Rejected: angle is not the
missing dimension. No flat rotation produces foreshortening, which is what
"standing up, seen from the side" *is*.

**A mockup-style composite (screen bezel, stand, shadow layer).** Rejected for
now: it means authoring artwork rather than presenting the real interface, and
every real UI change would stale it. If the user wants literal thickness later,
that is a new asset, not a transform.

**Bigger perspective (closer vanishing point, >25°).** Rejected: past roughly
20° the far-side text stops being readable at all, and the picture's remaining
job — showing this interface — is lost.

## Consequences

**Bought.** The hero reads as a physical display in the room instead of a
pasted image; the request is met without touching the image itself.

**Given up.** The glyphs in the screenshot are softened by the projection, and
that is now permanent until the user says otherwise. The CSS comment that
explained why the site refused 3D is gone; this note replaces it as the record.

**Owed.** Same as before: nothing ships until the next release or a manual
`pages.yml` dispatch. No Dart changed, so the six gates are unchanged by
construction; format and analyze were run anyway.

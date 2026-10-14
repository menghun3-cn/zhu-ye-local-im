# Agent Note: The hero spins on its own axis

Status: implemented

## Problem

The planar clockwise 30° (`2026-10-13-the-hero-comes-back-flat-and-turns-thirty.md`)
lasted one round too. The refinement: "on the front-facing base, rotate 30°
around the middle axis, horizontally." The rotation axis was wrong, not the
angle — an in-plane `rotate()` tips the whole sheet like a crooked photo, while
the user wants the picture to swing around its own central vertical axis, the
way a door turns on its hinge.

## Decision

**`transform: rotateY(30deg)`, and nothing else.** Two boundaries kept from the
previous rounds, deliberately:

- **No `perspective`.** The user rejected the 3D side view two rounds ago and
  has not asked for depth back. Without a perspective ancestor, `rotateY` is an
  orthographic projection: the picture stays front-facing and readable, only
  foreshortened to cos30 ≈ 0.87 of its width, both edges pulling in
  symmetrically. That is "rotated around its middle axis" in the flat sense.
- **No `scale`.** The planar round needed `scale(.82)` because a 2D rotate
  *grows* the painted box (×1.17). `rotateY` *shrinks* it (×cos), so the
  painted box is narrower than the column by construction — the scale and its
  justification are both gone.

`transform-origin` stays at the default `50% 50%`, which is literally "the
middle axis".

## Testing

- Headless Chrome 1280×900: image level (no tilt), narrowed, inside the column.
- Iframe harness at a true 375px viewport: `scrollWidth == clientWidth`, no
  element outside the viewport. No Dart changed; the six gates are untouched.

## Alternatives considered

**`rotateY(30deg)` under `perspective`.** Rejected for now: it reintroduces the
depth the user explicitly turned down, and at 30° the far side would recede
harder than the 20° version they already rejected. Flagged in the reply as a
one-line switch if "turned" should read with depth.

**Keep the planar `rotate(30deg)`.** Rejected: wrong axis — that was the very
thing this round corrected.

## Consequences

**Bought.** A level, front-facing screenshot that narrows symmetrically around
its own centre — the axis requested, no depth re-added.

**Given up.** Orthographic `rotateY` can read as "slightly narrower image"
rather than "turned"; the foreshortening is the entire visible effect. If that
reads as underwhelming, the honest fix is perspective, not a bigger angle.

**Owed.** Same as before: nothing ships until the next release or a manual
`pages.yml` dispatch.

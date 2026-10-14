# Agent Note: The hero comes back flat, turned 30 degrees

Status: implemented

## Problem

The 3D side view (`2026-10-13-the-hero-leans-into-3d-after-all.md`) lasted one
round. The next instruction redefined the target pose entirely: "front-facing
and upright, then rotate 30° clockwise." That is not a camera move around a
standing screen — it is the flat screenshot, face toward the viewer, tipped
clockwise like a photo pinned slightly askew. The perspective machinery
(`perspective`, `rotateY`, `rotateX`) now expresses the wrong thing: it
foreshortens a picture the user wants seen square-on.

## Decision

**Back to a 2D rotation — the same primitive the 3D note rejected — but for a
different reason, which is why the rejection does not carry over.** The earlier
objection to 2D `rotate()` was that it cannot produce depth; here depth is
explicitly not wanted. `rotate(30deg)` is exactly the request. CSS positive
angles are clockwise, so the reading "left edge high, right edge low" that the
user asked for in the previous round is preserved automatically.

Two mechanics worth recording:

- **Rotation does not change the layout box, it changes the painted box.** A
  1.67:1 image rotated 30° has a bounding box ≈1.17× its width; at
  `width: 100%` of the right column that overshoots the column into the gap,
  the copy, and the page margin. A `scale(.82)` is stacked on the same
  transform (`rotate(30deg) scale(.82)`) to pull the painted box back inside
  the column. The angle stays exactly 30° — scale does not touch angle.
- **A 390px screenshot on this machine lies.** Windows enforces a ~500px
  minimum window width, so `--window-size=390` lays the page out at ~511 and
  crops the shot to 390 — text looks clipped when nothing overflows. The honest
  check is an iframe harness: a real 375px inline viewport (after its
  scrollbar), where `scrollWidth == clientWidth` and no element's transformed
  bounding rect crosses the edge.

Narrow screens keep `rotate(30deg) scale(.8)` under 860px — same angle, same
reasoning, slightly more scale headroom for the full-width column.

## Testing

- Headless Chrome 1280×900: face-on image, left-high/right-low 30° tilt, fully
  inside the right column; copy and pill row untouched.
- Iframe harness at a true 375px viewport: no scrollable overflow, no element
  bounding rect outside the viewport. The earlier "clipped" 390px screenshot
  was identified as the minimum-window-width artifact above, not a regression.
- Dark theme shares the geometry; only the border colour differs. Not re-shot.

## Alternatives considered

**Keep the 3D view and add a Z-axis twist (`rotateZ(30deg)` on top of
`rotateY`).** Rejected: that is "side view, also spun", not "front-facing,
turned". It preserves the glyph softening while no longer delivering the pose
the user named.

**Drop the scale and let the corners overlap the gap and margin.** Rejected for
now: ~39px of image would sit in a 32px gap and cross the section edge; the
composition would read as a rendering bug rather than intent. If the user wants
it larger, the honest fix is a wider art column, not overflow.

**Tune `perspective-origin` to fake a square-on look.** Rejected: perspective
always foreshortens somewhere; "front-facing" and "perspective" are
contradictions, not knobs.

## Consequences

**Bought.** The exact pose requested: a clean, sharp, face-on screenshot tipped
30° clockwise. The glyphs regain full crispness — the cost the 3D round accepted
is refunded.

**Given up.** The depth reading ("standing up, seen from the side") is gone
again, by explicit instruction. The 3D note's "Given up / Owed" record is now
historical; this note supersedes it. `perspective` and `perspective-origin`
are removed from `.hero__art` rather than left as dead weight.

**Owed.** Same as before: nothing ships until the next release or a manual
`pages.yml` dispatch. No Dart changed, so the six gates are unchanged by
construction.

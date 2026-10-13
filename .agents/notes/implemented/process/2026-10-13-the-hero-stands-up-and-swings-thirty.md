# Agent Note: The hero stands up and swings 30° around its own axis

Status: implemented

## Problem

The orthographic `rotateY(30deg)`
(`2026-10-13-the-hero-spins-on-its-own-axis.md`) lasted one round too. The
refinement: the image should stand up — read as a screen in space — while
still swinging 30° around its own central vertical axis. The missing
ingredient was depth, which is exactly what the previous round deliberately
left out; the user has now asked for it back.

## Decision

**Parent perspective, centred; child keeps a bare `rotateY(30deg)`.**

- `.hero__art` gains `perspective: 1000px; perspective-origin: 50% 50%`.
  Centring the origin is what keeps the swing strictly around the image's own
  middle axis: the near edge grows, the far edge recedes, the composition
  stays symmetric — a door turning on its hinge, seen from the front.
- No `rotateX`: a pure horizontal swing, the screen does not lean toward the
  viewer.
- No `scale`: `rotateY` shrinks the painted width by cos30 ≈ 0.87, so the
  standing screenshot still fits the right column by construction.
- The narrow-viewport override keeps the same transform and inherits the
  parent perspective automatically — nothing to duplicate.

## Testing

- Headless Chrome 1280×900: the screenshot stands up, near edge right, far
  edge left, symmetric around its centre, inside the column.
- Iframe harness at a true 375px viewport: `scrollWidth == clientWidth`, no
  element outside the viewport. No Dart changed; the six gates are untouched.

## Alternatives considered

**`perspective-origin: 80% 50%`** (the earlier 3D side view). Rejected: it
biases the vanishing point, so the swing is no longer around the image's own
centre — the user was explicit about the central axis.

**An extra wrapper with `transform-style: preserve-3d`.** Rejected: a single
transformed element plus a parent perspective is already enough; the wrapper
adds coupling for no visual gain.

**Staying orthographic.** Rejected by the user this round — that flat swing is
precisely what read as "just a narrower image".

## Consequences

**Bought.** A standing screenshot with real depth, rotating 30° around its own
central vertical axis.

**Given up.** Text inside the 3D-transformed image renders slightly soft; the
same trade-off accepted during the earlier side-view round. Colours and layout
do not depend on the transform, so removing it degrades gracefully.

**Owed.** Nothing ships until the next release or a manual `pages.yml` dispatch.

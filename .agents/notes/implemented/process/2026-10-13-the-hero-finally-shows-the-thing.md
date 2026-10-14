# Agent Note: The hero finally shows the thing

Status: implemented

## Problem

Three requests about the marketing site, all of them about the same weakness: the
page described the application in prose and never showed it.

1. The download section ended with a callout telling readers to script their
   downloads against two fixed `releases/latest/download/...` addresses, with
   `.sha256` sidecars. The request was to remove it.
2. The four-item strip — 服务器/账号/云端/外网请求, each answered 没有 or
   仅「检查更新」 — was a four-column grid of label-over-value cards. The request
   was to present the same content differently.
3. The top of the page was text only. The request was an image on the right,
   tilted, with the existing copy unchanged on the left.

The underlying issue with (3) is that a page whose entire pitch is "two of your
own devices, talking on your own network" had no picture of two devices talking.
Every screenshot that exists lives in `design-preview/_shots/`, which is
untracked — the site could not have referenced one even if it wanted to.

## Decision

**The hero became two columns, and the site gained its first binary asset.**

- `site/assets/hero.png` (1284×769, 73 KB) is the conversation page window,
  cropped out of `design-preview/_shots/conversation.png`. The crop is exact:
  the source is a 1360×980 page whose bottom ~150 px are design annotations
  ("局部微调说明…", "配对回到列表行上…"), which must not ship. The window's own
  hairline border is at x 38–1321 and its bottom edge at y 824; the crop is
  `(38, 56, 1322, 825)`, found by matching the border colours rather than by
  eye, because the page background (`#E9EBEF`) is not white and a naive
  "not white" bounding box swallows the annotation text.
- **Copying, not referencing.** `design-preview/` is untracked, so Pages would
  have served a 404. The image is now a tracked file under `site/`. This amends
  `2026-10-12-the-site-is-files-not-a-build.md`, which says the site is three
  files and nothing else: it is now three files plus one image, and that is the
  one place where "no build step" stops being literally true — the crop was
  made by hand, once, and is reviewed as a diff from here on.
- **The tilt is 2D, not 3D.** `transform: rotate(-2.4deg)` (1.2° under 860 px).
  A `perspective()` tilt would have looked more "designed", and would also have
  softened every glyph inside the interface — the one thing this picture exists
  to prove is that the interface is legible.
- **The text column is wider than the image column** (`1.1fr / 1fr`). The h1 is
  a hard-broken two-liner; in an equal-width column the first line overflows at
  the display size, and the fix would have been to shrink the type, which is the
  wrong trade. The h1 size is `clamp(34px, 3.6vw, 48px)` so it never outruns its
  column between 960 px and the 1080 px container.
- **The four items became pills, not another grid.** Each pill carries a mark:
  a circled slash for the three that are genuinely absent, a solid dot for
  外网请求 — because that one is not "none", it is "only this much", and a
  crossed-out mark would have said the opposite of the truth. The strip stacks
  to one column under 960 px.

## Testing

- Rendered in headless Chrome at 1280×900 (light), 1280×900 (dark, forced by
  patching a throwaway copy of the page so the inline theme script could not
  reset it), 390×1400 (narrow), and 1280×2200 (whole page). All four looked
  right: no h1 overflow at any width, the image never collides with the copy
  (the 32 px column gap absorbs the rotation), the pills wrap instead of
  scrolling, and the download section ends after the SmartScreen callout.
- The removed callout is gone and nothing referenced it: `grep` over `site/`
  finds no `latest/download` and no `sha256sum`. The `.callout code` rule stays,
  with its comment rewritten — the reason it existed (one URL longer than its
  container) is gone, but long paths and hashes have no natural break point.
- No Dart, no workflow, no packaging input changed, so the six gates are
  unchanged by construction; they were run anyway.

## Alternatives considered

**A 3D perspective tilt.** Rejected: it softens the text inside the screenshot,
and legibility of the interface is the whole point of putting it there.

**Referencing `design-preview/_shots/conversation.png` directly.** Rejected:
that directory is untracked, so the deployed site would 404 on its own hero.
Copying the file into `site/assets/` is the only version that survives a fresh
clone.

**Generating an illustration instead of using a screenshot.** Rejected: an
illustration of "two devices transferring a file" would be a drawing of the
product, on the page whose job is to show the product. The design tokens are
already shared with `design-preview/`, so a screenshot is the on-brand option
for free.

**Keeping the fixed-address callout somewhere lower on the page.** Rejected: the
request was removal, and the addresses are a maintainer concern — they live in
`release.yml`, `CHANGELOG.md` and the release notes, which is where someone
writing a script will find them.

**Leaving the four items as a grid and only restyling it (dividers, uppercase
  keys).** Rejected: that is the same reading pattern with different paint. The
  pill row changes what the strip *says* — a list of things being crossed off,
  one at a time — which is what the content always meant.

## Consequences

**Bought.** The first screen now shows the product, the copy is untouched, and
the four "no"s read as a series of negations rather than a spec table.

**Given up.** `site/` is no longer exactly three files. Any future "just copy
the directory" reasoning has to account for `assets/`, and the one image in it
was produced by a manual crop that no script reproduces — if the interface
changes, someone has to crop again by hand.

**Owed.** Nothing ships from this branch: `master` only accepts `release/*`
PRs, so the new hero goes live with the next release (or a `workflow_dispatch`
run of `pages.yml`, which exists for exactly this).

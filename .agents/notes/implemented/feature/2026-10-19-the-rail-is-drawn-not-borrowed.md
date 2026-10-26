# Agent Note: The rail is drawn, not borrowed

Status: implemented

English | [中文](2026-10-19-the-rail-is-drawn-not-borrowed.zh.md)

## Problem

A wide window's left rail is Material's `NavigationRail`, re-skinned by a
`navigationRailTheme`. The draft (`design-preview/conversation.html` and
`design-preview/styles.css`) is a different picture, and the three places it
differs are not colours:

- **The current surface is one block.** The draft's
  `.rail__item[aria-current="page"]` fills the whole entry — glyph and word
  together — on `--brand-soft`, and turns the label `--brand-strong` with it.
  The component marks the current destination with a 56 × 32 stadium behind the
  *icon* alone. `NavigationRailThemeData.indicatorShape` changes that stadium's
  shape; its size is `_kCircularIndicatorDiameter` × `_kIndicatorHeight`, two
  private constants, and no parameter reaches it.
- **The six entries are two runs.** `.rail__spacer` separates the four places to
  be (会话 / 设备 / 传输 / 剪贴板) from the two a user visits to change something
  (设置 / 关于) with nothing between them but space. The component draws
  `destinations` as one contiguous run.
- **The product's mark is at the head.** `.rail__brand` draws the bamboo-leaf
  bubble above every entry, and the theme has no slot for it.

Only the first is a wall. `leading` and `trailing` hold arbitrary widgets and
`trailingAtBottom` pins one at the foot, so a group break and a brand mark are
reachable — but only by putting entries outside `destinations`, where nothing
draws them. A hand-built entry is what those two differences need anyway, and a
hand-built entry carrying the draft's block is the first difference. One answer
covers all three.

A theme slot also cannot be asserted. A test reads
`navigationRailTheme.indicatorColor` and passes while the marker on screen is
the wrong shape, size, or extent; nothing in a widget test sees the picture.

## Decision

Draw the rail in `lib/ui/nav_rail.dart`.

`AppNavRail` is the column: the brand mark, an optional `status` block, the four
surfaces, a `Spacer`, the two tools, and an optional `trailing` below them. It
takes one ordered `destinations` list and `pinnedCount`, the number counted off
the *end*, so the shell's list stays single and a seventh surface cannot land in
the wrong run.
`NavRailDestination` is its entry type — a glyph, a word and a count, and no
filled variant, because the rail does not swap the glyph when an entry becomes
current. `RailItem` is the entry itself, public and found by its label.

`WeChat` gains the twelve rail tokens transcribed from the draft (`railWidth`
84, the two paddings, the item gap, the brand box and mark, the item radius and
padding, the icon/label gap, and the icon and label sizes), and a narrow window
keeps Material's `NavigationBar`. The shell builds one ordered `_Surface` list —
glyph pair, word, count — and hands the same order to both: the rail takes the
outlined glyph, the bar takes both, because filling the current tab's glyph is
how Material says where a reader is.

## Consequences

- `lib/ui/nav_rail.dart` is new. The brand mark is the draft's 24 × 24 SVG
  transcribed command for command and scaled to 26, drawn as a `CustomPaint`
  rather than an icon: the nearest Material stand-in (`Icons.eco`) is a leaf
  without the bubble, at the one size a reader sees under the window's own icon.
- `lib/ui/wechat/theme.dart` loses `navigationRailTheme` — nothing reads it —
  and gains the twelve tokens. The label inherits `lineHeightBody` (1.4) rather
  than the draft's own line height, so an entry's block is about 56.4 pixels
  where the draft measures 58.
- `lib/ui/home_shell.dart` builds the six surfaces once, as one list, and gives
  the rail `pinnedCount` and the update entry as `trailing`.
- `test_flutter/ui/nav_rail_test.dart` is new: the two runs and the foot, the
  whole-entry block, the pointer, and the Tab walk. `ui_harness.dart`,
  `shell_test.dart` and `update_rail_test.dart` name `AppNavRail` where they
  named `NavigationRail`.
- This round also appends to the note above it: every update entry is disabled
  while an update runs, and the confirm button says "Update and restart". The
  hand-drawn `RailItem` and the hand-drawn update entry (`_UpdateEntry`) are
  now driven by the shell's `_updateLocked`, so the disabled state is this new
  rail's own concern.
- The rail is ours to keep. Keyboard traversal, semantics, RTL and any future
  disabled state are now ours, and a regression in them fails no component test
  but ours.
- Older notes name the component where this build names the rail. [An update
  entry pinned under the
  rail](2026-10-12-an-update-entry-in-the-rail.md) writes the entry as
  `NavigationRail(trailingAtBottom: true)`, [the rail entry installs instead of
  opening a
  browser](2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.md)
  measures the rail at 72 pixels — the component's default, not this draft's 84
  — and [the application has a
  screen](2026-09-30-flutter-ui-shell.md) and [the WeChat look covers every
  surface](2026-10-09-wechat-theme-everywhere.md) name `NavigationRail` as the
  container and as a skinned widget. These are facts to bring along, not
  decisions that changed.

## Alternatives considered

**Keep `NavigationRail` and set `indicatorShape`.** The shape is a parameter and
the size is not. A `RoundedRectangleBorder` on a fixed 56 × 32 box is a rounder
stadium, not the draft's block, and nothing stretches it over the word.

**Compose the draft out of `leading` and `trailing`.** `leading` holds the brand
and `trailing` with `trailingAtBottom` holds the foot, so the arrangement is
reachable — but the two tools have to leave `destinations` to get space above
them, and an entry outside `destinations` is drawn by nobody. Both routes end in
hand-built entries; the component would contribute a `Material` and a
`SafeArea` while owning a list order the shell already owns.

**A destination per entry with a pill-shaped `indicatorShape`.** The only
per-destination lever is `padding`, and padding moves the entry's box without
moving the 56 × 32 marker, which follows the icon. The marker would sit centred
in a taller box rather than fill it.

**Plain `GestureDetector`s.** Cheaper, and it drops the keyboard: `InkWell`
brings focus, an `ActivateIntent` binding, and the semantics role that makes the
rail reachable by Tab.

**`NavigationDrawer`, or an extended rail.** Both answer a different problem: a
drawer is a modal list over the content, and an extended rail spends width on
labels that the draft fits under the glyphs.

**A theme slot beside the hand-drawn rail.** Nothing would read it, and a slot
nothing reads is where the next reader looks for the rail's colours and does not
find them.

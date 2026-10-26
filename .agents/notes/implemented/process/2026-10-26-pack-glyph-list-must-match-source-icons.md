# Agent Note: The pack glyph list must match the icons the source uses

Status: implemented

English | [中文](2026-10-26-pack-glyph-list-must-match-source-icons.zh.md)

## Problem

`scripts/pack-windows-portable.ps1` names the code points that must be present
in the bundled `MaterialIcons-Regular.otf`. The list is the project's real
guard against stale icon subsets, but it also becomes a stale check when source
code stops using one of those icons. Removing the About card's separate
download-and-update button also removed the only source use of
`Icons.download_outlined`; the tree shaker correctly dropped `0xeff2` from the
font, and the release-time smoke check failed on a glyph the source no longer
asks for.

## Decision

The required-glyph list contains only code points the current source uses.
Removing a source icon removes its entry in the same change, keeping the comment
next to each listed glyph a statement about the current source rather than a
record of past UI. The single action button's `Icons.system_update_alt`
(`0xe637`) remains on the list.

## Alternatives considered

**Keep the removed glyph in the list.** It matches nothing in the source, so it
would fail every future build while the icon subset follows the source.

**Treat a missing listed glyph as a warning.** The check exists so a package
that would draw empty icon boxes cannot be shipped; weakening it for stale
entries would also weaken it for genuinely missing glyphs.

## Consequences

- The About-card action no longer leaves the pack glyph list one entry behind.
- The remaining list continues to be a complete statement of the icons this
  release must draw, so the source-icon smell it catches stays caught.

## Testing

The change is a list entry matching the single button icon already kept in the
source; `.\scripts\pack-windows-portable.ps1 -Smoke` passes once a build exists.

# Agent Note: The packaged icon font went stale behind a content-hashed build cache

Status: implemented

English | [中文](2026-10-09-the-icon-font-stayed-stale-behind-a-content-hashed-cache.zh.md)

## Problem

The Windows portable package went out with a Material icon font that did not
contain the one glyph the new right-click **Copy image** item needs:

```
PACK_THREW: MaterialIcons-Regular.otf 里没有这些字形，界面上的图标会是空白的:
      0xef7f (Icons.content_copy_outlined)
```

The guard inside `scripts/pack-windows-portable.ps1` did its job. What it could
not say is why, and the first explanation — the one the script's own comments
gave — was wrong.

The evidence that rules out "the icon is unreachable code": `0xf090`
(`Icons.folder_open_outlined`) *was* in the font. That icon lives in the same
file, in the same widget, in the same `_item(...)` list, seven lines above the
one that was missing (`lib/ui/transfer_actions.dart`). A tree-shaker that reads
reachability cannot include one and drop the other.

The evidence that rules out "the build never recompiled the app":

| file | mtime |
| --- | --- |
| `lib/ui/transfer_actions.dart` | 20:00:12 |
| `pubspec.yaml` (touched by the script) | 20:10:31 |
| `.dart_tool/flutter_build/<hash>/app.dill` | 20:11:07 |
| `build/.../Release/data/app.so` | 20:11:19 |
| `.dart_tool/flutter_build/<hash>/release_bundle_windows-x64_assets.stamp` | **19:14:07** |
| `build/.../Release/data/flutter_assets/fonts/MaterialIcons-Regular.otf` | **19:14:06** |

`app.dill` was rebuilt and does contain `0xef7f`. The step that runs the icon
tree-shaker (`release_bundle_<platform>_assets`, i.e. `BundleWindowsAssets`)
never ran at all — its stamp is an hour older than the source it should have
read. Build succeeded, exit code 0, every user-facing string present, one icon
blank.

**Root cause.** Flutter's build system decides whether to re-run a target by
comparing **content hashes** of its inputs, not modification times.
`build_system.dart`'s `Node.computeChanges` branches on
`fileStore.currentAssetKeys[absolutePath] != previousAssetKey`; mtime appears
nowhere. The invalidation step in the packaging script set
`(Get-Item $pubspec).LastWriteTime = Get-Date`, which changes exactly zero of
the bytes the cache hashes. `BundleWindowsAssets.inputs` does list
`{PROJECT_DIR}/pubspec.yaml` — which is what made the touch look plausible —
but listing an input is not the same as detecting that it changed.

Deleting the produced font is not a lever either: `BundleWindowsAssets.outputs`
is an empty list, so the output side of the check has nothing to find missing.
`build_system.dart` states the rule for the input side plainly: *"If the stamp
file is missing, the target's action is always rerun."*

## Decision

The packaging script stops touching `pubspec.yaml` and instead **deletes the
target's stamp file** — every `.dart_tool/flutter_build/*/release_bundle_windows-x64_assets.stamp`
it can find — so the step that carries the icon tree-shaker is guaranteed to
re-run. The stamp is derived from the build configuration, so the directory hash
is globbed rather than hard-coded. Only that one stamp is removed; kernel
snapshot and AOT have their own stamps and are untouched, which keeps the cost
to a rebuilt font rather than a rebuilt app.

Two belt-and-braces additions came with it. The previously produced
`MaterialIcons-Regular.otf` is deleted before the build, and after the build the
script asserts the file exists again. That turns "the step silently skipped" —
the exact failure above, which produced a green build and a broken window — into
a hard failure at the moment it happens, instead of a blank pill in somebody
else's app.

## Alternatives considered

**Keep touching `pubspec.yaml`.** Rejected: it is the bug. A timestamp change is
not an input change to a content-hashed cache, and the comment claiming
otherwise would keep being believed.

**Delete the produced font as the invalidation mechanism.** Rejected as the
mechanism, kept as the probe described above: with `outputs` empty, a missing
output is not something the cache checks.

**`flutter clean`, or delete every stamp under `.dart_tool/flutter_build/`.**
Rejected: `flutter clean` is a silent no-op on this machine (the sandbox's
safe-delete blocks the bulk delete, and the tool still exits 0 while printing
`Failed to remove ...\build`), and dropping all stamps re-runs the kernel
snapshot and the AOT compile to fix a font problem. Removing one stamp is
smaller and is aimed at the step that is actually wrong.

**Append a byte to `pubspec.yaml` so its hash changes.** Rejected: it edits a
manifest as a side effect of building, and the churn flips the hash back on the
next build, invalidating the step again for no reason.

**Use an icon that is already in the subset (`Icons.content_paste`, `0xe192`,
is present).** Rejected as the fix: it hides the mechanism and the next new icon
fails the same way. It remains the fallback if a future Flutter changes the
invalidation rule in a direction stamp deletion does not cover — which is what
the new post-build assertion is there to detect.

## Consequences

- The package's own font guard passes on a font that is actually current: the
  subset went from 48 codepoints to 49 — the set it already had, plus `0xef7f` —
  and `$requiredGlyphs`, all 11 of them, hit.
- Re-running the step costs a re-subset font, seconds, and nothing else: the
  AOT compile, the kernel snapshot and the native link keep their existing
  stamps and stay incremental.
- A future change to how Flutter invalidates this target fails loudly in the
  script instead of quietly shipping blank icons.
- The reasoning lives in the script, next to the step, because the previous
  wrong reasoning lived there too and was convincing enough to survive two
  rounds of use.

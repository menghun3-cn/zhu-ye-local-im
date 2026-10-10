# Agent Note: dark mode is a palette on the theme

Status: implemented

## Problem

The design draft was signed off with one screen deliberately left unfinished. Its
`[data-theme="dark"]` block had been written and the design-system page could switch
to it, but the draft's own README says as much: the dark tokens exist and have not
been walked screen by screen, and the Flutter side waits behind the template
(`design-preview/README.md`). The repaint and the layout work have both landed, so
this is that item — the last of the three.

The obstacle was never the values. The draft already gives every dark token, and the
dark tokens are the same *roles* as the light ones: a panel, a board, a hairline, an
ink. The obstacle was that a colour in this codebase was not a role. It was a
`static const` on `WeChat`, read by name at dozens of call sites across ten files.

A colour named `WeChat.surface` is a fact about *light*. A widget that says it cannot
render on dark paper no matter what the palette would prefer, because it is not
asking any palette — it is naming a value. What dark mode needed was for the question
to become "which theme is the reader in", and for it to be answered where every
widget already asks its questions.

The design's own rule fixed the shape of the answer. The dark block "只覆盖语义令牌，组件代码
一行不动" — it overrides semantic tokens only, and not one line of component code
changes. A palette any widget has to branch on is not that.

## Decision

**A colour is a `ThemeExtension`, and there are two of them.** `WeChatColors` is an
`@immutable` extension carrying every colour role the design names — thirty of them,
from `brand` to `inversePrimary` — plus the `Brightness` the palette belongs to.
`WeChatColors.light` is the palette the draft was drawn in. `WeChatColors.dark` is
the same roles read off the draft's `[data-theme="dark"]` block, value for value.
Widgets ask `WeChatColors.of(context)`, which is a lookup on `Theme.of(context)` —
the mechanism every widget already uses to learn anything about the theme.

**`WeChat.theme` takes a palette; `MaterialApp` takes two themes.** `theme()` now
reads `theme(WeChatColors colors)` and stamps its argument onto the `ThemeData`
through `extensions: [colors]`. `app.dart` passes
`theme: WeChat.theme(WeChatColors.light)`,
`darkTheme: WeChat.theme(WeChatColors.dark)` and `themeMode: ThemeMode.system`, on
both the running application and the failure screen. The `ColorScheme` is still built
from the palette — `ColorScheme.light(...)` or `ColorScheme.dark(...)` chosen by the
palette's own brightness — so Material's constructor decides only the slots nothing
here names.

**Sizes, radii and type do not move, so they stay still.** They remain `static const`
on `WeChat`. A palette change is a change of paper; a fourteen-pixel corner is not.

**Dark mode follows the operating system, and is not written down.** No setting, no
`ThemeMode` toggle in the UI, no new field in the device profile. `ThemeMode.system`
is the whole of the choice.

**The identifying green never carries white text, and dark mode is where that became
visible.** Wiring the palette turned up three places that had quietly disagreed with
the design — all three the same mistake, a fill colour used as a button:

- The composer's send button and the bubble's filled action were `brand` (`#07C160`)
  under white labels, which is the 2.4:1 pair the repaint's whole
  `brandStrong`/`onBrand` split exists to avoid. They are now `brandStrong` with the
  palette's `onBrandStrong` — white on the deep light-mode green, near-black on the
  bright dark-theme one, the flip the repaint's note predicted.
- The conversation row's Connect action was `brand`; the draft's `.rowact--primary`
  is `--brand-strong`. It is `brandStrong` now.
- Both progress tracks were `Colors.black12`, which is invisible on a dark bubble.
  They are `surfaceSunken` — the draft's `--surface-3`, which is one slot for both a
  progress track and a control's sunken fill.

## Alternatives considered

**Branch on `Theme.of(context).brightness` at each site.** Rejected: it is the
inverse of the design's rule. Every widget would then decide for itself what "the
panel" means on a dark page, and the first one to decide differently is a page drawn
half in each theme.

**Derive the dark palette by inverting the light one.** Rejected: an inversion puts
the brand green on near-black at a luminance that vibrates, and leaves the raised
panel *darker* than the page it is raised above. What has to survive a theme change is
the *relationship* — the panel above the page, the sidebar between them, a received
bubble lighter than its board — and an inversion reverses it. The dark values are the
draft's, chosen as values.

**Keep the `static const` colours and add `WeChatColors` beside them.** Rejected: two
sources of truth for one colour. The static one would win wherever a widget had not
been migrated, so dark mode would work in the places somebody remembered and fail in
the places nobody looked — the worst failure mode, because it looks like it works.

**Let the user choose the theme.** Deferred, not rejected: the design has exactly two
palettes and no third is derived at runtime, and a setting would mean a persisted
preference and a profile-format change the design never asked for. Following the OS is
the honest default until somebody asks for more.

**Rename `WeChat` and `lib/ui/wechat/` in the same PR.** Deferred, as in the repaint:
still a chore across every call site, still not this PR.

## Consequences

**A colour is now a `BuildContext` lookup, and three things followed from that.** A
`const TextStyle` that named a colour had to lose its `const`, because a lookup is not
a constant expression. A private getter with no context — the message bubble's ink —
became a method taking the palette, and the palette is threaded from the bubble's
`build` through the two helpers that draw its inside. And the helper that paints a
progress track needed the context it was already being called with, so it asks for the
palette like everything else.

**Nothing looks different in light mode except the three corrections.** The light
palette is the values that were already there, so the repaint is unchanged — which is
what makes this reviewable as a diff rather than as a screenshot. The send button, the
Connect dot and the two progress tracks do change in light mode, because they were
wrong in light mode; each is a move onto a token the design already had.

**The dark palette is not walked screen by screen, and this PR cannot change that.**
The draft says so about itself: the tokens exist, the switcher works, nobody looked at
every page. What this PR can state is the relationships the tests pin — the board is
lighter than the page, a received bubble is brighter than the board, the sidebar sits
between the two, the ink on the bright green is dark. Whether a given page looks
*right* is still the before/after screenshot comparison, and dark mode has now been
added to it.

**One test group was rewritten and one was added.** `shell_test.dart`'s assertions
about the theme read `WeChatColors.light.*` now, and a new `the dark palette` group
pins the relationships above, that `WeChat.theme(WeChatColors.dark)` stamps a dark
`ColorScheme`, that `WeChatColors.of(context)` resolves to whichever theme is running,
and that `lerp` flips the brightness at the halfway point rather than snapping.

**The palette is reachable only through a theme, and a bare test is not one.**
`WeChatColors.of` falls back to `light` rather than throwing, so a widget pumped under
a bare `MaterialApp` — a dialog in a test, a paint callback outside the application's
tree — renders the light page instead of crashing. The application always installs one
of the two, so the fallback is never what a running window shows.

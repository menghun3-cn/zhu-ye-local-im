# Agent Note: A label that names no font

Status: implemented

English | [中文](2026-10-21-a-label-that-names-no-font.zh.md)

## Problem

Some of the interface's text drew in a font other than the one the theme asks
for. On a machine with a Chinese-first stack, the labels that came out wrong
were the ones Material builds a style for itself: a button's own label, a
list tile's subtitle, a segmented button's segment, a text field's hint.

The theme names its font twice over. `WeChat.fontFamily` is
`'Microsoft YaHei UI'`, `WeChat.fontFamilyFallback` is the chain behind it, and
`ThemeData` is given both — with a comment saying why:

> 中文优先：Windows 上 Material 默认的 Roboto 不含汉字，会回退到系统字体；
> 显式点名雅黑能让中英混排的基线一致。

That intent is only half-implemented. `ThemeData.fontFamily` is a constructor
parameter that gets applied to the **default text theme** — it is not a
readable field, and it does not reach styles the framework builds on its own.
The theme's `textTheme` entries therefore carry the family, and every `Text`
that inherits from one of them draws in YaHei. But a component style such as
`ButtonStyle.textStyle` or `ListTileThemeData.subtitleTextStyle` is a
standalone `TextStyle` that names no family at all.

And that is not the same thing as "inherits the family". `AnimatedDefaultTextStyle`
**replaces** the ambient style rather than merging into it, and `TextStyle.merge`
overwrites `fontFamily` with the other side's value — including with `null`.
A style that names no family therefore does not fall back to the theme's; it
falls back to whatever the platform supplies, which is a different face with
different Chinese coverage and different metrics.

## Decision

**Every style the framework builds for itself now names the theme's font, and
the fallback chain ends at a face that has the symbol glyphs.**

- The component styles in `WeChat.theme` — the button themes'
  `textStyle`, the list tile theme's `subtitleTextStyle`, the segmented button
  theme's `textStyle`, the navigation bar's `labelTextStyle`, the chip theme's
  `labelStyle`, and the input decoration theme's `labelStyle` /
  `floatingLabelStyle` / `helperStyle` / `hintStyle` — carry
  `fontFamily: WeChat.fontFamily` and `fontFamilyFallback:
  WeChat.fontFamilyFallback`.
- The call sites that override those styles carry them too:
  `conversation_view.dart`'s send button and bubble action, and
  `conversations_page.dart`'s row action. An override that names no family
  replaces the theme's one, so the override has to name it as well.
- The composer field and the emoji button's glyph name the family at their own
  call sites for the same reason.
- `WeChat.fontFamilyFallback` gained `'Segoe UI Symbol'`. The Chinese face has
  no `☺` in it, so the composer's emoji button — the one control whose label
  *is* a symbol — had nothing to draw even after the family was named. The
  chain is a chain of "the previous face lacks this one glyph", and the last
  link is the face that has the symbols.

## Testing

- The theme's component styles are asserted to name the family, in
  `test_flutter/ui/shell_test.dart`, next to the existing assertion that the
  text theme carries it.
- The five pictures under `docs/screenshots/` were regenerated and read: every
  button label, list tile subtitle, segmented control label and field hint
  draws in the theme's face, and the emoji button draws a face rather than a
  box.

## Alternatives considered

**Registering the Chinese face under the platform's default family name so
that styles naming no family pick it up.** Rejected: it fixes the symptom only
inside a test. The shipped application runs on Windows, where the default
family is whatever Windows substitutes, and the substitute's Chinese coverage
and metrics are not the ones the design was drawn against. Naming the family
in the style is what makes the picture match the intent.

**Wrapping the captured tree in a `DefaultTextStyle` that names the family.**
Rejected: the capture would then show something the shipping application does
not. The defect is in the shipping styles, and a picture that hid it would
have hidden the very thing the pictures are for.

**Leaving the theme alone and dropping the affected pictures.** Rejected: the
wrong-looking labels were the button and the list tile — the parts of the
interface a reader looks at first.

**Replacing the emoji glyph with a Material icon.** Rejected: `☺` is the
character the design uses, and an icon would be a different picture from the
one the design drew.

## Consequences

**Bought.** One font stack across the whole interface, and the labels in the
pictures are the labels a user sees.

**Given up.** A component style that overrides `textStyle` at a call site must
name the family too, or it silently drops the theme's. That is a rule the
framework does not enforce and the type system cannot express, so the next
call site that overrides one has to know it.

**Owed.** `'Segoe UI Symbol'` is a Windows face. On Android the chain falls
through to `Roboto`, and a `☺` there comes from the platform's own emoji font.
The chain is a list of faces, not a promise that all of them exist.

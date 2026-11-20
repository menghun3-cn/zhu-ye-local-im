# Agent Note: A disabled button stops wearing the brand green

Status: implemented

English | [中文](2026-11-20-disabled-buttons-look-disabled.zh.md)

## Problem

The About card's update button already refused a second press while the
download ran — `onPressed` was `null` for the whole of `session.busy` — but
it looked exactly like it had not noticed the press at all. The progress
bar underneath was moving while the button kept the brand green, the same
colour a live button wears, so a user who clicked 更新 reasonably concluded
the click had been dropped.

The cause was the theme, not the button. `filledButtonTheme` and
`textButtonTheme` pinned `backgroundColor`/`foregroundColor` with
`WidgetStatePropertyAll`, which resolves to the same colour for every
state — including `WidgetState.disabled`. Material's own defaults check the
disabled state first; a theme that answers for all states overrides that
check, so "cannot be pressed" and "can be pressed" drew identically. The
troubleshooting page had already hit this and worked around it locally —
its comment says the quiet part out loud: "a disabled button would still
look pressable."

## Decision

The disabled pair of colours moved into the theme, where every button gets
them.

- **`filledButtonTheme`** resolves `backgroundColor` and `foregroundColor`
  per state: disabled takes `surfaceSunken` and `disabledText` — the sunken
  fill and the faintest text tier the palette already defines for "there is
  nothing to do here" — and every other state keeps `brandStrong` /
  `onBrandStrong` unchanged.
- **`textButtonTheme`** resolves `foregroundColor` the same way, so a
  disabled quiet action fades to `disabledText` instead of staying the
  action green.
- **The rail's update entry** keeps its own `styleFrom`, which names
  `foregroundColor` for all states and would have overridden the theme fix;
  it now also names `disabledForegroundColor: colors.disabledText`.
- **The troubleshooting page's local workaround is gone.** Its
  `FilledButton.tonalIcon` reads the same `filledButtonTheme`, so the theme
  now supplies the identical pair it was hand-rolling — enabled falls
  through to the theme's brand colours, disabled to the same sunken/faint
  pair.

## Alternatives considered

**Override the colours on the update button only**, the way the
troubleshooting page did. Rejected: it fixes the one reported button and
leaves the same invisible-disabled bug on every other filled and text
button in the app — dialog confirms, the share page's actions, the devices
page's connect button — each of which can sit disabled and each of which
would keep looking pressable.

**Change only the button's label or add a spinner.** Rejected as half a
fix: the label already says what the download is doing via the progress
sentence beneath it, and a control that cannot be pressed still has to look
like one. The missing fact was the state, not the wording.

**Dim the whole button with `Opacity`.** Rejected: translucency over an
unknown backdrop is exactly what the palette's named tiers exist to avoid,
and `disabledText`/`surfaceSunken` already encode "inactive" in both
brightnesses.

## Consequences

- Every `FilledButton` and `TextButton` in the app now shows a real disabled
  state for the first time. The update card's button greys the moment the
  download starts, which is the feedback the report asked for; the second
  press was already impossible, and now it also *looks* impossible.
- The rail entry fades to `disabledText` while locked — during the card's
  own update check and for the whole install — matching what the About
  card's buttons do.
- Any future button that disables inherits the correct look without
  remembering to ask for it; the per-call-site workaround pattern the
  troubleshooting page pioneered is no longer needed.
- Buttons with hand-rolled `styleFrom`/`ButtonStyle` foreground colours
  (the screenshot overlay's white-on-dark controls, the composer send
  button) keep their own palettes and were deliberately left alone — they
  already manage their disabled colours themselves or cannot be disabled.

## Testing

- `test_flutter/ui/update_session_test.dart` — "greys the update button
  while its download runs" presses 更新 against a held installer, asserts
  the `FilledButton`'s `onPressed` is null mid-download, and resolves the
  theme's filled-button style for `WidgetState.disabled` to pin
  `surfaceSunken` / `disabledText` — the exact pair that used to resolve to
  the brand colours.

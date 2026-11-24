# Agent Note: The remark helper text ellipsized instead of wrapping

Status: implemented

English | [中文](2026-11-24-the-remark-helper-ellipsized.zh.md)

## Problem

The 修改备注 dialog's helper sentence — 「只在本机显示，代替对方自报的名
称或地址，对方看不到。留空即清除。」 — rendered as 「只在本机显示，代替
对方自报的名…」: the tail of the explanation, including the part that says
leaving the field empty clears the Remark, was cut off with an ellipsis.

The cause is a default in `InputDecoration`, not the dialog's width. A
`helperText` string is drawn with `overflow: TextOverflow.ellipsis` and
`maxLines: helperMaxLines`, and `helperMaxLines` defaults to null — which
the framework documents as "soft line breaks are truncated with an ellipse
while hard line breaks are respected". Every other helper sentence in the
app is short enough to fit on one line, so the remark helper was the first
one long enough to expose the truncation.

## Decision

The remark dialog's helper moved from `helperText` to `helper`, the
widget-valued slot `InputDecoration` offers for exactly this case: a `Text`
carrying `l10n.remarkHelper` styled with the theme's
`inputDecorationTheme.helperStyle`, so it keeps the same size, colour and
font as every other helper while wrapping to as many lines as it needs.
`helper` occupies the same slot below the field and yields to `errorText`
the same way `helperText` does; the dialog has no error state, so nothing
else about the field changes.

`helperMaxLines` was the alternative knob and was rejected for this use: it
still caps the line count and ellipsizes past the cap, so picking a number
is guessing at the longest translation the two locales will ever produce.
The English sentence is already the longer of the two and wraps to several
lines at dialog width.

## Alternatives considered

**Set `helperMaxLines` to a fixed count.** Rejected: it trades one
truncation for a taller one. Any finite cap reintroduces the same defect the
first time a locale or a wider sentence needs one more line, and the "right"
number is a property of the translation, not of the widget.

**Widen the dialog.** Rejected: the ellipsis is applied per line, not per
paragraph — a wider field only delays the cut, and the English sentence is
long enough that no reasonable dialog width fits it on one line.

**Shorten the sentence.** Rejected: 「留空即清除」 is the behaviour a user
most needs told before typing, and the same information has to survive in
both locales; wrapping is the framework's answer to a long helper, not
editing the copy to fit a default.

## Consequences

- The remark dialog's helper now wraps to its full length in both locales;
  the clear-on-empty instruction is always visible.
- The pattern to copy for any future long helper is `helper:` with the
  theme's `helperStyle`, not a bigger `helperMaxLines`.
- The other dialogs keep `helperText`: their sentences fit on one line, and
  switching them would add styling boilerplate for no visible change.

## Testing

- Manual: open 修改备注 on a peer and confirm the helper renders on
  multiple lines with no ellipsis, in both the Chinese and English locales.

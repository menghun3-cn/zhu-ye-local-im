# Agent Note: the WeChat look covers every surface, not just the conversation

Status: implemented

## Problem

The WeChat tokens existed and the conversation surfaces used them. Nothing else
did. The navigation bar and the four remaining pages — 设备, 传输, 剪贴板, 设置 —
were still built on Material defaults, and the theme behind them named the
colours a *page* mentions by hand while leaving almost every component theme and
most `ColorScheme` slots at Material 3's own values. A page does not have to
mention a slot for that slot to be drawn: `Chip`, `Switch`, `SegmentedButton`,
`NavigationRail`, `NavigationBar` and a dialog's surface all read slots nobody
wrote down, so they rendered in Material's palette — a lavender tonal button in
a grey list, a purple-grey `onSurfaceVariant` on every secondary label, an
elevation tint washing flat white cards towards the seed. One un-themed control
in an otherwise WeChat-grey page reads as having come from a different
application, and it survives review because it appears nowhere in the diff.

The conversation list was also unfinished in three specific ways. A row carried
no time, so "when was this last said" was not on screen at all. Rows ran
together with no parting line. And the way in — connecting, or pairing — was
drawn as a filled pill, which is not how the reference draws a quiet action.

## Decision

**Name every colour slot, including the ones no page mentions.** `theme()` now
builds an explicit `ColorScheme.light(...)` in which all of `surfaceDim`,
`surfaceBright`, the four `surfaceContainer*` steps, `onSurfaceVariant`,
`outline`, `outlineVariant`, `inverseSurface`, `inversePrimary`,
`errorContainer`, `onErrorContainer`, `shadow` and `scrim` are given a value.
The rule these share is that none of them may default, because a default is
Material's colour and not this application's.

**`surfaceTint` is `Colors.transparent`.** This is the one slot whose default
actively damages the look: Material 3 tints elevated surfaces towards the seed,
and WeChat's surfaces are flat greys and whites. A flat white card that has been
tinted is the single clearest sign that a theme was inherited rather than
chosen.

**Component themes for everything a page can reach for** — `appBar`, `card`,
`divider`, `chip`, `listTile`, `progressIndicator`, `switch`, `checkbox`,
`radio`, `segmentedButton`, `filledButton`, `textButton`, `navigationRail`,
`navigationBar`, `dialog`, `inputDecoration`, plus `iconTheme` and `textTheme`.
`switch`, `checkbox` and both navigation surfaces resolve per state with
`WidgetStateProperty`, so the brand green appears when a control is *on* or
*current* and the greys otherwise.

**The two navigation surfaces part company deliberately.** The rail sits on
`sidebarBackground` and marks the current item with a brand-coloured icon over a
`listHover` indicator. The bottom bar sits on `toolbarBackground` with
`indicatorColor: Colors.transparent` and marks the current tab by tinting the
icon and its label — no pill behind them. That difference is in the reference,
not an oversight: at the bottom of a phone-sized layout the tab bar is thin and
a filled indicator would dominate it.

**The four pages stop inventing their own numbers.** Each takes
`WeChat.pagePadding`, `WeChat.cardPadding`, `WeChat.cardGap` and
`WeChat.sectionGap` instead of local `EdgeInsets` and literal gaps. Page padding
used to be four independent opinions, which is four chances for two pages to
disagree about the same margin.

**A quiet action is a word, not a pill.** `textButtonTheme` sets the brand green
with no fill, and that is what the conversation row's way in now uses: a
`TextButton` carrying a 6×6 dot and the verb, replacing the filled/outlined
pill. The word button keeps its focus ring, keyboard activation and tooltip
semantics, which a hand-rolled `Material` + `InkWell` would have dropped.

**A row's time comes from the data, not from the clock.** The right-hand column
of a conversation row stacks the timestamp above the action-or-summary, and the
timestamp is `latest?.at ?? peer.lastSeen`. `TransferView.at` is new and
threaded from `app_controller`'s own clock at the moment a Transfer is tracked,
because the engine's `Transfer` is a protocol object and has no time of its own,
and a time read at render would print something different on every rebuild. The
row is also parted from the next by a divider inset by
`conversationRowPadding`, so the line starts at the avatar's left edge: a
full-bleed rule chops a list into blocks, and the reference keeps it one sheet.

**The widget harness now builds the shipping theme.** `test_flutter`'s `_pane`
was assembling its own `MaterialApp` with `ColorScheme.fromSeed(deepPurple)`,
which meant every widget test ran against a theme the application never uses.
It now uses `WeChat.theme()` with only the page transition overridden, so a
theme regression is something the suite can see.

## Alternatives considered

**`ColorScheme.fromSeed(brand)`.** What the app used before this work, and the
tempting simplification: one line, a whole coherent ramp. Rejected because the
point of the exercise is a *specific* green, and a seeded scheme derives its own
by an algorithm nobody in the conversation agreed to. The one place a seed is
still right is nothing in this file.

**Theme only the slots the pages actually touch.** Arguably the minimal fix, and
the reason the previous state existed: it is exactly the set of things a
reviewer can see. Rejected because the list is unknowable — Material reads slots
a page never names, and each one that defaults is a control in the wrong
palette. The cost of naming all of them is a longer file; the cost of not is a
bug nobody can find by reading the page.

**Leave `surfaceTint` alone and give cards `elevation: 0`.** Cards would look
flat, but every *other* elevated surface — dialogs, menus, the selected-option
surfaces — would still be tinted. Transparent at the scheme level fixes all of
them at once.

**`ChipThemeData.visualDensity`.** Written first, then removed: the parameter
does not exist on `ChipThemeData` in this Flutter version, and `flutter analyze`
said so. Recorded here because the other component themes do take it, so the
absence looks like an oversight from the neighbouring lines.

**Draw the row's time at render time, from `DateTime.now()`.** One line, no
plumbing. Rejected because it makes the same message display a different time
on every rebuild, and because a conversation list is a record of what happened,
so its times belong to the events rather than to the frame that drew them.

**Give the connect entry a light grey fill instead of the brand green.**
Preserves the pill silhouette, and the reference does use grey-filled buttons
elsewhere. Rejected because in this list the row's job is to be scanned, and a
filled shape competes with the unread badge and the avatar for the eye; a word
in the brand colour is noticed when looked for and ignored otherwise.

**Assert `ThemeData.fontFamily` in the theme test.** It is not a getter.
`fontFamily` is a constructor parameter applied onto the default text theme, so
the assertion reads the family off `textTheme.bodyMedium` instead — which is
where a page's text actually inherits it.

## Consequences

**A page that forgets a token now gets a WeChat-ish value, not a Material one.**
This is the whole point, and it changes the failure mode of future work: the
worst case is a surface that looks slightly off, rather than one that looks like
a different application.

**Anything added later has to be themed here, or it inherits.** The component
themes are a list that must be kept up with Material's catalogue; a new
component type that no page has used yet is un-themed until someone adds it.
That is one more thing to remember, and it is still better than the alternative
this note describes, because the omission is now visible in one file rather than
spread across four pages.

**The suite can now catch a theme regression.** Because the harness builds
`WeChat.theme()`, the tests that assert slot values and navigation surfaces fail
if the theme is replaced with a seeded or default one — which is exactly the
change that would otherwise pass unnoticed.

**The conversation list shows times it did not show before, so its rows are
taller and its right column is bounded.** The timestamp shares the right column
with the action-or-summary inside a `ConstrainedBox` at 42% of the list width,
so a long summary wraps rather than pushing the name out.

## Testing

`test_flutter/ui/shell_test.dart` gains a `the WeChat theme` group that works on
the `ThemeData` directly, with no widget tree:

* the slots Material would otherwise fill in itself are asserted to *differ*
  from `ColorScheme.light()` — `secondaryContainer`, `onSurfaceVariant`,
  `outline` — each with the consequence written into the `reason`, since "this
  is not merely what Material would have chosen" is the assertion's actual
  content;
* `surfaceTint` is transparent, and the card, scaffold and divider colours are
  the tokens;
* the font family is read off `textTheme.bodyMedium`;
* the rail and the bottom bar carry the WeChat greys, and the bottom bar's
  `indicatorColor` is transparent.

`test_flutter/ui/pages_test.dart` gains three tests on a real conversation row,
one per unfinished detail: a row says when it last moved (the "just now" string
is present), a row is parted from the next by an inset hairline (a `Divider` in
`WeChat.divider` inside a `Padding` of `conversationRowPadding`), and the way in
is a word rather than a filled button (a `TextButton` whose background resolves
to transparent, foreground to `secondaryText`, containing a circular dot).

`test_flutter/support/ui_harness.dart`'s `_pane` is the change that makes those
worth anything: with a throwaway theme in the harness, a regression in
`WeChat.theme()` would not have failed a single test.

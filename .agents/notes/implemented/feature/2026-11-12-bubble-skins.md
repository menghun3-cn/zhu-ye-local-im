# Agent Note: Bubble skins are user data in the profile, not palette slots

Status: implemented

## Problem

The conversation bubble had exactly one degree of freedom: four colour slots
in `WeChatColors` (`bubbleOut`, `bubbleOutText`, `bubbleIn`, `bubbleText`),
all designed and fixed. Users asked for customizable bubbles — gradients,
pictures, their own images — with the outgoing and incoming sides styled
independently, text bubbles only, and the choice living on this Device alone.

Two existing constraints shaped the answer. `theme.dart` deliberately offers
no `copyWith` on `WeChatColors`: the palette is a designed object, and a
mutation API would invite combinations nobody designed. And a user-picked
picture cannot be stored as the path the picker returned — on Android that
is a `content://` URI or a cache file the OS may purge — so "remember the
path" is not a durable answer on one of the two shipping platforms.

## Decision

**A skin is a `BubbleSkin` value in `DeviceProfile`, resolved per bubble at
render time.** `lib/core/profile/bubble_skin.dart` is plain Dart: a sealed
type with two fills — `GradientBubbleSkin` (2–4 ARGB colours, a direction,
optional stops) and `ImageBubbleSkin` (an asset name or an absolute file
path, a scrim, an ink). Both sides persist independently as
`outgoingBubbleSkin` / `incomingBubbleSkin`; absent keys decode to null,
which means "the theme's own colours" — the state every profile starts in.
Serialization is tolerant in both directions: an unknown `kind`, a malformed
colour, or a newer build's fill type all read as "no custom skin" rather than
as profile damage, because a preference is not worth refusing to open a
Device's identity file over.

**The controller, not the theme, carries the skin to the bubble.**
`MessageBubble` already holds the `LocalTransferController`, so
`bubblePaintFor` reads `controller.outgoingBubbleSkin` /
`incomingBubbleSkin` by direction and resolves a `BubblePaint` — a
`BoxDecoration` plus an ink plus an optional scrim — that `MessageBubbleShape`
paints and every word inside the bubble inherits. `WeChatColors` is never
mutated and gains no `copyWith`; the theme keeps its designed-palette
contract. The ink is binary (dark/light) rather than a free colour, which is
what keeps a user-picked fill from producing unreadable text by accident.

**Eligibility is a fact about the message, not the paint.** Only
`PayloadKind.text` and `PayloadKind.emoji` bubbles consult the profile; file
and image transfers keep the theme because their bubble is a transfer's
receipt. A bare local image never had a bubble and still does not. A file
skin whose copied picture has been deleted falls back to the theme paint —
a blank rectangle with white text is worse than the ordinary bubble.

**User pictures are copied, never referenced.** Picking a picture calls
`LocalTransferController.importBubbleSkinImage`, which copies it into
`<data dir>/bubble_skins/` under a timestamp-plus-random name and stores the
copy's path. The profile therefore holds a path this Device owns, identical
on Windows (`%APPDATA%/LocalTransfer/bubble_skins`) and Android (the
app-private files directory the platform channel already provides). The
picker enforces the documented rules before the copy: PNG/JPG/WebP/BMP only
(GIF is refused even though `imageExtensions` accepts it — a skin is a
still), at most `bubbleSkinMaxImageBytes` (2 MB), with the cropping,
composition, scrim and minimum-width guidance shown in the dialog itself.

**The picker is a draft until 完成.** `BubbleSkinPicker` edits a local draft —
presets, a custom-gradient editor on `flutter_colorpicker`, bundled pictures,
the user's own picture with ink/scrim choices — and only `setBubbleSkin`
persists on confirm, so dragging a colour slider does not rewrite the
profile per tick. Historical messages pick up a new skin on the next
rebuild, which is the same behaviour WeChat has and costs nothing here
because the skin is resolved at paint time, not baked into records.

## Alternatives considered

**Inject the skin through `ThemeExtension`.** Rejected: it would put user
data into the theme layer the codebase deliberately keeps as designed
palettes, force `lerp`/`copyWith` semantics for a value that is not a
palette, and make "which skin applies" a function of theme state rather than
of the message's direction. Reading the controller directly keeps the
separation clean and the change to one call site.

**One skin shared by both sides.** Rejected by the user: the two sides of a
conversation are read differently — your own bubbles are "mine", the peer's
are "theirs" — and a single choice cannot express "green out, pink in".

**Store the picker's path and decode-check at render time.** Rejected:
Android's picker answers do not survive, and a `FileImage` that fails inside
a `BoxDecoration` has no `errorBuilder` to fall back through — the failure
would paint as a broken fill, not as the ordinary bubble. Copying at import
time makes the stored path durable by construction, and the missing-file
check in `bubblePaintFor` covers what remains (app data cleaned by hand or
the OS).

**Auto-derive ink from the picture's average luminance.** Rejected: decoding
every skin picture to compute a mean is real IO per bubble rebuild for a
number that is wrong often enough to matter on busy images. A binary ink
choice plus a live preview in the picker puts the legibility decision where
the user can see it.

**GIF skins.** Rejected: a `BoxDecoration` image shows one frame, so a GIF
would only ever show its first — a picture the user did not pick. The format
is refused at the dialog alongside the other rules.

## Consequences

**Bought.** Three skin sources in one pass — six designed gradient presets,
six bundled pictures, and user pictures under explicit rules — with
independent sides, a live preview, and persistence that survives restart and
is identical on both platforms. The wire protocol, the Owner Group, and every
peer-visible surface are untouched: a skin is local user data and never
leaves the Device.

**Cost.** `conversation_view.dart` now threads a resolved `BubblePaint`
through `_contents`/`_body`/`_image`/`_BubbleAction` instead of recomputing
`_bubbleInk(colors)` per call — a wider signature in exchange for one
resolution per bubble. The settings surface gained a section and a ~1000-line
picker; `flutter_colorpicker` is a new dependency for the custom-gradient
editor. Six generated PNG assets ship in `assets/bubble_skins/`.

**Testing.** `test/profile/bubble_skin_test.dart` covers the model's JSON
round-trip and every malformed-input fallback; `device_profile_test.dart`
covers the two slots' independence and tolerant decoding;
`app_controller_test.dart` covers persistence across a restart and the
import-copy contract; `test_flutter/ui/bubble_skin_test.dart` covers the
rendered paint per kind, per side, per source, and the missing-file
fallback, plus the picker's draft-and-confirm flow.

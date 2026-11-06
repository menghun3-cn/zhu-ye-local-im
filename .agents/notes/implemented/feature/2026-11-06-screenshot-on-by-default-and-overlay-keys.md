# Agent Note: Screenshot on by default, with customizable in-overlay keys

Status: implemented

English | [中文](2026-11-06-screenshot-on-by-default-and-overlay-keys.zh.md)

## Problem

[2026-11-20-windows-screenshot-tools](2026-11-20-windows-screenshot-tools.md)
shipped the capture overlay mouse-only and the whole feature behind a
switch that defaulted **off**, on the reasoning that a global hotkey
capturing the screen is the most invasive thing the app can do. Two
consequences showed up in use:

* A feature nobody can find is a feature nobody uses. The summon hotkey
  only exists once the switch is on, and nothing outside the "我的 → 截图"
  page says the feature exists at all.
* Once the overlay is open it owns the whole screen and the keyboard, yet
  every action — switch mode, finish, pin, cancel — required aiming at a
  toolbar button. Snipaste, the reference behaviour, is keyboard-first.

## Decision

**On for new Devices, untouched for existing ones.** The
`DeviceProfile.screenshotEnabled` constructor default flips to `true`;
`fromJson` still resolves a missing key to `false`. Every profile written
since the feature shipped carries the key explicitly, so the flip reaches
exactly the installs that never answered the question — an old profile is
not changed retroactively, and no "did the user ever touch this" flag was
needed.

**Six bindings, one per overlay action.** A `CaptureAction` enum
(`region`, `window`, `full`, `copy`, `pin`, `cancel`) maps to defaults
`q`/`w`/`e`/`enter`/`ctrl+enter`/`escape`, stored in the profile as
`captureKeys` — action wire name to normalized `modifier+key` string.
The grammar is a sibling of `isScreenshotHotkey`, not a reuse of it:
`isCaptureHotkey` accepts a **bare key** (the overlay has no other app's
shortcuts to defer to) and the named keys `enter`, `escape`, `space`,
`tab`, arrows and friends that a screenshot tool lives on. All bindings
pass through `normalizeCaptureHotkey`, so `shift+ctrl+a` and
`ctrl+shift+a` are the same stored string.

**The overlay matches keys itself.** A `Focus(autofocus: true)` above the
overlay's listener translates each `KeyDownEvent` — modifiers read from
`HardwareKeyboard`, since the event names only the key that went down —
into the same canonical string and dispatches the action. Returning
`handled` keeps `Enter` from also clicking a focused toolbar button, and
a `_capturing` guard makes a held key a single capture. The bindings
reach the overlay's separate engine through a new
`ScreenshotWindowArgs.overlayKeys` field — the arguments are the only
link a screenshot window has to the profile.

**The settings page lists all of them.** "我的 → 截图" gained a
截图内快捷键 card: one recorder row per action, each with its own
recorder and a reset-to-default. `DeviceProfile.setCaptureKey`
refuses malformed bindings and any binding another action already holds
— two actions on one key would make the overlay's dispatch a coin flip.
The controller adds one more refusal the profile cannot see: a binding
equal to the summon hotkey, which would re-open the overlay on every
press. `ScreenshotService.captureKeys` is pushed on every profile sync,
so an edited key applies to the next overlay without a restart.

## Consequences

* Fresh installs now register `ctrl+shift+a` at first run. That is a
  behaviour change for anyone who installs and never opens the settings
  page — accepted deliberately, and reversible in one tap.
* Bare-key bindings mean the overlay swallows plain letters while open.
  That is the point — the overlay is modal — but it also means a binding
  like `q` does nothing *outside* the overlay, which the settings copy
  now says ("截图遮罩打开时生效").
* Profiles written by this build carry `captureKeys`; an older build
  reading them ignores the unknown key, the same tolerance the hotkey
  string already relied on.
* The key-name bridge (`lib/ui/screenshot/capture_key_names.dart`) is
  shared by the recorder and the overlay on purpose: a binding the page
  accepts must be one the overlay can spell.

## Alternatives considered

**Flip existing users on too.** Rejected: the stored `false` cannot be
told apart from "never asked", and answering that honestly needs a
"user touched the switch" flag for a one-time migration. New-installs-
only was the scope asked for and the honest version of it.

**Reuse `isScreenshotHotkey` for overlay bindings.** Rejected: it
requires a modifier and excludes every named key, which would ban
exactly the `enter`/`escape` bindings the feature is expected to ship.
The grammars share shape and modifier names but not rules.

**Register the overlay keys through `hotkey_manager` as well.**
Rejected: the overlay is a separate window in a separate engine, and a
second round of global registrations would fire app-wide instead of only
while the overlay is up. Flutter key events inside the focused overlay
window are the correct scope.

**One profile field per action.** Rejected: six fields would need six
serializer branches and still could not grow a seventh action without a
format change; the map keyed by wire name degrades per-entry, which is
the tolerance this profile already practices.

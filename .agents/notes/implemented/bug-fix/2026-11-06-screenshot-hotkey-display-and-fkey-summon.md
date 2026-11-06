# Agent Note: Readable hotkey bindings and a bare-F-key summon hotkey

Status: implemented

English | [中文](2026-11-06-screenshot-hotkey-display-and-fkey-summon.zh.md)

## Problem

Two defects showed up together on the "我的 → 截图" page's hotkey rows:

* The row rendered hotkey_manager's `HotKeyRecorder`, whose built-in
  `HotKeyVirtualView` labels keys through `PhysicalKeyboardKey.keyLabel`.
  That getter resolves to the package's own symbol table — `⌃`, `⇧`,
  `⊞` — so `ctrl+shift+a` displayed as three chips reading "^", an
  upward arrow and "A". The binding worked; it just could not be read.
* `isScreenshotHotkey` required at least one modifier, so the one
  chord-free binding users actually ask for — a bare `F1` — was refused
  at the settings screen even though `hotkey_manager` registers it
  without complaint.

## Decision

**The page records keys itself and labels them itself.** `_HotkeyEditor`
in `screenshot_page.dart` is now a `StatefulWidget` that listens through
`HardwareKeyboard.instance` exactly like the recorder it replaced —
but only after the row is tapped: every row shares the same physical
keyboard, so an always-on listener would record one key press into all
seven rows at once, and a static `_armed` slot keeps exactly one row
listening. Modifier-only presses are ignored (they are the first half
of a chord), every other `KeyDownEvent` is translated by
`captureKeyName` plus the live modifier state into the profile's
`modifier+key` string, run through `normalizeCaptureHotkey`, and
filtered by the row's `accepts` grammar; a bare `escape` disarms on
rows whose grammar refuses it, which is the cancel gesture. The
display is `captureHotkeyLabel`, so the row reads
`Ctrl+Shift+A` — the same spelling the overlay toolbar hints already
use. hotkey_manager is still what registers the global hotkey; only its
widget was dropped.

**A bare `f1`–`f24` is now a legal summon hotkey.** `isScreenshotHotkey`
accepts a single function-key part; letters, digits and named keys still
require a modifier, because a bare `a` or `enter` would fire on ordinary
typing. `_parseAccelerator` needed no change — an empty modifier list was
always a valid `HotKey`. Both hotkey grammars also tightened their
function-key range to `f1`–`f24`, the range `captureKeyOf` and
`_parseAccelerator` can actually spell: `ctrl+f99` used to pass the
validator and then fail silently at registration.

## Consequences

* Every hotkey row on the page — the summon hotkey and all six overlay
  bindings — now shows readable labels instead of modifier glyphs.
* `f1` through `f24` can be bound globally with no modifier. The settings
  copy now says pressing a new chord rebinds the hotkey.
* Bare letters, digits and named keys remain refused for the global
  hotkey; the overlay bindings are unaffected and still allow them.
* A hand-edited profile carrying `f25`-or-later or `f0` bindings now
  falls back to defaults instead of registering nothing.

## Alternatives considered

**Keep `HotKeyRecorder` and restyle around it.** Rejected: its display
is `HotKeyVirtualView`, an internal widget with no label or theme hook —
the glyph output cannot be changed from outside, and forking the
recorder to fix a label is more code than the twenty lines of
`HardwareKeyboard` handling the page already needed for translation.

**Allow any bare key globally.** Rejected: a bare letter, digit or
`enter` fires while the user types in other applications — the hotkey
would break the machine it is meant to serve. Function keys are the
only keys nobody types on, which is why the exception stops there.

**Register through Flutter key events instead of `hotkey_manager`.**
Rejected: the summon hotkey must fire while another application has
focus, which only an OS-level registration can do. `hotkey_manager`
stays for registration; only its recorder widget was replaced.

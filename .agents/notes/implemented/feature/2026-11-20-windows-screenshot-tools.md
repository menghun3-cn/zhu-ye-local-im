# Agent Note: A Snipaste-style screenshot toolkit, Windows only

Status: implemented

English | [中文](2026-11-20-windows-screenshot-tools.zh.md)

## Problem

Users of a file-and-clipboard transfer app regularly need to grab what's on
screen — an error dialog, a chart, a message they want to paste elsewhere.
Snipaste is the reference behaviour: a global hotkey summons a fullscreen
dimmed overlay, you drag a region (or pick a window, or take the whole
screen), the image lands on the clipboard, and it can be pinned above other
windows or annotated. None of that existed here; the only clipboard story was
text, files and mirrored entries between paired Devices.

The ask was deliberately Snipaste-shaped rather than "add a screenshot
button": pin windows that persist across restarts, a floating history, an
annotation editor, and a customizable global hotkey, gated behind a switch
that is **off by default** because a global hotkey that captures the screen
is the most invasive thing this app can do.

## Decision

The feature is Windows-only and built from four pieces, each in its own
Flutter engine via `desktop_multi_window`:

* **Capture overlay** — one window covering the virtual screen
  (`GetSystemMetrics(SM_*VIRTUALSCREEN)`), always-on-top and
  click-through-free. Region drag, window mode (`EnumWindows` +
  `WindowFromPoint` + `PrintWindow`, which captures occluded windows), and
  full-screen mode, switchable from a toolbar. Finishing copies the PNG to
  the clipboard as `CF_DIB` — written by hand through Win32 because
  Flutter's `Clipboard` carries text only — and appends it to the history.
* **History** — a `ScreenshotLibrary` (index JSON + one PNG per entry,
  capped at 20) shown in a floating grid window, reachable from the overlay,
  a "我的 → 截图" card, and a new tray menu entry in the existing native
  `HostShell`.
* **Pins** — a `PinStore` of `PinRecord`s (geometry, always-on-top,
  click-through) restored on startup as borderless always-on-top windows.
  Click-through is `WS_EX_TRANSPARENT | WS_EX_LAYERED` plus pinned alpha,
  set through a unique window title → `EnumWindows` lookup, because every
  pin engine shares one process id and `desktop_multi_window`'s windowId is
  a UUID, not an HWND.
* **Annotation editor** — arrows, rectangles, freehand brush, text and
  numbered markers drawn over the image; on 完成 the strokes are replayed
  through `ui.PictureRecorder` and the PNG is rewritten in place, so the
  history entry or pin stays the same file.

The enable switch and hotkey live in `DeviceProfile`
(`screenshotEnabled`, `screenshotHotkey`, default `ctrl+shift+a` — chosen
over the `Ctrl+Alt` family QQ and WeChat already own globally). A
`ScreenshotService` in the main engine reconciles registration through
`hotkey_manager` and pushes the enabled flag to the tray menu over the
existing host channel; disabling unregisters the hotkey and hides the
entries but keeps pins and history, which are the user's pictures.

UIA control-boundary snapping was explicitly deferred: no plugin offers it
and v1 ships ordinary reference-line selection.

## Consequences

* The feature adds five runtime dependencies (`desktop_multi_window`,
  `window_manager`, `hotkey_manager`, `win32`, `image`, plus `ffi` declared
  directly) and a small amount of hand-rolled Win32. The GDI and clipboard
  code is the part most likely to need attention on unusual setups —
  multi-monitor negative origins are handled, mixed-DPI is approximated by
  the overlay window's own DPI.
* Pins restore on every launch while the feature is enabled; a user who
  wants them gone closes each pin, which deletes its record.
* The hotkey string is profile data, so an older build reading a profile
  written by a newer one simply falls back to the default — the tolerant
  parse is deliberate.
* Android is untouched: the "我的" card, the service and the tray entry all
  sit behind `DevicePlatform.windows`.

## Alternatives considered

**`screen_capturer` / `flutter_screen_capture` for pixels.** Rejected for
the core path: they bring their own overlay or file-based flows and cannot
drive the Snipaste interaction (mode switching inside one overlay,
window-under-cursor highlight, occluded-window `PrintWindow`). The GDI path
in `win_desktop.dart` is ~150 lines and does exactly what is needed.

**`tray_manager` for the history entry.** Rejected: the app already owns a
native notification-area icon in `host_shell.cpp` with a hand-built menu;
a second tray icon would be a duplicate. One menu item and one channel
method (`setScreenshotEnabled`, `screenshotHistory`) extended the existing
shell instead.

**`window_manager` 0.6.x / `hotkey_manager` 0.3.x.** Held back deliberately:
both latest releases are days old and 0.6.x rewrites window_manager onto
`nativeapi`, which this feature does not need. 0.5.2 / 0.2.3 are the
versions the plugins' own examples target.

**Passing images between engines as bytes.** Rejected: every window reads
its PNG from the library/pins directory named in its `WindowConfiguration`
arguments, which also makes pin restore and editor-reopen identical paths —
and keeps large bitmaps out of the argument channel entirely.

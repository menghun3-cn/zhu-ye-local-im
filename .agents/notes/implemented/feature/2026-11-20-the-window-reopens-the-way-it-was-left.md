# Agent Note: The window reopens the way it was left

Status: implemented

## Problem

The main window always opened at its created size, whatever state the user
had left it in. Someone who works with the window maximized had to maximise
it again after every start and after every update — the update hand-off
restarts the process, so "next time" included "right after I updated". The
windowed case had the mirror problem in miniature: there was no record of
either state, so the choice the user made by dragging the title bar was
simply not kept.

## Decision

`HostShell` — which already owns the window facts Dart cannot reach, the
tray icon and the autostart entry — now also owns the maximized bit. It is
stored as `WindowMaximized` (REG_DWORD) under
`HKCU\Software\cn.hnasct.local_transfer`, read once in `Attach` and written
back by `set_maximized` only when the value actually changes. The registry
rather than the profile file because the window is created in
`main.cpp`/`FlutterWindow::OnCreate`, before Dart has opened a single seam;
the native side has to answer for itself.

`FlutterWindow::OnCreate` asks `host_shell_.maximized()` while the window is
still invisible and calls `Win32Window::SetShowMaximized()`, which makes the
first `Show()` — still deferred to the first frame — present the window with
`SW_MAXIMIZE` instead of `SW_SHOWNORMAL`. `SW_SHOWNORMAL` on an already
maximised window would restore it, so the decision has to live in the show
command rather than in an earlier `ShowWindow` call.

`WM_SIZE` is the writer: `SIZE_MAXIMIZED` and `SIZE_RESTORED` both record
`IsZoomed(hwnd)`, while `SIZE_MINIMIZED` is ignored — a minimised window is
still a maximised one underneath, and asking `IsZoomed` during minimise
would wrongly clear the bit. Asking `IsZoomed` rather than trusting the
`wparam` keeps the record honest across hide-to-tray and restore, where the
size codes alone do not say what the window is.

Only the maximised bit is kept, deliberately: a remembered windowed
rectangle can land off-screen or on a disconnected monitor after a hardware
change, so a non-maximised start always uses the created 1280×720 geometry.

## Alternatives considered

**`window_manager`'s `setBounds`/`getBounds` persistence.** Rejected: the
plugin is already a dependency for the screenshot windows, but the main
window is a hand-rolled `Win32Window` shown before any Dart runs, and
`window_manager` is a Dart-side API — the state would still have to cross
the same native/Dart boundary, only with a plugin in the middle. The runner
already reads and writes `HKCU` for autostart; one more value beside it is
the smaller mechanism.

**Persist position and size alongside the maximised bit.** Rejected for
now: it is the fuller answer, but it drags in monitor-DPI and
disconnected-display edge cases that the maximised bit does not have, and
the request was only ever "maximised stays maximised, windowed stays
windowed". The created size remains the windowed geometry.

**Store the bit in the profile file and push it down a method channel.**
Rejected: the window is shown before the profile store exists, so Dart
would always be one frame late — the window would flash at the wrong state
and then jump. The native read has to happen where the window is created.

## Consequences

- A maximised window reopens maximised after a normal start, after a
  close-to-tray exit, and after an update hand-off — the registry is per
  user, not per install path, so a moved or updated executable keeps it.
- The first `WM_SIZE` of a maximised restore does not rewrite the value:
  `Attach` seeds `maximized_` from the registry before any size message can
  arrive, and `set_maximized` writes only on change.
- The state is per Windows user, not per Device profile — the same choice
  the autostart entry already makes, and the right scope for a window
  rectangle.
- `windows/runner` is C++ the Dart test suites cannot reach; the behaviour
  is verified by building the runner and exercising maximise/restore across
  restarts rather than by an automated test.

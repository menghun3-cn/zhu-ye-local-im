# Agent Note: The tray icon appears with the window

Status: implemented

English | [中文](2026-10-26-tray-icon-appears-with-the-window.zh.md)

## Problem

The notification-area icon was added only when the window was first hidden by
its close button. While the application was visible in the taskbar there was
no tray icon, and the tray was the only place that offered "exit". A user who
saw the window in the taskbar had no visible way to quit the application, and
the inconsistency read as a missing feature.

## Decision

`HostShell::Attach` adds the tray icon at the same moment it adopts the window,
instead of waiting for the first `WM_CLOSE`. The icon therefore appears as
soon as the window exists, stays through the window's visible lifetime, and is
already there when the close button hides the window. The `WM_CLOSE` path and
the `TaskbarCreated` recovery both keep working unchanged, because
`AddTrayIcon` is idempotent and is still used by both of them.

## Testing

This is native runner code: it is covered by building the Windows target and
by the packaging script that starts the built executable and probes its
behaviour. No Dart test can observe `Shell_NotifyIcon`.

## Alternatives considered

**Keep the icon close-hide-only and document the tray in the window chrome.**
Rejected: the tray already exists as the exit route, and a window that shows
no tray icon while its only quit action sits in the tray is a user-facing bug
rather than a documentation gap.

**Add a Dart-side setting to choose when the icon appears.** Rejected: the
host already knows how to place the icon, and adding an interface so a Flutter
widget can ask for what the host should always do multiplies the moving parts
for no behaviour the user asked about.

## Consequences

- The tray icon is present from the moment the window exists.
- The taskbar and the notification area never disagree about the application
  being on screen again.
- "Exit" and "show main window" are available from the tray on first launch,
  not only after the window has been hidden once.
- The close-to-tray safety check still refuses to hide the window if the icon
  could not be added.

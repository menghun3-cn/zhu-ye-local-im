# Agent Note: The desktop host shell: one instance, a tray, and a close button with a meaning

Status: implemented

## Problem

The application shipped as a desktop window while behaving like a page in a
browser. Four things were missing, and not one of them can be asked for from
Dart: the language has no window handle, no notification area, and no registry.

**A second launch was a second application.** Two windows on one machine are two
Devices with two identities, two of everything on the Devices surface, and the
same file arriving twice.

**The close button always ended the process.** For an application whose entire
purpose is to receive things over the network, that is the wrong default. Closing
the window is how a user stops looking at it, not how a user stops being
reachable.

**There was no way to start with Windows**, so a Device meant to be reachable had
to be started by hand after every restart.

**Nothing in Settings could change any of the first three** — and Android, which
has neither a notification area nor a close button of its own, must not be
offered rows with nothing behind them.

The last point has a second half that is easy to miss, and it shapes how this was
built: the gates do not compile `windows/**` at all. `analysis_options.yaml`
excludes it, `dart format` does not read C++, and no test suite builds it. What
the runner does is verified by building the runner, and by nothing else.

## Decision

A `HostShell` — plain Win32, with no Flutter in it — in
`windows/runner/host_shell.{h,cpp}`, driven from two places: the window's message
handler, and one method channel, `cn.hnasct.local_transfer/host`.

**Single instance is a named mutex, taken before there is a window.**
`wWinMain` calls `HostShell::AcquireSingleInstance()` before COM is initialised
and before any window exists. The name is a `Local\` one, so a second signed-in
session — or a second user — running the application is a second and entirely
legitimate instance. When the mutex is already held, the new process finds the
window that holds it, calls `AllowSetForegroundWindow` for that window's owner,
posts a registered message, and exits without ever creating a window of its own.
The `AllowSetForegroundWindow` is not decoration: without it Windows raises the
window behind whatever the user clicked from, which reads as the second launch
having done nothing at all.

**The runner's window class is no longer Flutter's default.** It was
`FLUTTER_RUNNER_WIN32_WINDOW`, a name every Flutter Windows application shares. A
second launch that looked for a window by that name could raise an unrelated
program's window and then exit silently. It is now
`cn.hnasct.local_transfer.window`, declared in `win32_window.h` as
`kWin32WindowClassName` so that the window and the hand-off cannot drift apart.

**The close button has a stored meaning.** `CloseBehaviour` — `quit` or `tray` —
lives in the profile beside the other user settings, and the default is `tray`:
`WM_CLOSE` hides the window and the process keeps running, so it can still
receive. Dart pushes the choice to the host twice over: once as the Device comes
up, before anything slower happens, and once whenever the user changes it.

**The notification-area icon is added the first time the window is hidden, and
only then.** An application opened to send one file does not leave a permanent
entry behind it. `WM_CLOSE` is swallowed *only if the icon could be added*: a
window that hides with no way back is a process the user cannot reach, and
`Shell_NotifyIcon` failing is a real possibility rather than a theoretical one.
The icon is put back on the shell's `TaskbarCreated` broadcast, which is the one
moment Windows drops every icon at once.

**Starting with Windows is read, never remembered.** The entry is
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run\LocalTransfer`, holding the
quoted path of the running executable — quoted because the entry is launched as a
command line and the path routinely contains spaces. Nothing about it is cached
on the Dart side: `autostartEnabled` asks the registry, and `setAutostart` reads
the answer back *after* writing. A write that failed, and a user who deleted the
entry by hand, therefore both surface as what will actually happen rather than as
what was asked for.

## What Dart decides, and what the host decides

`PlatformSeams` carries two separate facts, and they are separate on purpose.

`hostShell` is always present, on every platform. It holds the `HostShell`
implementation, and a platform that has not implemented the channel answers
`MissingPluginException`, which `PlatformHostShell` turns into "nothing
happened". A settings screen that could not be drawn because a tray icon was
unavailable would be a worse outcome than a switch that quietly does nothing.

`controlsWindow` is a plain bool, true only on Windows. It is what the Settings
surface branches on to decide whether the group is drawn at all — absent rather
than disabled, because a surface that lists what a platform cannot do is a
surface that reads as broken. It is synchronous and known before anything is
awaited, which is why it is not derived from asking `hostShell`: that would put
an await inside building a page, and make "is this row offered" depend on whether
the platform is currently answering.

## Testing

`test/profile/device_profile_test.dart` covers the profile field: the default,
the round trip, the two wire names, and the tolerant decode that makes a value
from a newer build read as the default rather than fail an older one.

`test_flutter/ui/window_settings_test.dart` covers the Settings surface against
`ScriptedHostShell`: that the group is absent when `controlsWindow` is false, that
the close choice reaches both the running window and the stored profile, that a
host which already starts with the system is what the switch shows *without*
anything having been asked, and that a write which does not take leaves the switch
off rather than on.

The runner itself has no test. It is verified by being compiled —
`cmake --build build/windows/x64 --config Release --target local_transfer` — which
is the only command in the project that compiles `windows/**`.

## Alternatives considered

**A pub plugin.** `launch_at_startup`, `tray_manager`, `window_manager` and one of
the single-instance packages would together cover all four behaviours. They lost
on a standing decision of this project: the application ships no plugins, so that
every platform fact it depends on is written down in this repository and can be
read. Four packages would have added four maintainers, four platform-channel
surfaces and a transitively large dependency graph in exchange for questions that
are about three hundred lines of Win32 — and the two channels this project does
have, `.../host` and `.../paths`, are already its own.

**One channel per fact.** Three channels, one each for the close behaviour and
the two halves of autostart. Rejected: all of them are answered by the same
window, and the runner's handler would have become a lookup table of one.

**Deriving `controlsWindow` from whether `hostShell` answers.** Rejected: it makes
a question that is known synchronously — can this build change its own window —
depend on an awaited platform call, and it makes the shape of a page depend on
whether the platform is currently reachable.

**Remembering the autostart state in the profile.** Rejected: a second copy of a
fact the operating system owns. The two could disagree, and the copy would be the
one that is wrong.

**`SetQuitOnClose(false)`, so that closing never ends anything.** Rejected:
quitting has to keep working, and `quit_on_close_` is what ends the message loop.
It is still `true`. The tray path hides the window *instead of* closing it, so
`WM_DESTROY` and `PostQuitMessage` still happen the ordinary way when the user
really does mean to quit — including from the notification-area menu, which posts
an ordinary `WM_CLOSE` with the flag already flipped.

**An icon visible from startup.** Rejected: it leaves a permanent notification-area
entry behind an application the user may have opened to send a single file.

## Consequences

**Bought.** The application can be left running with no window on screen and still
receive things; two launches are one window; starting with Windows is a switch
that reports what the operating system will actually do; and the close choice
survives a restart, because it is a profile field rather than window state.

**The runner sits outside every gate.** `analysis_options.yaml` excludes
`windows/**`, and no test suite builds it, so a mistake there is caught by
compiling it and by nothing else. Every source under `windows/runner` is also pure
ASCII with `\uXXXX` escapes: a non-ASCII byte in a runner source file is C4819
under code page 936, which this project's `/WX` promotes to a hard error.

**Known gaps.** The notification-area menu's two labels — show the window, exit —
are the host's own escaped literals rather than localized strings, because the menu
is built by the runner and reaching into Dart for two words would mean the menu
could not be drawn while the engine was busy. `HKCU\...\Explorer\StartupApproved\Run`
is not consulted, so an entry the user disabled from Task Manager still reads as
on; turning the switch off and on again rewrites it. And only Windows implements
the channel — `controlsWindow` exists precisely so that the other platforms do not
pretend otherwise.

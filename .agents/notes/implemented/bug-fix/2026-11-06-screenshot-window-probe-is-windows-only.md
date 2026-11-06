# Agent Note: The screenshot window probe only runs on Windows

Status: implemented

English | [中文](2026-11-06-screenshot-window-probe-is-windows-only.zh.md)

## Problem

v0.1.36 shipped the Windows screenshot toolkit, and `main` opened with an
unconditional `await ScreenshotWindowArgs.current()`. That call reaches
`WindowController.fromCurrentEngine()` in `desktop_multi_window`, which asks
the `mixin.one/desktop_multi_window` channel for `getWindowDefinition`. The
plugin has no Android implementation, so on Android the await threw
`MissingPluginException` — before `runApp`, and outside the `try` that turns
seam failures into `StartupFailureApp`. The process stayed alive with
nothing drawn: the whole app opened to a blank window. Windows was
unaffected because its runner does implement the channel.

## Decision

`main` asks the question only when `currentPlatform() ==
DevicePlatform.windows`, the one platform whose runner can spawn the extra
engines the arguments belong to. The comparison is written out rather than
inferred from "the plugin might not exist", for the same reason
`controlsWindow` is: adding a platform is a decision somebody has to make
next to the reason it is not in the list. Everywhere the screenshot feature
is otherwise reached — `ScreenshotService.open`, the settings rows — is
already gated on the same comparison in `_LocalTransferAppState`, so this
was the only unguarded call site.

## Testing

`main` is not reachable from a test — it binds the discovery port and calls
`runApp` — so nothing automated pins the guard; the check is one
`currentPlatform()` comparison reviewed against the call it protects. The
regression it fixes is platform-level (a channel with no implementation),
which no `dart test` suite on a Windows host can reproduce anyway: the
proof is the Android build opening to the app rather than to nothing.

## Alternatives considered

**Catch `MissingPluginException` inside `ScreenshotWindowArgs.current()`.**
Rejected as the only fix: it would make the function silently answer "no
window" on every platform that cannot host one, hiding the fact that the
question should never have been asked. The platform gate says *why* the
answer is null; a swallowed exception only says the answer happened to be
null this time.

**Move the check into `current()` as `Platform.isWindows`.** Rejected:
`Platform.is*` answers the host, not the project's platform vocabulary —
`DevicePlatform` is what the rest of the startup path compares against, and
a second dialect of the same question is how the two drift apart.

**Give the plugin an Android no-op implementation.** Rejected: there is no
Android side to implement — the feature is Windows-only by design, and a
stub channel exists only to make a call that should not happen return
something.

## Consequences

- Android opens to the application again; the screenshot code is never
  touched there, matching how `_openScreenshots` already gated the service.
- A future platform added to `DevicePlatform` gets `windowArgs == null` by
  default — the safe answer — until somebody decides it can host the
  feature and says so at the comparison.
- The Windows multi-window flow is unchanged: the main engine's arguments
  are still empty, decode to null, and the app proceeds as before.

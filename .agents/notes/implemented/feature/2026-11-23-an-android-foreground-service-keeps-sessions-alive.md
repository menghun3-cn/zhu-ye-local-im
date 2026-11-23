# Agent Note: An Android foreground service keeps Sessions alive in the background

Status: implemented

## Problem

On Android the whole product — the UDP broadcast listener, the TCP
Sessions, the Dart timers — lives in the app process, and Android freezes
or kills a backgrounded process. Switching to another app therefore took
the Device offline: discovery stopped announcing, peers' keep-alives
expired, and the app looked dead until it was reopened. The broadcast
discovery note already named this as an open Android-layer decision
("whether discovery runs only in the foreground"), and the background
constraints doc recorded the `dataSync` budget without a shipped answer.

## Decision

`LocalTransferForegroundService` (hand-written Kotlin, no plugin) is
started from `MainActivity.onCreate` via `startForegroundService` and
calls `ServiceCompat.startForeground` with type
`FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE`. The service does nothing
itself; its only job is holding the process at foreground priority so
the sockets and timers inside it keep running while the user is in
another app. A persistent `IMPORTANCE_LOW` notification ("正在局域网中
保持在线") explains the standing task to the user; tapping it relaunches
the activity.

- The service is `START_NOT_STICKY` and stops itself in `onTaskRemoved`:
  the user swiping the app away is a deliberate "go offline", and a
  restarted service would come back with no Flutter engine and dead
  sockets — a notification that lies.
- `connectedDevice`, not `dataSync`: on Android 15+ `dataSync` carries a
  6-hours-per-24 budget that a stay-resident app would hit; `connectedDevice`
  has no such timeout. Android 14+ requires a connectedDevice service to
  hold one of a fixed set of permissions, so the manifest declares
  `CHANGE_WIFI_MULTICAST_STATE` — the honest pick, since LAN discovery is
  broadcast-adjacent and the same permission is what a future
  MulticastLock needs.
- Android 13+ hides the notification until `POST_NOTIFICATIONS` is
  granted; `MainActivity.onResume` asks once (flagged in SharedPreferences)
because the service still runs without it — only the shade entry is
missing, and a user who never sees it has no idea the app stays online
on purpose.
- Dart changes: none. The service only preserves the process; the network
  stack is untouched.

## Alternatives considered

**`dataSync` foreground service type.** Semantically the closest (sync /
transfer), but Android 15+ caps it at 6 hours per 24 and calls
`onTimeout` — wrong shape for a stay-resident app. Rejected.

**`specialUse` type.** No time budget, but it needs a manifest property
justifying the subtype and has fuzzier review semantics; `connectedDevice`
is cleaner for "stay connected to LAN peers". Rejected.

**A plugin (`flutter_foreground_task` et al.).** Mature and feature-rich,
but it breaks the project's zero-plugin constraint and the pure-Dart
headless-testable core for 5% of what it offers. Rejected.

**WakeLock/WifiLock only.** Keeps the CPU awake but the process can still
be frozen or killed; alone it buys little. Screen-off (doze) keep-alive is
a separate decision and is out of scope here. Rejected for this change.

## Consequences

- Switching apps no longer takes the Device offline; the notification is
  the visible price, and it is honest about what the app is doing.
- The app now holds four new manifest permissions
  (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`,
  `POST_NOTIFICATIONS`, `CHANGE_WIFI_MULTICAST_STATE`), all normal or
  runtime-grantable; none expose new data.
- Screen-off doze can still suspend sockets — this change covers the
  "switched apps" case only. If field reports show screen-off drops, the
  next step is a partial wake lock, decided separately.
- Battery cost is the foreground-service baseline: the process stays
  runnable, which is what the product needs to be a peer at all times.
- Verified by `flutter analyze`, `dart format`, `dart test`, and the
  agent-note/translation gates; the Kotlin side compiles as part of the
  normal Android build. Real-device verification (switch apps → peer
  stays online; swipe away → goes offline) is recorded as the manual
  check, not automated.

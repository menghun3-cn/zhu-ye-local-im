# Agent Note: Verify the core with `dart test` where `flutter test` cannot run

Status: implemented

English | [中文](2026-09-29-dart-test-as-the-core-gate.zh.md)

## Problem

[AGENTS.md](../../../../AGENTS.md) §5 makes `flutter test` the acceptance gate.
On this development machine `flutter test` cannot run at all: every test file
fails while loading with `Invalid WebSocket upgrade request`. The cause is
environmental, not in this repository. The Sangfor aTrust zero-trust client
installs a Winsock LSP that forwards loopback HTTP but strips the hop-by-hop
`Connection` and `Upgrade` headers, so the WebSocket the Flutter test harness
opens against its own `flutter_tester` process never completes its handshake.
Plain HTTP on the same socket is unaffected, and the state flips between working
and broken within minutes as the client updates itself.

A gate that cannot run is not a gate. Leaving it in place either blocks all work
or trains everyone to ignore a red result.

Two later problems made the first answer insufficient:

- `lib/ui/` grew real widgets. Widget tests import `package:flutter_test`, which
  the pure Dart VM cannot run at all, so they cannot live where the working gate
  looks.
- `dart test` discovers `test/` and nothing else. A widget test dropped into
  `test/` therefore breaks the one suite that is guaranteed to run on this
  machine — the exact failure the first decision existed to prevent — and it
  breaks it on a machine that has no way to fix the breakage.

## Decision

The suite is split by what can run it, and the split is by directory:

| Directory | What it holds | What runs it |
| --- | --- | --- |
| `test/` | Tests with no widget tree | `dart test` |
| `test_flutter/` | Tests that import `package:flutter_test` | `flutter test test_flutter` |

`lib/core/` and `lib/app/` import nothing from Flutter — only `dart:*`,
`package:crypto`, `package:cryptography` and each other — so `dart test` runs
every test in `test/`, including those that bind a real loopback TCP socket.
`test/app/plain_dart_test.dart` enforces that claim instead of assuming it: it
scans both layers for a `package:flutter` import and fails if one appears.

`test_flutter/` is the second gate, and it is the one this machine usually
cannot run. `flutter analyze` **does** run here — it reaches the analysis server
over stdio rather than a loopback WebSocket — and it covers `test_flutter/`, so
the widget suite is type-checked on every change even when it cannot be executed.
That is a real but partial guarantee and is not treated as a substitute.

`test/widget_test.dart`, the counter test `flutter create` leaves behind, was
deleted rather than left failing: it asserted against an app shell this
increment does not touch, and it cannot execute here.

The gate is therefore:

```powershell
.\scripts\verify-agent-notes.ps1
.\scripts\verify-translation-pairs.ps1
flutter analyze
dart format --set-exit-if-changed .
dart test
flutter test test_flutter
```

`flutter test` with no path would also collect `test/`; the widget gate is
written with the explicit path because a second runner over the pure Dart suite
adds cost and no coverage — and because on a machine where the widget runner is
broken, the narrower command is the one whose result means something.

Beyond the two suites, this decision covers how the platform-dependent branches
are reached at all. `openPlatformSeams` takes four optional parameters —
`platform`, `environment`, `pathsChannel` and `beacon` — which exist so that a
test can ask what the Android and Windows rules resolve to, and what the app
does with the answer, without being on Android, without reading the real
`%APPDATA%`, and without binding the well-known discovery port that only one
process per host may hold. Production passes none of them.

## Alternatives considered

**Run `flutter test` and accept the failures.** Rejected: a permanently red gate
hides real regressions in exactly the tests it reports, and the failure is a
load-time error in every file rather than a specific failing assertion.

**Make uninstalling the aTrust client, or allow-listing the Flutter binaries, a
prerequisite.** Rejected as a blocking dependency: it is a corporate security
client on a managed machine, so it is not this repository's call to remove, and
a gate that needs an IT ticket is not one a contributor can rely on. It is
recorded here as the real fix if someone with admin rights wants `flutter test`
back.

**Keep every test in `test/`.** Rejected: it would break `dart test` — the one
runner that always works here — the moment the first widget test was added, which
inverts the whole point of the first decision.

**Put the widget tests in `test/` and accept `dart test` failing on them.**
Rejected as the same mistake as the previous one with a different label.

**Move the core into its own Flutter-free package and test it there.** Rejected:
it buys nothing over the current arrangement. `lib/core/` already has no Flutter
dependency, and a second package would add a pubspec, a version and a dependency
edge for a boundary the import graph already enforces.

**Test the core through `flutter test` so one runner covers everything.**
Rejected: it couples a deliberately Flutter-free layer to the one toolchain that
cannot run here.

**Reach the Android and Windows branches by mocking at the `ProfileStore` and
`BeaconTransport` level instead of at a channel and a port.** Rejected for these
two: it would test what the app does *given* a resolved path while leaving the
resolution itself — the part that differs between the platforms — unexercised,
which is the part most likely to be wrong.

## Consequences

- `dart test` covers `lib/core/` and `lib/app/` completely, including real-socket
  behaviour. It runs in a single process with no build step, and the whole suite
  finishes in a few seconds. It is the gate that can always be run.
- Widget tests exist and are gate-able: `test_flutter/` holds a UI harness, per
  surface tests, and an end-to-end test that pairs two Devices and moves a file
  between two widget trees in one process.
- **The widget suite cannot be executed on this machine.** On a day when the LSP
  is interfering, `flutter test test_flutter` fails at load for every file.
  `flutter analyze` still type-checks it. The gap is named, not hidden, and the
  honest reading of a green `analyze` is "it compiles", never "it works".
- The core's and the app layer's Flutter-freedom is load-bearing rather than
  incidental: an import of `package:flutter` under `lib/core/` or `lib/app/`
  breaks the gate. That is a deliberate constraint, not an oversight.
- `lib/ui/` now carries four optional parameters that exist only for tests. They
  are documented as such at their definition, and the cost is real: the seam
  widens the signature every caller reads. It was accepted because the Android
  and Windows branches of `openPlatformSeams` are otherwise unreachable from one
  machine, and unreachable code is where the bugs in this file went unnoticed
  once already.
- The gate deviates from AGENTS.md §5 in shape, which still names a bare
  `flutter test`. §5 is the convention contributors read; this note is the record
  of why the split exists.

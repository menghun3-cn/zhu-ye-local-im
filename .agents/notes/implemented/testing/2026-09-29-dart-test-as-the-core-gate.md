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

## Decision

The core is verified with `dart test`, and that is the gate for `lib/core/`.
`lib/core/` imports nothing from Flutter — only `dart:*`, `package:crypto` and
`package:cryptography` — so the pure Dart VM runs every one of its tests,
including those that bind a real loopback TCP socket. `flutter analyze` and
`dart format --set-exit-if-changed .` are unchanged and still cover the whole
repository.

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
```

`flutter test` remains the intended gate for widget tests on a machine where the
LSP does not interfere, and nothing in this decision prevents using it there.

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

**Move the core into its own Flutter-free package and test it there.** Rejected:
it buys nothing over the current arrangement. `lib/core/` already has no Flutter
dependency, and a second package would add a pubspec, a version and a dependency
edge for a boundary the import graph already enforces.

**Test the core through `flutter test` so one runner covers everything.**
Rejected: it couples a deliberately Flutter-free layer to the one toolchain that
cannot run here.

## Consequences

- `dart test` covers the core completely, including real-socket behaviour. It
  runs in a single process with no build step, and the whole suite finishes in a
  few seconds.
- The core's Flutter-freedom is now load-bearing rather than incidental: an
  import of `package:flutter` anywhere under `lib/core/` would break the gate.
  That is a deliberate constraint, not an oversight.
- Widget tests are a named coverage gap on this machine. None exist for the app
  shell, and none will be written until the UI shell exists and a machine can
  run them.
- The gate deviates from AGENTS.md §5, which still names `flutter test`. This
  note is the record of why the core gate is `dart test` here, so the deviation
  is a decision rather than drift.

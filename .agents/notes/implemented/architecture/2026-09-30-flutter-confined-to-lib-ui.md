# Agent Note: Flutter is confined to `lib/ui`

Status: implemented

English | [中文](2026-09-30-flutter-confined-to-lib-ui.zh.md)

## Problem

The [application layer](2026-09-30-app-layer-plain-dart-orchestration.md) is
plain Dart, and `test/app/plain_dart_test.dart` walks `lib/core` and `lib/app`
and fails on any `package:flutter` import. That rule covers two layers, and the
widgets about to be written needed a third. The tempting place for them is
beside the controller they call: a page and the object it drives in one folder
needs no import and no explanation.

What that costs is the property the whole acceptance strategy rests on. On this
development machine `flutter test` cannot start at all — the zero-trust client
strips the hop-by-hop headers a loopback WebSocket upgrade needs, so the runner
never reaches `flutter_tester` (recorded in
[the dart-test gate note](../testing/2026-09-29-dart-test-as-the-core-gate.md)).
The only tests that run here are `dart test`, and they can only run against
code with no Flutter in it. If a widget may live anywhere, then "can this file
be tested on this machine" is answered by reading it, one file at a time.

## Decision

**`lib/ui` is the only place under `lib` that may import `package:flutter`.**
`lib/main.dart` is the single exception: the entry point has to import
`runApp` and Material, and a rule with one named carve-out is more honest than
one that forces the entry point into a folder named after the framework.

The rule is enforced rather than asserted. `test/app/plain_dart_test.dart` walks
every `.dart` file under `lib`, skips `lib/ui/` and `lib/main.dart`, and fails
if any of the rest imports `package:flutter`; it also fails if it scanned fewer
than twenty files, so a moved or mis-rooted walk cannot pass for the wrong
reason. A second case in the same group asserts that `lib/ui` exists and holds
more than four files, so the skip list cannot become a way to pass by deleting
things.

**The layering below is one-way.** Widgets import `lib/app` and `lib/core`;
nothing under `lib/app` or `lib/core` imports `lib/ui`. `lib/main.dart` does as
little as it can: open the platform seams, run the application, show a failure
screen if either throws.

## Alternatives considered

**Let the widgets live in `lib/app`, beside the controller.** Rejected: it makes
the existing plain-Dart claim false for half of the folder, so the enforcement
test would have to become a per-file allow-list — the same rule, with more
places to get it wrong, and a new file that silently lands on the wrong side.

**A separate package for the user interface** (`packages/ui`, or a workspace
tool to tie it together). Rejected: one application and two platforms, with
nothing to publish. A package boundary would buy a compiler-enforced rule at the
price of a second `pubspec.yaml`, a path dependency, and every editor and CI
setting that goes with a workspace — where a test that walks the tree buys the
same rule for twenty lines.

**Leave it as a convention written in `AGENTS.md`.** Rejected: this repository's
own history is that an unchecked claim rots. A frame's payload was aliased for
as long as nothing asserted the bytes, and an `onError` callback with the wrong
signature failed only when an error actually arrived. So the convention is
written down *and* checked, and the check is in the same suite the change has to
pass.

**Prohibit Flutter outside a `lib/flutter/` folder, `main.dart` included.**
Rejected: a rule whose exception is a file every Flutter developer already
recognises as the entry point is easier to hold in mind than one that pretends
the entry point is a widget folder.

## Consequences

- "Does this file need a widget tree to test" is answered by its path — the only
  answer available on a machine where no widget test can run. `lib/core` and
  `lib/app` stay wholly covered by `dart test`; `lib/ui` is covered by
  `flutter analyze` and by a real build.
- The rule constrains later work as much as this change. A widget that wants to
  hold real logic — a clipboard watcher, a path resolver — has to be written in
  a layer that can be tested. Both pieces this change needed went down into
  `lib/core` for exactly that reason, and came back with 13 cases of their own.
- A Flutter-typed helper (`IconData`, `Color`, `TextStyle`) can never live below
  `lib/ui`, so `labels.dart` and `widgets.dart` are presentation by construction.
  Nothing keeps them trivial, and nothing should: the rule fixes where such
  types may appear, not how much of them there may be.
- `lib/ui` is invisible to the plain-Dart test, so an import it should not have —
  `lib/ui` reaching into `lib/core`'s internals, or a page importing a page — is
  not caught by it. What catches a *broken* import is `flutter analyze`, and what
  catches a *wrong* one is review; the boundary is enforced in one direction
  only, and this is the direction that is cheap to check.

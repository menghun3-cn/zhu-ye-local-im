# Agent Note: Make the ControllerScope tell its dependents that something changed

Status: implemented

English | [中文](2026-09-30-controller-scope-never-notified-its-dependents.zh.md)

## Problem

`ControllerScope` is how every page in this app reaches the controller: a page
calls `ControllerScope.of(context)` inside its own `build` and holds no
subscription of its own. The class documents the arrangement in its header — one
notification at the root per change, rather than a subscription per widget — and
the mechanism is `_ControllerProvider.updateShouldNotify`:

```dart
bool updateShouldNotify(_ControllerProvider oldWidget) =>
    !identical(oldWidget.controller, controller);
```

Both operands are the same object. `_ControllerScopeState` holds one controller
for the life of the scope and hands that same instance to `_ControllerProvider`
on every rebuild, so `identical` was always `true` and this always answered
`false`.

Nothing else in the arrangement could carry the notification instead. The
`child` passed to `_ControllerProvider` is the widget instance the state was
given at `pumpWidget` time — it never changes — and Flutter's `updateChild`
skips a subtree whose widget instance is identical. So the scope rebuilt, and
reached nobody. Every page that read the controller stayed at its first build.

The symptom was visible only once the widget suite could be run at all. In the
two-window end-to-end test, pairing completed: both sides confirmed the digits
and both controllers reported `isServing`. The comparison dialog advanced,
because a dialog's stepping is its own local state. But the Devices page never
re-rendered to its paired wording — `Pair another Device` never appeared, and
the test hung waiting for a screen that was never going to change. The
assertion was right; the screen was frozen.

Nothing had caught this before for two separate reasons. The plain Dart suite
drives `LocalTransferController` directly and builds no widget tree, so it has
nothing to say about whether a tree rebuilds. And `flutter analyze` checks
types, not whether an `InheritedWidget` ever fires.

## Decision

`updateShouldNotify` returns `true`:

```dart
@override
bool updateShouldNotify(_ControllerProvider oldWidget) => true;
```

`true` is the correct answer rather than a workaround, and the reason is in what
this widget is: it is rebuilt **only** when the controller has reported a change
(see `_ControllerScopeState`), the controller instance is the same one for the
life of the scope, and everything the controller hands out is read inside
`build`. So "a change happened" is exactly the question the dependents want
answered — there is no second value here to compare that would tell them
anything the rebuild does not already say.

`InheritedElement.notifyClients` is what makes this work: it walks the
dependents that registered through `dependOnInheritedWidgetOfExactType` and
marks each one dirty directly, which is a different path from the parent
rebuilding its child — and therefore not blocked by the identical-child short
circuit above.

## Alternatives considered

**Keep the comparison, but compare something that changes.** Rejected: the
controller's `changes` stream is deliberately coarse — one "something moved"
tick rather than one stream per field — so any comparable value would have to be
invented at the scope, and an invented value that is not derived from the same
tick would either miss changes or rebuild on ticks that changed nothing a page
reads.

**Have each page subscribe to `changes` itself.** Rejected: this is the
arrangement the class exists to avoid. A dozen independent subscriptions race
each other, each page has to remember to cancel its own, and a page that
forgets leaks a listener into a broadcast stream that outlives the widget.

**Use `InheritedNotifier` instead of a hand-written `InheritedWidget`.** A
genuine alternative, and the closest thing to the idiomatic Flutter answer: it
notifies dependents on `Listenable` notifications without any
`updateShouldNotify` at all. It was not taken because the controller exposes a
`Stream`, not a `Listenable`, so adopting it means either changing what the
controller is or adding an adapter whose only job is to convert one to the
other. The one-line change keeps the existing arrangement, and the notification
it fixes is directly observable in a test.

## Consequences

- A page that reads the controller now rebuilds when the controller reports a
  change, which is what the class always claimed. Before this, the Devices list
  did not fill in from Discovery, the Transfers list did not gain rows, and the
  Settings screen did not follow a rename — none of it visible in the plain
  suite, all of it visible the moment a real tree was driven.
- The rebuild stays wholesale on purpose: the views the controller hands out are
  small value objects, so a page's `build` is cheap, and a tree that rebuilds
  itself once cannot race itself the way independent subscriptions can.
- `test_flutter/e2e/two_window_e2e_test.dart` is what pins it. The pairing test
  asserts the paired wording reaches both Devices pages, so the comparison
  answering `false` again would fail it rather than hang it.

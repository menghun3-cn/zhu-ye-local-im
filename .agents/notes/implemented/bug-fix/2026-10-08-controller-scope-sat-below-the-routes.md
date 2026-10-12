# Agent Note: The ControllerScope sat below the routes that needed it

Status: implemented

English | [中文](2026-10-08-controller-scope-sat-below-the-routes.zh.md)

## Problem

Opening a conversation showed a blank window. The Devices list drew, pairing
worked, a Session was up on both machines — and clicking a connected Device's
card, or the "open conversation" button on it, produced an empty pane. Two
machines, both directions, both on a release build, every time.

The window was not empty of content so much as empty of *everything*: no hint
text, no message box, no attach button, no send button. The report named those
four absences specifically, which rules out the tempting reading — that the
conversation had opened and merely lost its peer, which would still have drawn
the composer with the attach button greyed out.

A release build draws a build failure as a plain grey window. That is what the
screenshot showed, and it is the whole reason the symptom read as "blank page"
rather than as an error. The same failure under `flutter test` says what it is:

```
Bad state: no ControllerScope above this widget
```

`ControllerScope.of` throws that when there is no `_ControllerProvider` above
the calling context. `ConversationPage` calls it in `build`. The provider was
there — the app installed one — but not above that context.

`LocalTransferApp` wrapped only its `home`:

```dart
home: Builder(builder: _screen),   // _screen returned ControllerScope(child: HomeShell(...))
```

A route pushed with `Navigator.of(context).push(...)` does not build below
`home`. It builds in the root navigator's overlay, which is a **sibling** of
`home` — the navigator holds both. `_PeerCard._openConversation` pushes exactly
that way, so `ConversationPage` was built outside the scope and threw on its
first line of work.

Every other dialog in the app was unaffected for a reason worth naming: they
receive the controller as a **constructor argument**
(`showSendFileDialog(context, controller, …)`) rather than reading it from the
scope, so their being siblings of `home` never mattered to them. The
conversation is the one surface that reaches the controller through the scope
from a pushed route, and it is the one surface that broke.

## Decision

The scope wraps the whole `MaterialApp`, and wraps it only once there is a
controller to put in it:

```dart
final app = MaterialApp(…, home: Builder(builder: (context) => _screenFor(context)));
return controller == null ? app : ControllerScope(controller: controller, child: app);
```

Three things about this are load-bearing.

**Above the `MaterialApp`, not inside `home`.** The navigator is created by the
`MaterialApp` itself and cannot be handed in, so there is no place inside the
app's own tree that is above the navigator and below the localizations. Wrapping
the `MaterialApp` puts the scope above the navigator and therefore above `home`
*and* every route pushed on top of it, which is the property the conversation
needs.

**`home` stays the shell.** An earlier attempt moved the shell into
`MaterialApp.builder` and left `home` a placeholder. That renders an *empty*
window: `builder` decorates the navigator, it does not supply the route the
navigator shows, so a placeholder `home` leaves the navigator with nothing to
build. The failure mode is indistinguishable from the one being fixed, which is
what makes it worth writing down.

**The scope is absent while the app is starting up.** `home` has to be drivable
in all three states — starting, failed, running — because it is the only place a
route can come from, and the scope cannot be installed before there is a
controller. Nothing below needs it in those states: the startup and failure
screens read only their own strings.

## Alternatives considered

**Teach `ConversationPage` to take the controller as a constructor argument.**
Rejected, though it is the smallest diff and it matches how every dialog in the
app already works. It would fix this page and leave the trap armed: the next
pushed route that reads the scope fails the same way, and it fails as a grey
window rather than as a stack trace. The scope exists so that pages do not have
to be threaded; the fix belongs in where the scope sits.

**Wrap only the `home`'s subtree but push with a nested `Navigator`.** Rejected:
a nested navigator under the scope would put pushed routes inside it, which does
work, but it also means every dialog in the app renders inside that navigator's
overlay rather than the root's — a real change to how dialogs are positioned and
dismissed, taken to avoid moving one widget.

**Have `ConversationPage` tolerate a missing scope, e.g. `maybeOf` returning
null.** Rejected: it converts a wiring mistake into a page that quietly renders
without a controller. `ControllerScope.of` throwing is deliberate — its header
says a page built outside a scope "is a wiring mistake worth failing loudly on" —
and softening it here would hide the next instance of this bug rather than
surface it.

**Keep the scope where it was and push the route from a context under it, for
instance by giving the conversation its own `Navigator`.** Rejected: the route
still lands in an overlay, so the question of which overlay is above the scope
just moves.

## Consequences

- `lib/ui/app.dart` installs the scope around the `MaterialApp`. It is the one
  place the application's tree is assembled, and the comment there records why
  the scope is outside the app rather than under `home`.
- `test_flutter/ui/app_tree_test.dart` is new and pins it: it pumps
  `LocalTransferApp` itself — the tree `main` builds — and pushes the
  conversation from a context inside the shell, asserting the page builds, that
  its hint text and text field are on screen, and that popping returns to the
  shell. Against the old tree it fails with
  `no ControllerScope above this widget`, which is the reported grey window.
- That suite exists because the shared harness could not have caught this.
  `test_flutter/support/ui_harness.dart` wraps its `ControllerScope` around its
  `MaterialApp` — the same shape this fix adopts, with a comment explaining that
  a scope around `home` is invisible to dialogs — so every widget test built the
  *correct* tree while `lib/ui/app.dart` built a different one. A suite that
  builds its own tree cannot police the tree the application ships; this one
  builds the application's.
- `test_flutter/ui/app_tree_test.dart` drives two clocks, because
  `LocalTransferApp._open` binds a real `ServerSocket` on a widget test's fake
  clock. Each round yields to the real event loop and then advances the fake one;
  the same trap `startUiDevice` documents, applied to the app's own controller.
- A Device that drops its Session still leaves the conversation page with no
  notice: the title degrades to a bare fingerprint, the address line reads
  `neverSeen`, and the attach button greys out. That is unchanged here and is
  worth its own fix — the page is now reachable enough for it to matter.

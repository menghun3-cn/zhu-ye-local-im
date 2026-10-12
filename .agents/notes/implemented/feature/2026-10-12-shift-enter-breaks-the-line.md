# Agent Note: Shift+Enter breaks the line, and cannot be left to the framework

Status: implemented

## Problem

The composer sends on Enter and breaks the line on Shift+Enter. The code said
so in two doc comments and did not do it: Shift+Enter sent the message.

Nothing in the composer was broken. What answered the chord was the thing the
old comment left it to. Every activator in the framework's default text-editing
table is a `SingleActivator` with `shift: false`, and a `SingleActivator` matches
its modifiers *exactly* — so Shift+Enter falls past the whole table, past
`WidgetsApp`'s own `ActivateIntent` (also `shift: false`), and out of the
framework altogether. The engine answers an enter key that nobody claimed by
translating it into the field's `textInputAction`, which in this composer is
`TextInputAction.send`; `onSubmitted` then fires and the message is handed over.
At that point the two chords are indistinguishable — the action carries the
intent to send and nothing about which modifiers produced it. "Leave Shift+Enter
to the default line break" was therefore "make Shift+Enter send", and the
comment explaining it was the reason nobody looked.

Two smaller things were wrong in the same comments, both of which had the effect
of hiding the trap: `textInputAction` was described as "only a hint to the
*platform* keyboard" that does "nothing for a physical one" (it is exactly what
a physical Enter becomes), and the field was described as `maxLines: null` while
the code has said `maxLines: 6` for some time.

Why no test caught it: the composer's send was only ever driven through
`tester.testTextInput.receiveAction(TextInputAction.send)` — the engine's road,
which is the road that *worked*. The keys are the road a desktop user takes, and
no test had ever pressed one.

## Decision

**Shift+Enter is claimed as a key, in the same table as the bare Enter.**
`SingleActivator(LogicalKeyboardKey.enter, shift: true)` and the same for
`numpadEnter`, both mapped to a new `InsertLineBreakIntent`. Claiming it is what
keeps the engine out of it: a claimed key event is consumed and reported to the
engine as handled, so the action that cannot tell the chords apart is never
consulted. The bare Enter works the same way and keeps working — `WidgetsApp`
mounts its text-editing table near the top of the tree, any `Shortcuts` between
that table and the field overrides it, and this composer's table is that widget.

**The break is inserted by hand**, following the rule the paste fallback already
reproduced: the selection is replaced and the caret lands after what was
inserted. That rule now lives in one method, `_insertAtCaret`, which both callers
use — they have the same reason for existing, which is that each of them stopped
the field from doing the insertion itself (one by claiming Ctrl+V, the other by
claiming Shift+Enter).

**The action road stays.** `onSubmitted` is still wired, and is no longer
redundant for the reason the old comment gave: it is what answers a soft
keyboard's send key — on Android, where there are no modifiers and no second
chord — and any platform that reports the action rather than the key.

**The doc comments were rewritten, not extended.** The false one was
load-bearing: it named a mechanism that is not the one running, and the fix for
the bug is a sentence about which node in the focus chain gets to answer a key.
The rewritten block on `_ComposerField` states the rule that matters — an enter
nobody claims becomes the field's `textInputAction` — so that the next person
tempted to "let the framework handle it" has to argue with it first.

## Testing

`test_flutter/ui/composer_keys_test.dart`, five tests, all pressing real keys
rather than driving the action, on the precedent of the harness's `sendCtrlV`:
the bare Enter asks to send and leaves no break; Shift+Enter breaks the line,
inserts at the caret and asks for nothing; the break replaces a selection; the
numpad pair behave exactly as the main pair; and a break is still in the text
that goes out. The composer is pumped on its own, in the shape
`composer_attachment_test.dart` established — no window, no controller, no peer.

What these tests cannot cover is the engine's half. A widget test has no engine,
so it cannot press a key and observe that the engine did *not* also send; what it
can pin is the thing that keeps the engine out — that the chord is claimed, that
the text gains a newline, and that no send is asked for.

## Alternatives considered

**Leaving Shift+Enter to fall through to the framework's line break.** This is
what the code did. Rejected: there is no framework line break to fall through
to. Every default activator that could claim Enter is `shift: false`, and the
engine's answer to an unclaimed enter is the field's own `textInputAction`.

**`textInputAction: TextInputAction.newline`, so the engine's fallback inserts
the break.** Rejected: it would change what Android's soft keyboard does. This
composer keeps `send` because the only Enter an Android user has is the IME's
send key, and trading that away to fix a desktop chord is the wrong half of the
app paying for it.

**`focusNode: FocusNode(onKeyEvent: …)` on the field's own node instead of a
`Shortcuts` table above it.** Works, and is the recipe the field's own node
being consulted first makes the most literal one. Rejected for now because it
would split this composer's key handling across two places — the table already
declares four chords and documents them — and because the table's override of
`WidgetsApp`'s default is documented framework behaviour, not a trick. The node
route stays available if some future widget ever claims a chord from between the
table and the field.

**Guarding both chords against an active IME composition**, by reading
`controller.value.composing` before sending. Not done. On Windows the Enter that
commits a composition belongs to the IME and never arrives as a key event; on
Android the action road is a deliberate send. A guard that cannot be exercised
on the machines this project builds on would be unverifiable code wrapped around
an `if` — it belongs with a pass that can actually type 拼音 and watch what
arrives.

**A hint in the box** — "Enter 发送，Shift+Enter 换行" — or a tooltip on the
field. Rejected: it would rewrite `messageHint`, a user-visible sentence that the
packaging script probes `app.so` for, in order to explain a convention the box
already teaches by doing it.

**Sending on Ctrl+Enter as well**, or moving the send to the modified chord and
giving Enter back to the line break. Rejected: the first is unasked for; the
second contradicts the desktop convention this composer deliberately follows and
would make the common case the awkward one.

## Consequences

**Bought.** The chord does what both the code and the user's expectation said it
should, and the reason it is a *key* claim rather than a fall-through is written
down where the table is, next to the activators, where the next change to the
table will be made.

**A test now presses keys, and that is a new kind of coverage here.** Every
existing composer test drove `TextInputAction.send`; the key road was untested
even though it is the road every desktop user takes, which is how a bug in a
doc-commented feature survived. Anything else claimed by the table (Ctrl+V has
its own helper) is now the odd one out rather than the rule.

**The five new widget tests have never been run.** `flutter test
test_flutter` does not start on the machine this was written on: any
`Process.start` with piped stdio fails there with `CreateFile failed 231`, which
takes the `flutter` tool, `dart test` and the packaging script with it. The
analysis here is the framework's own source — the exact-match semantics of
`SingleActivator`, `WidgetsApp`'s mounting of `DefaultTextEditingShortcuts`, and
the `onSubmitted` doc that says the engine translates Enter into an action — but
a passing run is still owed on a machine where the toolchain works.

**Nothing user-visible was added.** No string, no icon, no layout: the packaging
probes are untouched, because there is no new sentence in `app_zh.arb` for them
to look for.

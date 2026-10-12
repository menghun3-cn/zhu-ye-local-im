# Agent Note: One picker for files and pictures

Status: implemented

## Problem

The composer had two attach controls: a paperclip labelled 发送文件 and a picture
labelled 发送图片. They opened two different dialogs for one intention, and the
second of them was a lie about the first.

`SystemPicker.files()` called `openFiles` with no filter at all; `image()` called
`openFile` with `acceptedTypeGroups: [XTypeGroup(extensions: imageExtensions)]`.
But that filter was the *only* thing the second control changed. What a choice
turns out to be was never the control's to decide: both roads end in
`_stagePaths`, which classifies every path with `looksLikeImage` and hands each
one to `_sendMessage`, where a picture goes out through `sendImage` and
everything else through `sendFile`. So the paperclip could already send a
picture and did — there were two controls for one intention, one of them
teaching the user a rule the code did not have.

The label is what makes this more than tidiness. 发送文件 reads as "files, not
pictures", which is exactly the belief the product must not create: which of the
two a message becomes is what decides whether the far side is *asked* to accept
it (`_landingFor`: a picture lands in the configured folder on arrival, a file
waits for a click), and a user who has learned "pictures go through the other
button" has learned that the button chooses. It does not, and it never did — the
extension chooses. Two entry points invited the user to hold a rule about the
interface where the product holds a rule about the file.

## Decision

**One control, one dialog.** The composer keeps the paperclip, keeps
`menuSendFile` as its tooltip, and drops the second control. `SystemPicker` keeps
one method — `openFiles`, unfiltered and multi-select — and loses `image()`; so
does the `FilePicker` seam it implements. The `ScriptedPicker` fixture loses its
second queue along with it, which is the point: a test can no longer express
"this was chosen through the picture button", because there is no such button.
It has to express what the user did — put a `.png` among the choices — and let
`looksLikeImage` answer.

**The type stays a reading of the file, not of the interface.** Nothing moved
into the composer: `classifyPaths` and `looksLikeImage` are unchanged, and the
arrival rule (`_landingFor`) is untouched. A picture still arrives and is drawn
with nobody answering; a file still waits for a click. The merge is meant to be
invisible in behaviour — if it had changed either half of that, it would have
been the wrong merge.

**The picture that control used to be is still in the app.**
`Icons.image_outlined` (0xf120) stays in the packaging script's
`$requiredGlyphs`: `labels.dart`'s `iconForKind` draws it on every list that
names a message's kind, and the placeholder for a picture that will not decode
uses it too. Only the comment changed, because the control that used to be the
reason is gone.

**The dead sentence went with it.** `menuSendImage` has no call site left, so the
tree-shaker will correctly drop it from `app.so` — which is exactly why the
packaging probe `'发送图片'` had to be deleted in the same change. A probe whose
sentence can no longer be reached is a probe that is red on a correct build; this
project has been here before (`chooseFolderTitle`). The key was deleted from both
`.arb` files and from the three generated localisation files, kept in step by
hand because `gen-l10n` does not run on this machine.

## Testing

`test_flutter/ui/pages_test.dart`. The old test that chose a picture through the
picture control now chooses it through the attach control —
`picker.willOffer([source.path])` with a `.png` in it — and asserts
`filesAsked == 1`, so the test itself is what pins "there is one dialog".

A second test is new, and it is the one this change is about: **one dialog sends
a picture and a file each its own way.** A single `willOffer([picture.path,
note.path])` — the shape a multi-select dialog hands back — and then: Alice's two
transfers come out as `[image, file]`; on Bob's side the picture has landed
(`localPath != null`) with nobody answering anything and never appears in
`offers`, while the file is not on disk and is the only thing waiting for a
click. Nothing in that test consults which control was pressed, because after
this change there is one.

`test_flutter/support/ui_harness.dart` loses `imageButton()`, `willOfferImage()`
and `imagesAsked`, together with the picker method they addressed.

## Alternatives considered

**Keep both controls, with the picture one as a filter.** Rejected: the filter is
the thing that was wrong. It changed nothing about the message, so it could only
ever mislead — and it did, by naming a rule (`发送文件` cannot send a picture)
that was not true of the code. Keeping it as a "shortcut" would keep the lie and
add a second way to reach the same dialog.

**Give the merged dialog an `XTypeGroup` for pictures**, so its file-type
dropdown offers 图片 / 所有文件. Rejected: it re-introduces the same suggestion
inside the dialog, and it pays for that with the default view, which is where
most choices happen — a dialog that opens on a filtered list is worse than one
that opens on everything.

**Rename the tooltip to 发送文件或图片.** Rejected: 发送文件 already means this
(the tool sends pictures through it and always could), and the smaller the
visible diff the better — a renamed string is a sentence the packaging probes
must be taught, while the current one is asserted by name in the harness and in
the end-to-end test.

**Keep `FilePicker.image()` in the seam, unused.** Rejected: the seam exists to
stand in for the platform, and a method nothing calls is a method whose test
double nothing drives. Deleting it is what makes the fixture unable to lie about
how a picture was chosen.

## Consequences

**Bought.** One intention, one control, one dialog. The label now describes what
the control does. And the rule that actually decides a message's kind — its
extension — is stated in one place (`looksLikeImage`) instead of being implied
twice by two controls with two filters.

**The packaged documentation moved with it.** `packaging/使用说明.txt` described
the control that no longer exists in three places (the composer's tool row, the
「发图片：两种方式」 section, and the first-pairing walkthrough); all three now
describe the single paperclip and say that the extension is what tells a picture
from a file.

**One packaging probe was deleted and one glyph comment rewritten.**
`$newProbes` loses `'发送图片'`; `$requiredGlyphs` keeps `0xf120` with the reason
it is still there. Nothing was added: this change adds no sentence to
`app_zh.arb`, which is worth saying out loud because `$newProbes` is a
"must-edit" list.

**The two widget tests have never been run.** `flutter test test_flutter` does
not start on the machine this was written on — `Process.start` with piped stdio
fails with `CreateFile failed 231`, taking the toolchain with it. The reasoning
here is the source: `classifyPaths` and `looksLikeImage` for the classification,
`_landingFor` for the arrival rule, and `_sendMessage` for the road each staged
attachment takes. A passing run is still owed where the toolchain works.

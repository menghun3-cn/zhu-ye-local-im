# Agent Note: Accepting a file lands it, and does not ask where

Status: implemented

## Problem

Pressing 接收 on a file offer opened a second dialog — "这些文件保存到哪个
文件夹？" — before any byte moved. The folder it proposed was already the one
this Device receives into: the field was prefilled with
`controller.incomingDirectory ?? defaultIncomingDirectory`, the same value an
image is filed under without a question. So the dialog collected an answer the
Device already had, and made the button feel like the first half of one.

The dialog was not decoration; it had a rationale, recorded in the doc comment
on `acceptOffer`: "the folder is asked for rather than assumed, because a Device
that only ever wrote to one folder would be a Device that cannot file
anything." That argument was about a Device with *no* folder. It said nothing
about the Device that has one — which is every Windows install, where the
platform default always resolves — and on those it was pure friction. The
choice of folder had not been lost either: the settings page has carried the
receiving directory since the 2026-10-09 round, which is where a folder decision
belongs.

## Decision

**`acceptOffer` asks only when it has no folder to name.** When the
`defaultDirectory` handed in resolves — user choice or platform default — the
offer goes straight into it: create the folder if missing, `acceptInto`, done.
When it does not (a platform with neither), the existing dialog opens exactly as
before, because there the question is not a confirmation but the only way left
to name a folder at all.

The rule of *what waits for the user* is untouched and stays in one place:
`_landingFor` still returns null for a file, so a file is still the user's to
answer, the bubble still draws 接收/拒绝, and nothing arrives unsolicited. What
changed is only what the answer costs. An image and an accepted file now land in
the same folder by the same road, which is also the sentence a user would have
written as the spec.

The dialog code, and every string it renders, stay compiled and reachable
through the fallback branch — the packaging probes for those sentences keep
passing, and no probe was added or removed.

## Testing

`test_flutter/ui/pages_test.dart` gains "accepting a file asks no second
question when there is a folder to receive into": Bob is started with a
`defaultIncomingDirectory`, Alice sends a file, Bob presses 接收 on the
Transfers surface, and the test pins the three things that matter — no dialog
opens, the Transfer completes, and the bytes are on disk under their own name
inside that folder (waited on by `existsSync`, per the localPath-after-settle
rule). The pre-existing dialog test keeps covering the other branch: its Bob is
started with no folder, so the question still opens there, and its comment now
says that is *why*.

## Alternatives considered

**Auto-accepting files on arrival, as images are.** Rejected: it undoes the
decision the previous round made deliberately — a file is the user's to answer,
and "接收" is the consent. Only the second question went, not the first.

**Remembering the folder the dialog last answered with.** Rejected: it
re-implements the settings field one dialog at a time, and the first transfer
after an install would still ask. The settings page already is the place a
folder is chosen.

**A "另存为" entry on the right-click menu for a settled file.** Not built now.
It would restore the per-transfer choice the dialog used to give without
standing between the click and the bytes, but it is an unrequested feature; the
request was to remove the question, and the folder is reachable from the same
menu through 打开所在目录.

**Deleting the dialog outright.** Rejected: some platform has no folder to
assume, and there the question is the only way to receive at all.

## Consequences

**Bought.** One click, one landing, one folder — the same folder images go to,
which the user can change in settings and nowhere else.

**Given up.** The per-transfer "save this one somewhere else" the dialog
accidentally provided. The right-click "另存为" listed above is the honest way
back if it turns out to be missed.

**The new test has never been run.** `flutter test` does not start on this
machine (`CreateFile failed 231` on any piped `Process.start`); the run is owed
on a machine where the toolchain works, like the two dialog-driven tests beside
it.

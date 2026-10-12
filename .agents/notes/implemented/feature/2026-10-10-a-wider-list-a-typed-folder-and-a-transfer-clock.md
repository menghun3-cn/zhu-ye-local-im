# Agent Note: a wider list, a folder you can type into, and a clock on a transfer

Status: implemented

## Problem

The repaint landed as its own PR, and the token layer now says what the design
says. Four things the design asks for are not tokens, though — they are
structure — and a repaint cannot reach them. A fifth item is not a change at all
but a test that had been lying.

**The conversation list was too narrow to read.** At 250 logical pixels in a
1280-wide window, the summary line under each name truncated often enough that
the list stopped being scannable: a row whose second line is an ellipsis is a row
you have to open to understand, which defeats the list.

**A conversation row was exactly 64 tall.** A fixed height is a number somebody
guessed, and it has to be re-guessed every time a font size moves — and the
repaint moved four of them. The row's correct height is the height its own
content asks for; writing it down was a cached answer to a question that changes.

**The received-files folder was behind a dialog.** Settings showed the folder as
a read-only fact line with a "Change…" button, and the button opened a dialog
containing an editable field. That field was the real control all along: a path
is something a user frequently has in hand — in a clipboard, in a Print dialog,
in a terminal — and making them open a modal to paste it is a step that buys
nothing. It also meant the value could only be *read* on the page, never
corrected there.

**A transfer said how much and not how long.** A row read `4.0 MiB / 4.0 MiB`,
which does not distinguish a transfer that took two seconds from one that took
two minutes. "Was that quick?" is the question the row is actually asked, and it
had no answer — the data to answer it did not exist.

**And the two-window end-to-end test asserted the wrong moment.** After waiting
for the transfer to report `completed`, it asserted the received file exists.
Those are not the same instant: the sink is closed and the staged file renamed
*after* the outcome is known, so `completed` is the start of the last step rather
than the end of it. The test passed when the scheduler was kind and failed when
it was not.

## Decision

**The list is 300 wide; the row sizes to its content.** `conversationListWidth`
went 250 → 300, and `conversationRowHeight` was **deleted** — the row is now a
`Column` with `mainAxisSize: min` holding the content and the hairline, with a
new `conversationRowVPadding` (10) for the breathing room the old number used to
provide. Nothing else changed about the row: the second line, the inset divider
and the in-row action all stay.

**The folder is a field on the page.** Settings now draws a labelled
`TextField` whose value is `incomingDirectory ?? defaultIncomingDirectory`, with
an `IconButton` in its `suffixIcon` that opens the platform's own folder chooser
through the existing `PickerResolution` seam. It commits on Enter and on leaving
the field — there is no Save button, because a settings field that needs
confirming is a field nobody trusts to have taken. The one thing that has to be
said out loud is the opposite: while the box holds text the controller has not
taken, the line under it says so (`folderNotSaved`). An emptied box commits
`null`, which is the controller's existing "ask me each time" rather than a path
nothing can be written to.

The dialog is not deleted — `askForDirectory` is still how the *accept* flow
picks a folder, where a modal is right because the question arrives while a
transfer is waiting. What is gone is using it for a value the page can just show.

**A transfer carries its end time.** `TransferView` gained `settledAt`, written
once from the controller's own injectable clock in the same `whenComplete` that
already settles the bookkeeping, and `describeTransferDuration` turns the
interval into words: a running count ("已用 12 秒") while it is still moving, the
interval it took ("用时 3 分 12 秒") once it has settled, and **nothing at all**
for a transfer that never started — still waiting for an answer, or refused
before a byte moved. Measuring an unfinished transfer to `now` is honest;
printing "用时 0 秒" under a question nobody answered is not. A settled transfer
whose end was never stamped (the app was restarted mid-flight) reports nothing
rather than measuring the application's uptime.

**The end-to-end test waits for the side effect.** The assertion now
`pumpUntil`s for the file to exist and *then* checks the state and the bytes.
This is the same rule an earlier change had to learn about `localPath`: wait for
the thing that must be true, not for the state that precedes it.

## Alternatives considered

**Keep the fixed row height and just re-guess it.** Rejected: it is the same
decision made worse — a second magic number in the file for the same fact, kept
in step by hand with a font scale that lives elsewhere.

**Keep the dialog and add the field as well.** Rejected: two controls for one
value, and the page would then have to explain which one wins. The dialog keeps
its job in the accept flow, where it is a question being asked rather than a
setting being edited.

**Show a Save button instead of committing on blur.** Rejected: the field would
then be a form, and a form implies the value is not applied until submitted —
which is exactly the uncertainty the inline field removes. Committing on blur
means the only state needing a word is the transient one.

**Tick the running duration on a timer.** Rejected: a `Timer.periodic` in a
widget test has to be pumped and cancelled by hand, and during an active transfer
the progress stream already rebuilds the row several times a second. Reading the
clock at build time is also what `describeLastSeen` already does for every other
relative time in the app. The known cost is that a *stalled* transfer shows a
frozen count — which is arguably the truthful reading of a stalled transfer.

**Report a duration for a refused transfer too.** Rejected: refused transfers
never moved a byte, and the interval would be the time a question sat on screen.
That is a fact about the user's attention, not about the transfer.

## Consequences

**The settings page has one control fewer and one state more.** `_chooseFolder`
became `_IncomingFolderField`, a `StatefulWidget` that owns a
`TextEditingController` and a `FocusNode`. Two widget tests were rewritten for
the new shape: they no longer drive a dialog, and one of them now pins the
transient state (`folderNotSaved`) rather than a dialog's title.

**One assertion had to stop skipping off-screen widgets.** The line under the
folder box is the last thing in its card and sits below the fold in the test
window, so the default finder — which prunes `ListView` children outside the
viewport — reported zero. It is read with `skipOffstage: false`. Worth knowing
before the next assertion on a long page is debugged as a logic failure.

**Four localisation keys were added for the duration and one for the folder.**
`transferElapsed`, `transferTook`, `durationSeconds`, `durationMinutes`,
`durationHours` and `folderNotSaved`, in both languages, generated by
`flutter gen-l10n`. Only `folderNotSaved` is a whole sentence without
placeholders, which is why it is the one the packaging probe can use; the
duration strings exist in `app.so` only as fragments.

**One localisation key was removed, and the packaging probe lost a sentence.**
`chooseFolderTitle` ("选择保存位置") was the *title of the folder dialog
settings used to open*, and that dialog was its only caller — the accept flow
passes `whereShouldFilesLand` / `whereShouldThisArrive` instead. Removing the
settings dialog therefore left the key with no call sites, and the AOT
tree-shaker dropped the sentence from `app.so` on the next release build. The
packaging script had been probing for exactly that sentence since a ninth of
October, so it failed the pack with *"app.so 里找不到这些新文案: 选择保存位置"* —
correctly: a probe for a sentence no correct build can contain is a permanent
red light. Both the probe and the key are gone.

The general rule the script states about replaced sentences applies to
**unreachable** ones too: a probe is a claim about what the shipped binary
contains, so it has to be re-derived whenever the caller graph moves, not only
when the wording changes.

**A stale local branch and a green suite hid a flaky test.** The end-to-end
assertion had been passing by luck; making the suite's heaviest test run beside
the others exposed it. It is fixed here rather than in its own PR because the fix
is three lines and the failure was blocking this PR's gate — but the lesson is
the one the earlier `localPath` change already wrote down, and it was worth
re-deriving: **a state that precedes an effect is not the effect.**

**Still to come, in its own PR.** Dark mode, and the in-app page top bar — the
latter deliberately deferred: a title on every page duplicates the navigation
labels in every text finder, so it wants its own diff and its own test pass
rather than riding along with a layout change.

# Agent Note: The rail update entry opens the card and shows its work

Status: implemented

English | [中文](2026-11-05-the-rail-update-entry-shows-its-work.zh.md)

Narrows [the rail entry installs instead of opening a browser](../feature/2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.md)
and builds on [the update download owned by a session](2026-11-05-update-download-session.md):
the install already survives the page that asked for it, but the rail entry
still has to prove the press landed and say what it has room to say.

## Problem

After the automatic check found a newer build, the rail showed 「更新」. A press
started the install in the session and switched to the My surface — but landed
on the card list, where nothing about the download was visible, and the entry
itself only knew a boolean "busy" answer: it could be greyed, but it could not
say the press had been accepted, could not say work was running, and could not
show how far the download had got. To a user the button still looked dead.

## Decision

**The rail press opens the card that shows the work.** The session owns the
install — the press reaches it directly, whenever the About card happens to be
built — so all `MyPage` owes a request is the sub-page the card lives on:
`openAboutRequests` is a counter the shell increments beside `_index`, and a
change in it opens `_SubPage.about`. A counter rather than a flag, so every
press is a request even when the card was already open; the card itself needs
no install-on-open path, because there is no request for it to consume — the
session already has the work.

**The rail draws the state the session reports.** `HomeShell` already listens
to the session for the busy edge; it now also keeps `_sessionPercent`, the
rounded percentage a download with known byte counts earns. The comparison is
on the displayed values, not the progress objects, so a per-chunk report does
not rebuild the rail faster than the number can change. While the session is
busy the entry is disabled and reads 「更新中」 / "Updating"; a known download
fraction adds the percentage line, and every other stage is the same updating
state. When the session goes idle — failure, cancellation, or the hand-over —
the entry reads 「更新」 again and is the retry.

**The prepared-but-unanswered window stays pressable.** `session.busy` is
false while a package waits for the question, so the entry is not locked
behind a modal dialog it could not reach anyway; a press there counts another
`confirmRequests`, which is how the card asks the same question again rather
than starting a second download.

## Alternatives considered

**Let the press land on the card list.** Rejected: the download would run
invisibly except for the rail label, and the progress bar, the question and
the failure sentence would all sit one more tap away. The press asked for the
update; showing its card is the answer.

**Plumb a progress callback from the card upward.** Rejected: the card is a
view over the session now, and the shell already listens to that session — a
second reporting channel would be a second source for one update.

**Draw a progress bar in the rail.** Rejected: the rail is 84 pixels wide and
already carries an icon plus a label. The About card keeps the byte counts and
the determinate bar; the rail carries the one percentage it has room for.

**Lock the entry while the question is open.** Rejected: `session.busy` is
already false there, and locking would hide the one press that means "ask me
again" — the question is modal, so the entry could not be pressed regardless.

## Consequences

- `lib/ui/home_shell.dart` tracks `_sessionPercent` beside `_sessionBusy`,
  passes `openAboutRequests` to `MyPage`, and gives `_UpdateEntry` the
  `updating`/`percent` pair that selects 「更新中」 plus the percentage.
- `lib/ui/pages/my_page.dart` opens the About sub-page when `openAboutRequests`
  changes; it owns no install state at all.
- `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` add `railUpdateRunning` and
  `railUpdatePercent`; generated localizations are committed.
- `test_flutter/ui/update_rail_test.dart` asserts that the press opens About
  and reaches the installer, that a held download disables the entry and shows
  the percentage, and that failure restores the retry.
- `test_flutter/support/ui_harness.dart` finds the entry by its icon so the
  finder still works after the label changes.

## Testing

`flutter test test_flutter/ui/update_rail_test.dart` and
`flutter test test_flutter/ui/update_session_test.dart` cover the rail opening
the card, the held-download disabled/percentage state, retry after failure,
prepared-package reuse after a cancelled question, and the Android installer
handoff.

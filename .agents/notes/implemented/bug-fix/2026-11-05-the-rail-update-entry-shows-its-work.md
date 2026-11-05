# Agent Note: The rail update entry opens the card and shows its work

Status: implemented

English | [中文](2026-11-05-the-rail-update-entry-shows-its-work.zh.md)

Narrows [the rail entry installs instead of opening a browser](../feature/2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.md):
the install still belongs to the About card, but the rail entry now has to prove
the press landed and report the compact state it has room for.

## Problem

After the automatic check found a newer build, the rail showed 「更新」. Pressing
it could look like nothing happened: the shell switched to the My surface, but
the About card is a sub-page inside My, so an `installRequest` counter alone did
not open it or start the install. The rail also only knew a boolean "busy"
answer, so it could not say that the press had been accepted, could not show
that work was running, and could not show how far the download had got.

## Decision

**The rail press opens the card it hands the install to.** `MyPage` treats a
new `installRequest` as "open About and start once" through `installOnOpen`;
once the About card exists, later presses still travel as the counter and are
answered by `didUpdateWidget`. The one-shot flag is cleared after the first
frame, so a request that turns out not to start cannot linger and start a later
visit by itself.

**The rail draws the newest stage the card reports.** `AboutPage` forwards
`UpdateInstallProgress` through `MyPage` to `HomeShell`, coalesced to at most
one report per frame because a download reports per received chunk and an
install can be started from `didUpdateWidget`. While progress is non-null the
entry is disabled and reads 「更新中」 / "Updating"; a download with known byte
counts adds the percentage line, and every other stage is the same updating
state. Null restores 「更新」 / "Update".

**A ready package is not the same as work in flight.** `_confirmingUpdate`
separates "the question before closing is open" from "a package is prepared".
Answering no, failing, or handing off to the installer clears the in-flight
state without discarding the package, so the same control is the retry and does
not fetch twenty megabytes again.

## Alternatives considered

**Keep the press as only a surface switch.** Rejected: that is the reported
bug. A user who presses 「更新」 and lands on a card list has been given no
evidence that anything was asked for.

**Let the shell own a second download state.** Rejected: the rail would then
have its own idea of what "downloading" means, beside the About card's real one.
Two sources for one update drift; the rail is a projection of the card's
reports, not a second installer.

**Report only busy, not progress.** Rejected: the requirement is that the
button show updating and, where possible, a percentage. A boolean can grey the
entry but cannot say how far the download has got.

**Draw a progress bar in the rail.** Rejected: the rail is 84 pixels wide and
already carries an icon plus a label. The About card keeps the byte counts and
the determinate bar; the rail carries the one percentage it has room for.

## Consequences

- `lib/ui/pages/my_page.dart` opens the About sub-page for a new
  `installRequest` and forwards `UpdateInstallProgress` upward.
- `lib/ui/pages/about_page.dart` accepts `installOnOpen` and
  `onUpdateProgressChanged`, reports progress at frame boundaries, and uses
  `_confirmingUpdate` so prepared-but-answered-no state re-enables the action.
- `lib/ui/home_shell.dart` stores the latest reported progress and passes it to
  the rail entry, which disables itself and switches from 「更新」 to
  「更新中」 plus a percentage when the download's byte counts are known.
- `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` add `railUpdateRunning` and
  `railUpdatePercent`; generated localizations are committed.
- `test_flutter/ui/update_rail_test.dart` now asserts that the press opens
  About and starts the installer, that the entry is disabled and shows the
  percentage while a held download is in flight, and that failure restores the
  retry. `test_flutter/support/ui_harness.dart` finds the entry by its icon so
  the finder still works after the label changes.

## Testing

`flutter test test_flutter/ui/update_rail_test.dart` and
`flutter test test_flutter/ui/about_page_test.dart` cover the rail opening the
card, the held-download disabled/percentage state, retry after failure,
prepared-package reuse after a cancelled question, and the Android installer
handoff.

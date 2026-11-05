# Agent Note: The update download is owned by a session, not the page

Status: implemented

English | [中文](2026-11-05-update-download-session.zh.md)

## Problem

The update install — fetch, checksum, unpack, the question, the hand-over —
lived in the About page's state. The page is only built while My's About
sub-page is open, so leaving it mid-download dropped everything the download
had produced: the `prepared` result was discarded on `!mounted`, the progress
and the ready state were gone, and coming back meant pressing 更新 again. A
second press while the orphaned fetch was still running could put two
`prepare` calls on the same `.part` file, which ends in a checksum failure
and a download started over — the interruption users actually saw. And a
package that *did* finish downloading was only ever rediscovered by running
`prepare` again from a page that had to be opened and pressed first, so a
restart always cost a fresh trip through the whole flow even when the bytes
were already sitting in the update folder.

## Decision

**`UpdateInstallSession` owns the install for the life of the process.** The
session is a `ChangeNotifier` held by `HomeShell` — the one widget that
outlives every surface — and handed down `MyPage` → `AboutPage`. It carries
the answer, the progress, the failure, the prepared update and the in-flight
prepare future; the About card is a view over it. `install(answer)` is the
single entry point for "install this": it adopts the answer, joins a prepare
already running instead of starting a second one, and counts a press that
finds a prepared update waiting as a `confirmRequests` bump — the question
asked again rather than a download started over. `reset()` is what a fresh
check from the card amounts to.

**The question stays the card's.** The session reports `prepared`; the card
turns a newly prepared update into `_ConfirmUpdateDialog` once, unless the
prepared update came from `restore` — a package found on disk is *offered*
(ready text, button asks the question) rather than announced, because
opening a page is not a request to close the app.

**A finished download is found again after a restart.**
`UpdateInstaller.hasFetchedPackage(check)` answers whether the package the
answer names is already in the update folder, whole and matching the
checksum the release published — a local digest read, no network.
`HomeShell` calls `session.restore(answer)` whenever the notice lands on an
available version; on a hit the session runs the same `prepare` a press
would, which is then only a verify and an unpack. Restore never fetches:
nothing on disk means nothing happens, and the next press downloads as it
always did. A `.part` left by a killed run is still adopted by the next
`prepare`, unchanged.

**The rail entry presses the session directly.** `_installUpdate` calls
`session.install(notice.answer)` and brings the My surface forward; the
`installRequest` counter and the card's `didUpdateWidget` consumption are
gone. This also repairs a break the My-page consolidation left behind: a
rail press used to do nothing until the About card happened to be built,
and even then the pending count was never consumed on first build — the
flow the rail tests describe only works now because the session, not the
page, holds the request.

## Testing

`test/ui/update_install_test.dart` pins `hasFetchedPackage` on a real
installer over a temp application folder: true only for a package that is
there and matches, false for missing, mismatched, digest-less and
unsupported-platform cases. `test_flutter/ui/update_session_test.dart`
covers the session itself — request joining, confirm counting, restore's
fetch-nothing and stage-what-is-there, once-per-version lookup, reset — and
the card on it: a download finishing while the page is gone still owes the
question, progress is where it was left for a card built mid-flight, and a
restored package is offered without a popup and installs on one press.
`test_flutter/support/ui_harness.dart`'s `openMyCard` now taps the card
itself — the 「查看详情」 button it used to look for has not existed since
the My page landed, which is why the rail tests were red on develop.

## Alternatives considered

**Keep the download in the page and keep the page alive.** Rejected: an
`Offstage`/`IndexedStack` wrapper preserves widget state but not the
process boundary the requirement names — a restart still finds nothing —
and it keeps a hidden page's listeners and timers alive for no benefit.
The session also has to outlive My itself being rebuilt, which a page-local
owner cannot promise.

**Persist a marker file describing the finished download.** Rejected: the
update folder already *is* the record — the package's name carries the
version and its bytes carry the checksum. A second file would be a second
thing to keep true, and `hasFetchedPackage` answers the same question by
reading the one that cannot lie.

**Auto-popup the question for a restored package.** Rejected: a restart
finding bytes on disk is not the user asking to close the app. The card
shows it ready and waits for the press that means it; a package a live
download just produced still gets the question immediately, as before.

**Resume a partial download automatically on restore.** Rejected for now:
the `.part` adoption already makes the next press cheap, and silently
restarting a fetch the user walked away from is a different promise than
the one this change makes. The hook is there if it is ever wanted.

## Consequences

- Switching surfaces mid-download no longer loses the download or its
  result; a second press joins the fetch in flight instead of racing it.
- A restart with a finished package in the update folder finds it ready:
  one press reaches the question, no download repeats.
- The rail update entry actually installs now — it was dead since the My
  page landed, and its tests are green again.
- The session is process-wide, so an install started from the rail is
  visible to — and cannot be double-started by — the card.
- `UpdateInstaller` gained a member; every implementer is in this repo
  (`PlatformUpdateInstaller`, `ScriptedUpdateInstaller`).

# Agent Note: An update applies without asking again

Status: implemented

English | [中文](2026-11-09-update-applies-without-asking.zh.md)

Partially supersedes the confirmation step recorded in
[the rail entry installs instead of opening a browser](../feature/2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.md)
and [the About card's single update action](../feature/2026-10-26-one-update-action-on-the-about-card.md),
and the `confirmRequests` mechanism in
[the update download is owned by a session](../bug-fix/2026-11-05-update-download-session.md).
The session's ownership of the download and the restore-on-restart behaviour
are unchanged.

## Problem

Pressing 更新 ran `prepare` — fetch, checksum, unpack — and then stopped to
ask 「更新并重启？」 or 「安装更新？」 before `apply`. The question existed
because `apply` ends the process: a program that closed itself without a word
would be alarming. In practice the press on 更新 was already the user's
decision to replace the running build, so the dialog added a step without
adding a decision — and on Android it delayed the system installer, which has
its own confirmation surface, behind a second in-app gate.

## Decision

`UpdateInstallSession` runs `prepare` and `apply` back to back. A prepare
that finishes is applied by the session itself unless it came from `restore`;
a press that finds a prepared package waiting calls `apply` rather than
counting a `confirmRequests` bump. The confirm dialog, its six l10n keys, and
the session's confirm-request counter are gone, and `preparedIsRestore` went
with them — the restore/press distinction now lives entirely inside
`_prepare`'s `restored` flag, which decides whether a finished prepare is
applied or only offered.

An `_applying` flag beside `_progress` marks the hand-over as busy. The
platforms that replace themselves report no progress during it, so without
the flag a second press inside the hand-over window could start a second
one.

A package `restore` finds on disk is still only offered: opening a page is
not a request to close the app, and the same 更新 press applies it.

## Alternatives considered

**Keep the dialog on Android only.** Rejected: it bought nothing there either
— `apply` opens the system package installer, which asks its own question, so
the in-app dialog was a gate in front of a gate.

**Auto-apply only while the About page is built.** Rejected: the session
outlives the page on purpose, and gating the hand-over on a visible surface
would make "the download finished while you were on Transfers" behave
differently from "it finished while you watched" — the first would wait for
a visit, the second would not.

**Keep a cancel window — apply a few seconds after the download lands.**
Rejected: a timer that closes the app is worse than either extreme; the press
already answered the question the window would have asked.

## Consequences

- One press on 更新 now ends in the app closing (Windows) or the system
  installer opening (Android) with no intermediate dialog.
- A download that finishes while a transfer is running interrupts it —
  accepted deliberately; there is no longer a moment to reconsider.
- `confirmRequests` and `preparedIsRestore` no longer exist; the widget tests
  assert `installer.applied` where they used to assert a dialog.
- `scripts/packaging-probes.json` swapped the removed `aboutUpdateConfirmTitle`
  probe for `aboutUpdateInstallHintAndroid`, which is equally unique and
  placeholder-free.

## Testing

`test_flutter/ui/about_page_test.dart`, `update_session_test.dart` and
`update_rail_test.dart` pin that a finished prepare is applied with no
`AlertDialog`, that a restored package is applied on press without being
fetched again, that apply failures surface as the usual failure sentences,
and that a second press during the hand-over cannot start a second one.

# Agent Note: The About card has one update action

Status: implemented

English | [中文](2026-10-26-one-update-action-on-the-about-card.zh.md)

Partially supersedes [the rail entry installs instead of opening a browser](2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.md),
which left asking and installing as two buttons on the About card. The rail
entry, install pipeline, confirmation dialog, and busy-state reporting remain
current.

## Problem

The About card showed "Check for updates" and, after an available answer, a
second filled "Download and update" or "Download and install" button. Both were
primary on the same card. The user had to recognize that the first button's
answer determined whether the second existed. The labels differed by platform
although the user-facing operation was the same.

The second button also needed to be visibly unavailable during a download. A
disabled second control beside an enabled check control made the card look as
if another action were still possible while the install was running.

## Decision

The card owns one filled primary action in one position:

- `Check for updates` when no installable update is known.
- `Checking…`, disabled, while the check is in flight.
- `Update` after an available update and a supported in-app installer.
- `Update`, disabled, while download, verification, staging, or hand-over is in
  progress. Progress text remains separate and names the phase.
- `Update` again after failure or after a cancelled confirmation. A prepared
  package is reused, and the install entry refuses a call while `_busy`.

Windows and Android share the `aboutUpdate` string, "Update". Platform-specific
hint and confirmation copy still explains restart versus opening the system
installer.

An available release on a platform without an in-app installer does not turn
the action into "Update"; the card keeps `Check for updates` and retains the
secondary manual download page.

## Alternatives considered

**Keep two primary buttons.** This repeats a two-step decision the card can
already make for the user, and leaves the check button alongside an install
that is already in progress.

**Always label the button `Update`.** It would claim an update exists before any
check and would remove the only explicit way to ask.

**Change the label to `Downloading` during the operation.** The progress bar and
stage sentence already say that. Keeping the stable `Update` label leaves the
disabled state and progress report to communicate the operation.

**Use platform-specific action labels.** Windows and Android start the same user
action and differ only after it starts. One label keeps the primary decision
identical.

## Consequences

- The card has one filled action; `aboutCheckForUpdates` and `aboutUpdate` are
  mutually exclusive states of the same control.
- A user cannot re-run the check while an available update is waiting to be
  installed. The update action can be retried after failure or cancelled
  confirmation.
- The secondary `Open the download page` control remains unchanged and is
  disabled while checking or updating.
- `_install` rejects a call while `_busy`, independently of the disabled button,
  so two entry points cannot start two downloads before the disabled frame is
  rendered.

## Testing

`test_flutter/ui/about_page_test.dart` pins the button transition, the
no-update states, the disabled download state, duplicate-press rejection, retry
after failure, prepared-package reuse after cancellation, Android installer
flow, and the unsupported-installer fallback.

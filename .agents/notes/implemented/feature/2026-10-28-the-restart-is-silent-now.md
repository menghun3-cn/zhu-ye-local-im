# Agent Note: The restart is silent now

Status: implemented

English | [中文](2026-10-28-the-restart-is-silent-now.zh.md)

## Problem

After the confirmation dialog that follows "Update and restart", Windows
showed two indeterminate indicators: a progress bar on the About card for about
600 ms, and then a separate hand-over window with a spinner and "Replacing this
folder and restarting…" while the new build copied itself into place. An
installed copy also showed Inno Setup's silent progress window. Three separate
"waiting" moments for a step the user had already agreed to, none of them a
percentage, none actionable.

## Decision

The confirmation dialog is the only announcement. After it:

- **The About card draws nothing new.** The `handingOver` progress state is no
  longer reported to the page (its sentence and the `aboutUpdateHandingOver`
  l10n key are gone), and on Windows the card does not set a progress state at
  all after the question. Android still shows "Opening the system installer…".
- **The hand-over window is gone.** A build started with `--apply-update` now
  finishes in place: `UpdateHandoff.run()` replaces the folder on an isolate,
  starts the updated build, and exits. `lib/ui/update_handoff.dart` was
  deleted. The updated build is the window the user asked for.
- **The installed copy is also silent.** Inno Setup is launched with
  `/VERYSILENT` instead of `/SILENT`, so no install window of its own appears;
  its existing `[Run]` `/update` entry still relaunches the app.
- **Failure is still reported.** The portable hand-over writes
  `.update-failed.txt` under the application folder when the new build cannot
  be started or the copy fails; the next start reads it (as before). Starting
  the staged build from the old process also writes the report on a start
  failure, since the old window may already be gone.

## Alternatives considered

**Keep the hand-over window, only remove the About-card bar.** This still shows
an uninformative spinner after the user already said yes, and keeps a window
whose only purpose was to say "waiting".

**Use a real progress bar for the copy.** The copy is on an isolate; per-file
progress would need a port and a stream for a number nobody can act on (the old
window rejected this same idea when the hand-over window was designed).

**Hide the window instead of deleting it.** A hidden Flutter window still
initialises a full engine, costs the same resources, and would leave a trap for
future code; deleting `update_handoff.dart` removes the path entirely.

## Consequences

- One announcement, then a restart: the updated application is what the user
  sees next.
- The failure report is the only trace left by a failed silent hand-over, read
  once by `previousFailure()` on the next start — the same contract as before.
- The native runner's comment and docs no longer reference a hand-over window;
  the flag contract (`--apply-update`, `--staged`, `--target`) is unchanged.

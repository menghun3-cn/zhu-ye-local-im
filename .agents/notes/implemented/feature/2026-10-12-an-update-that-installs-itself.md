# Agent Note: An update the application installs itself

Status: implemented

## Problem

The application could tell a user that a newer build existed, and could not give
it to them. The rail pinned an entry under the destinations, the About card
turned the answer into a sentence and offered a download page — and then the
work was the user's: leave the application, find the release, work out which of
seven attachments belongs to the shape of copy they are running, download it,
and replace a folder by hand (unpacked copy) or run an installer (installed
copy). Asked for in one sentence — 应用内一键下载/静默替换/重启 — and the
sentence is one action.

Three facts about the platform and about this repository are what made it more
than a download button.

**A running program may not overwrite itself on Windows.** `local_transfer.exe`,
`flutter_windows.dll` and `data\app.so` are open for as long as the process
runs, and there is no way to close them from inside it. Nothing that runs *in*
the application can put a new build where the old one is.

**There are two shapes of copy, with two different owners.** An *installed* copy
belongs to its installer: the uninstall entry records a version, and replacing
the files behind the installer's back leaves that version a lie — the honest
upgrade is to run the new installer and let it do the work. An *unpacked* copy
has no installer and nobody to ask.

**The release carries a file it must not be confused with.** Every asset is
published twice: once under a versioned name and once under a fixed-name alias,
and the alias ends in exactly the same suffix as the versioned one. A selection
rule that matched on `.zip` would be choosing by the order the API happened to
list seven files in.

## Decision

**The second process is the build that was just downloaded.** It is unpacked
into a folder of its own, started with `--apply-update --staged <folder>
--target <folder>`, and it waits for the old one to go before copying itself
into place. Not a script and not a helper shipped beside the application: this
product packages no interpreter and would rather not start one, and a helper
would be a file that has to be updated by the very mechanism it exists to
perform. The consequence is the feature of it — *the code that finishes an
update is the code that was written most recently*, so a fix to this machinery
reaches the machines that need it riding on the update that carries it.

**On Windows only, and said before anything is awaited.** `supported` is
`Platform.isWindows`, read synchronously, so the About card can leave the offer
out entirely rather than draw a button whose only outcome is a sentence about
failure. A button that cannot work is worse than no button.

**Which payload to fetch is answered by a file.** `安装说明.txt` is present in an
installed copy and absent from an unpacked one, because `packaging/local_transfer.iss`
copies it in and `scripts/pack-windows-portable.ps1` does not. The alternative —
reading the uninstall registry key — is more machinery, needs the native side,
and answers a question a file in the folder already answers.

**The asset is named, not matched.** `updateAssetName` builds
`LocalTransfer-<version>-windows-x64-portable.zip` or `…-setup.exe` from the tag
the release reported, and `updateAssetFor` looks for exactly that. The tag is the
version the answer already carries; there is nothing to infer.

**The checksum comes from the release API itself.** GitHub returns
`digest: "sha256:<hex>"` on every asset (verified against the published v0.1.1
release: all seven of them), so the expected hash arrives with the same answer
that named the file. A release that publishes no digest is *refused*
(`UpdateInstallFailure.noDigest`) rather than trusted. This is deliberate: the
bytes being fetched are about to be written over the application that is
running, and "it came from a URL we built" is not a check when the URL is
redirected to a CDN. The sidecar `.sha256` was rejected as the source — it exists
only on the `latest` alias, so using it would mean either resolving two answers
that can disagree or publishing an alias for every versioned file.

**It is verified before anything is unpacked, and unpacked before anything is
replaced.** `_download` → `_matchesDigest` → `_unpack` → `isAPackage` →
`dropStagedTree`. Each step can refuse, and the four refusals are four different
sentences.

**A hand-over drops a tree in two phases.** Every file of the new build is
copied to its destination under a `.ltnew` suffix first — nothing in the target
is touched during this phase — and only then are the suffixes renamed away.
A failure while copying (a full disk, a folder that turned out not to be
writable after all) therefore leaves the running build exactly as it was, with
nothing to undo but the litter; only the renames can leave a mixture, and a
rename carries no bytes, which is the shortest window this can be done in
without a second directory and a restart in between. The renames are retried
(40 times, 250ms apart), because the build being replaced has only just been
asked to stop and Windows keeps a program's files open until the process running
them has gone.

**The native runner reads the command line before the single-instance check.**
Two things change for a build finishing an update, and both are because the copy
it replaces is *still running*: it is not a second copy of the application (so
`HostShell::AcquireSingleInstance` must be skipped — otherwise the new build
finds the old window, hands it the focus, and exits), and it must not be closed
by a click in the middle of the copy (so `SetQuitOnClose(false)` — a click that
ended the process halfway would leave the folder holding half of each build).
The console attach stays first; `main.cpp` stays pure ASCII, because a non-ASCII
byte in a `windows/runner` source file is `C4819` under CP936 and `C2229`/`C2220`
after it, and the six gates do not compile `windows/**` at all.

**`main()` answers the flag before it opens anything.** `UpdateHandoff.parse`
runs before the seams: a hand-over opens no sockets, binds no port and asks the
platform for no directory — which is the point, because the build it is
replacing still holds the discovery port. What it does open is a window: the gap
between the old window closing and the new one opening covers copying a whole
application and restarting it, and a machine that showed nothing for that long
would read as having crashed. That window is also the only place a failure can
be reported — by then the old build is gone and the new one is not in place.

**An installed copy hands the job to Inno Setup, and the installer must put the
application back.** `Process.start(setup, ['/SILENT', '/SUPPRESSMSGBOXES',
'/NORESTART', '/update'])`. The existing `[Run]` entry carries `skipifsilent`,
so a silent install replaces the files and leaves nobody to relaunch them —
`local_transfer.iss` gained a second `[Run]` guarded by a `[Code]` function,
`UpdateWasRequested() = WizardSilent and CmdLineParamExists('/update')`. The
`/update` argument is what makes that entry fire only when this application
asked for the install: a scripted `/SILENT` install stays an install, and an
interactive one is still the first entry's business.

**Unpacking is `tar -xf`, the system's own.** Windows 10 1803 — the version this
application already requires — ships `bsdtar`, which reads a zip. A zip reader
in Dart would be a few hundred lines to read a file this machine can already
read, and it is also a few hundred lines that would have to be right about
paths, encodings and permissions.

**Progress is a stage and, while downloading, two byte counts.** A closed set
(`UpdateInstallStage`) rather than a sentence, for the same reason
`UpdateOutcome` is one: turning a stage into words belongs to the layer that
knows what language the user reads. `fraction` is null when the length is not
known, which is what makes the bar indeterminate for every step but the
download — those steps genuinely have no length.

**A hand-over that died leaves one file, read once.** `.update-failed.txt` is
written into the target folder by the window that failed and read-then-deleted
by `previousFailure()` on the next start, so the sentence appears once. Without
it the only trace of a failed hand-over would be a window that came and went.

**What hand-overs leave behind is cleared on the next start.**
`clearStaleUpdateStages` deletes `local_transfer_update_*` folders under the
system temporary directory that are more than an hour old. It is started
`unawaited` from `main()` — housekeeping must not hold up the first frame — and
the cutoff is what keeps it from deleting the stage of a hand-over that is
running right now, which is a folder the running build is executing from.

## Testing

`test/ui/update_install_test.dart` (plain Dart, no widgets) covers the parts
that are pure: which file each shape of copy fetches, that a `.ltnew` left
behind is not counted as part of a staged build, what `isAPackage` accepts and
refuses, that `dropStagedTree` overwrites the old contents *and* leaves the
target untouched when the copy phase throws, that `UpdateHandoff.parse` reads a
flag-only command line as a hand-over rather than as an ordinary start, that a
report is consumed by being read, and that the stale-stage sweep deletes by
prefix *and* by age.

`test/ui/update_check_test.dart` is new too: `parseRelease` and `parseAssets`
against hand-written JSON, and `GitHubUpdateChecker` against a local
`HttpServer` (a widget test cannot stand in for the response, and the point is
that a 404 and a 500 produce two different answers).

`test_flutter/ui/about_page_test.dart` covers the card: that the offer appears
only once a newer version is known *and* this build can replace itself, that
pressing it hands the page's own answer to the installer, that the bytes are
shown while a download runs, that each failure arrives as its own sentence with
the button offered again, and that what a dead hand-over left behind is said.

One trap is worth recording, because it cost a run: the hand-over stage draws
`LinearProgressIndicator(value: null)` — an indeterminate bar, which animates
for as long as it is on screen — so a test that presses the install button and
then calls `pumpAndSettle` never settles. Waiting for the tree to go quiet is
waiting for a process that is on its way out. The press is followed by two
explicit pumps instead, and the reason is written at the helper.

## Alternatives considered

**A `.bat` or PowerShell script that waits for the old process and copies the
files.** Rejected: this product ships no interpreter, and a script that has to
be updated by the mechanism it performs is the same problem one level down.

**A small updater executable kept beside the application.** Rejected: it would
have to be updated by the thing it updates. Shipping it in the release solves
that only for the machines that already have the new one.

**A `.sha256` sidecar file.** Rejected as the source of the expected hash — see
the Decision. Not rejected as an *idea*: this implementation simply takes the
same fact from the answer that already names the file, and refuses when it is
absent.

**Choosing the asset by suffix.** Rejected: the alias and the versioned file
share a suffix, so the choice would fall to the order the API listed them in.

**Writing the downloaded bytes straight into the application folder.** Rejected:
a download that fails halfway, or a package that turns out not to be one, would
then have destroyed the running build before anybody noticed.

**Deleting files the new build no longer has.** Rejected for now: it needs a
manifest of what the old build shipped, which nothing currently writes. The
consequence is that an update can leave a stale file behind, and it is written
down here rather than discovered later.

**Replacing an installed copy's files by hand instead of running its
installer.** Rejected: the uninstall entry would keep naming the old version,
and repair/uninstall would then work from a mixture.

**A separate `sha256` implementation, or `package:crypto` only for this.**
Not an alternative that survives: `crypto` is already in the dependency set and
`sha256.bind(file.openRead())` streams a 20MB file without holding it.

**Downloading with `package:http`.** Rejected: `HttpClient` is in `dart:io`,
which this code already imports for `File` and `Process`, and the byte-counting
callback wants the raw stream rather than a convenience wrapper over it.

**Doing the copy on the frame's isolate.** Rejected: it is thousands of files,
and the spinner is the one thing telling the user this is not a crash.

**Waiting for the old process by pid instead of retrying the renames.**
Rejected: the hand-over is not guaranteed to know the pid — and the pid is not
the thing that matters. What matters is whether the file can be renamed *yet*,
which is exactly the question the retry asks.

**Asking whether the folder is writable by attempting the real operation.**
Rejected in favour of a probe file: a probe can be attempted before a 20MB
download, which is the point of asking at all.

**A rollback: keep a copy of the old build and put it back on failure.**
Rejected: it doubles the disk cost and the report file covers what a user
actually needs, which is to be told. The two-phase drop is what makes the
window for this small in the first place.

**Counting files in the hand-over window.** Rejected: the copy is on an isolate
and reporting per file would need a port and a `Stream` for a number nobody can
act on. The window says what is happening; that is what the user needs from it.

## Consequences

**Bought.** A user who is told there is a newer version can get it without
leaving the application, and the two shapes of copy each get the upgrade that
respects who owns their files.

**The development tree is a third shape.** A build produced by
`flutter build windows --release` and run from its own folder has no
`安装说明.txt`, so it is treated as a portable copy: pressing the button on such a
tree would replace `build\windows\x64\runner\Release` in place. It is reachable
only by somebody who has built the application themselves and then pressed a
button that says 下载并更新, and it is recoverable by rebuilding — but it is a
real consequence of the marker-file rule, and the alternative (refusing when no
marker *and* no `使用说明.txt`) would refuse the portable package too, which is
the shape that most needs this feature.

**No rollback, and the two-phase drop is the whole mitigation.** Between the
first rename and the last the folder holds a mixture. A failure there leaves
`.ltnew` files and a partially replaced build, and the report the next start
reads says so. This is a design decision and not an oversight: the only complete
answer is an atomic directory swap, which Windows does not offer for a directory
that is open.

**An installed copy's success now depends on Inno Setup's arguments.** `/SILENT`
`/SUPPRESSMSGBOXES` `/NORESTART` `/update` are the contract, and the `[Code]`
function is what makes the relaunch happen only for this caller. A future
installer that renamed the `[Run]` entries or dropped `WizardSilent` would break
the relaunch silently — the files would be right and the window would not come
back.

**One more thing that can only be verified by running it.** The native half —
the skipped single-instance check, the window that does not quit on close, the
`--apply-update` flag surviving `GetCommandLineArguments` — is not covered by
any of the six gates, which do not compile `windows/**`. It was checked by
building the release and running the packaging script's smoke test; the flag
reaching Dart is verified by the same script's string probes, which now include
two of the new sentences.

**Two seams, not one.** `UpdateInstallResolution` sits beside
`UpdateResolution` rather than inside it: asking is in `update_check.dart` and
replacing is in `update_install.dart`, and folding them into one name would make
one of those files import the other for nothing but the resolution object. Every
widget test that pumps the About card now has to install a
`ScriptedUpdateInstaller`, because `supported` is read while the card is built.

**The About card grew a second button and a sentence.** The by-hand
instructions are still on the card, and the hint that explains the button
replaces them only when the button is there — see `aboutUpdateInstallHint`
against `aboutHowToUpgrade`. Which of the two shows is the same condition that
decides whether the offer exists at all.

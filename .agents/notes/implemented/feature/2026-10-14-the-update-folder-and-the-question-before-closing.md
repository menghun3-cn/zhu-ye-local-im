# Agent Note: The update folder, and the question before closing

Status: implemented

## Problem

The one-click update worked, and two things about it were wrong in the way a
user notices.

The package was fetched into a folder under the system's temporary directory —
`local_transfer_update_*` — which is the one place a program may write without
asking and also the one place a user never looks. Three consequences followed.
A user who wanted to see what had been downloaded, or to run it by hand when
the automatic path failed, had to know a name nobody had told them and look in
a folder nobody opens. A cancelled attempt left twenty megabytes nowhere in
particular, and the next attempt fetched all of it again. And the
application's own promise — the About card says the program keeps things only
in its own folder and in `%APPDATA%\LocalTransfer` — was quietly false for the
duration of every update.

The second thing was the silence. Pressing 下载并更新 downloaded, checked,
unpacked, started a second process and ended this one, with a 600-millisecond
sentence on screen before the window went away. Nothing was destroyed and
nothing was hidden, but the one thing the user was never asked about was the
thing they would have wanted to be asked about: their window closing. The
request was one sentence — 下载的更新包放在 update 目录，应用更新时如果程序
已经启动，先提示，用户确认后再关闭进程进行更新，更新完毕后重新打开 — and
both halves of it are about who decides.

## Decision

**The package is fetched into a folder of the application's own called
`update`.** Not the root of that folder, which holds the build itself — a
download sitting beside the executable reads as part of the program, and a user
looking for one should not have to tell the two apart. Not the temporary
directory either, for the reasons above. `updateDirectory(root)` creates it on
demand, and the writability question is asked of the folder above it before
anything is fetched, exactly as it was before.

**The package stays there between attempts, and a retry starts from it.**
`prepare` hashes what is already in the update folder before it fetches
anything: the right bytes cost nothing to keep and twenty megabytes to fetch
again. One package at a time — every other file in the folder is deleted when a
new one is asked for. A package whose bytes failed the checksum is deleted,
because the failure sentence has claimed the bytes were thrown away since the
feature shipped, and with the package in a folder that outlives the attempt
that sentence had to become true or be reworded. A package whose *unpack*
failed stays: the package is not what failed, it checked out, and that sentence
was reworded instead.

**Installing is two calls with a question between them.**
`UpdateInstaller.prepare` does everything that can be done while this build
still runs — fetch, check, unpack — and answers with what is ready or why
nothing is. `UpdateInstaller.apply` starts the process that puts it in place
and ends this one. The split is the request made structural: what ends the
process is a different kind of thing from what does not, and the user is asked
between the two. The question is an `AlertDialog` on the About card —
关闭并更新？, the version that has been fetched, and what pressing it does —
with 取消 the quiet option and also the safe one: the package stays in the
update folder, nothing is in flight, nothing failed, and the same button offers
it again without fetching anything.

**The next start of the version a package carries takes it away.**
`clearFetchedUpdate` runs beside `clearStaleUpdateStages` from `main.dart`: the
only trace that says an update happened is the name, so a package named for the
version this build now *is* is twenty megabytes of nothing, and a package for
any other version is one whose update was cancelled or failed and stays,
because it is what a retry starts from. What hand-overs leave in the temporary
directory is still swept by the same function as before — the unpacked build is
the transient part and lives where transient things live.

**The hand-over itself is unchanged.** The second process, the two-phase drop,
the retried renames, the native runner reading the flag before the
single-instance check, the installer's second `[Run]` entry — none of it moved.
What changed is when it starts: after a word from the user rather than after a
button press.

## Testing

`test/ui/update_install_test.dart` covers the folder: that `updateDirectory`
puts `update` under the application and makes it when it is not there; that
`clearFetchedUpdate` takes away the package of the running version and leaves
any other; that a package already in the folder is not fetched again, that a
superseded one is deleted in the same attempt, and that a package whose unpack
failed stays. The three address tests now hand the installer a folder of its
own, because the real one fetches into the folder it runs from.

`test_flutter/ui/about_page_test.dart` covers the question: that it is asked
once everything that can be done while this build runs has been, that nothing
is handed over while it is open, that answering no leaves the package where it
was and offers it again without fetching, and that answering yes hands the
prepared update over and leaves the hand-over sentence on screen. A download
that is still running is held open with a completer, which is the only way to
look at the middle of one.

## Alternatives considered

**Leaving the package in the system's temporary directory.** Rejected — it is
the reason for this change: unfindable, re-fetched on every retry, and false
against the application's own promise about where it keeps things.

**The root of the application's own folder.** Rejected: that folder holds the
build. A zip beside `local_transfer.exe` reads as part of the program, and the
first thing a user does with an update folder is look inside it.

**One `install()` call with a confirmation callback.** Rejected: it keeps the
interface small and makes the question invisible — a closure in the middle of a
download is not where a reader looks for "this ends the process", and the About
page would be awaiting a call that shows a dialog from inside itself. The two
calls say out loud which part can be abandoned and which cannot.

**Asking before the download.** Rejected: the question is about closing, and
closing is the last step. Asked first, it would be a question about something
that had not happened yet, and a download that failed would have been answered
for nothing.

**A `ready` stage on the progress line instead of a dialog.** Rejected: what is
being asked is the window going away. A question that shares a surface with the
progress it follows reads as one more status line.

**Deleting the package on unpack failure too.** Rejected: the package is not
what failed — it checked out against the published checksum — and deleting it
would make a retry start from the network for no reason. The sentence that
claimed discarding was reworded instead.

**Reusing an unpacked staging folder across attempts.** Rejected for now: the
download is the expensive half and it is already reused, and a staging folder
that survives an attempt is one more thing to reason about being from the right
version. The unpack is a local copy and costs seconds.

## Consequences

**Bought.** A user can find the update package, can run it by hand when the
automatic path fails, and is asked before their window closes. A retry after
取消 costs a hash and an unpack instead of twenty megabytes.

**The application's promise is true during an update.** Everything an update
writes is under the application's own folder — the package in `update/`, the
`.ltnew` drops beside the files they replace — or in `%APPDATA%`. What it
writes to the temporary directory is the unpacked build, which is swept within
an hour of the hand-over that used it, the same as before.

**`update/` is a folder with a lifecycle, and it is defined here.** One package
at a time; the package of an applied update is taken away by the next start; a
cancelled or failed one stays until it is superseded or succeeds. A user who
looks inside it will find at most one file, and will find nothing at all on a
build that has never updated itself.

**The About card grew a dialog and a line.** The question between fetching and
closing, and the line that says a package is waiting. Both are new sentences in
both languages, and both are probes in the packaging script — the rewritten
hint sentence replaced its own probe in the same change.

**`UpdateInstallResult` is gone.** Nothing answers "handed over" any more:
`prepare` answers ready-or-failed and `apply` does not return in the
application. The stand-in the widget tests hand in records what it was handed
instead.

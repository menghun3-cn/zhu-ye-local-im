# Agent Note: A receive that failed left a file behind

Status: implemented

English | [中文](2026-10-10-a-receive-that-failed-left-a-file-behind.zh.md)

## Problem

A Transfer that ends badly still leaves something in the folder the user chose.
The bytes were written straight to the file's *final* name, so an interrupted
receive left an empty file wearing the peer's name — a file that reads as
"arrived" and cannot be opened. A real disk made the shape of it plain:

```
WinDirStat.exe       0 B           09:24:47   ← the receive that stalled
WinDirStat (2).exe   4,214,704 B   09:25:01   ← the same file, retried
```

The retry got its file. It just did not get its *name*: `incomingPathFor`
resolves a clash by numbering rather than overwriting, which is right for a file
the user owns and wrong for the wreckage of a Transfer nobody completed. So the
folder keeps both — a zero-byte file that is not a file, and a `(2)` that exists
only because of it.

The same arrangement had a second cost, already paid. `acceptInto` used to
record the received file's path as soon as the receive was *answered*, a moment
at which no byte has arrived; an image message then decoded an empty file, failed
permanently, and drew a broken frame (PR #35, `0857ff7`). That half is fixed.
What was left over is the file on disk, which is what this note is about.

## Decision

A receive writes to a staging name of this Device's own making, and is renamed
to the name it keeps only once every byte has been verified and hashed.

```dart
// lib/app/views.dart
File stagingPathFor(Directory directory, String name)
// → <directory>/<sanitised name>.<16 hex digits>.part

// lib/app/app_controller.dart, in acceptInto
final staged = stagingPathFor(directory, item.name);
final sink = await FilePayloadSink.open(staged);
// …then, when the Transfer's outcome is TransferCompleted:
await landing.sink.close();
final finalPath = incomingPathFor(landing.directory, landing.name);
await landing.staged.rename(finalPath.path);
// …and when it is anything else:
await landing.sink.close();
await _discardStaged(landing.staged);
```

Three details are each a decision in their own right.

**The staging name lives in the destination folder.** A rename is only a rename
within one volume — staging in the system temp directory would make the last
step a copy, and a copy can itself be interrupted and leave half a file under a
name that looks whole. Same folder, and the last step is atomic.

**The staging name says what it is.** `<name>.<token>.part` — a user who opens
the folder mid-transfer sees an unfinished file and can tell; the old name hid
that behind the peer's name. The token keeps two attempts at one name apart and
keeps the staged file off a name the user might already own.

**The final name is decided at the rename, not at the answer.** `incomingPathFor`
is asked at the moment the bytes are published, so a name that was free when the
Offer was accepted but has been taken since gets numbered rather than
overwritten. Deciding early and renaming late would also have worked for the
common case, and would have handed the last step a name somebody else may own.

`FilePayloadSink.close()` became a shared, awaitable future as part of this.
Renaming needs the handle gone, and closing has two callers that do not know
about each other: the Transfer closes its sinks as it settles, and the landing
owner closes them again before it renames. A second `close` that reported before
the first had finished would hand back a file that could not yet be touched.

## Alternatives considered

**Delete the final-named file when the Transfer fails.** The smallest possible
fix, and rejected: it leaves the window that matters — the whole of a transfer's
life — with an empty file in the user's folder under a plausible name. It also
solves the `(2)` by a deletion that has to be sure the file is ours, on a path
where being wrong means deleting something the user put there.

**Decide the final name when the Offer is answered, and only stage the bytes.**
Rejected: the name would be reserved for the length of the transfer, so a file
the user creates in the meantime — or a second receive of the same name — would
be overwritten by the rename. Numbering late is what makes the collision
question get the right answer.

**Stage in the system temp directory.** Rejected: cross-volume, so the publish
step stops being atomic, which is the one property the whole arrangement buys.

**Clean up stale `.part` files at start-up.** Kept as a possible follow-up
rather than done here: this fix removes the files a *Transfer* abandons, which is
every ending the app can see. A crash or a kill leaves one behind, and it is
named as unfinished and holds no final name, so a sweep is tidying rather than
correctness. Adding it now would mean deciding a temp-file retention policy,
which is a separate question.

**Keep the written bytes for a resume.** The sink supports a `resume` offset and
`cancel` documents the partial bytes as "what makes the attempt resumable", but
nothing calls it: `acceptInto` opens sinks with `resume: false`, so those bytes
have never had a reader. What was being kept was litter, not a capability. If
resume is ever built it needs a staging name it can *find* again, which is a
decision about names, not about whether to delete this one.

## Consequences

- A retry of a file whose first attempt died gets the name it asked for instead
  of a number beside a file that never arrived.
- A folder being received into now briefly holds `<name>.<token>.part`, which is
  honest about being unfinished and disappears when the transfer completes.
- `localPath` appears once the Transfer has ended rather than the instant it
  does — publishing is a close plus a rename. The conversation redraws from the
  controller's notification, and the tests that wanted a landed picture now wait
  for the path rather than for the state.
- A crash still leaves a `.part` file. It is unmistakably unfinished and it does
  not occupy a final name, which is strictly better than the old behaviour, and
  it is the one case a start-up sweep would cover.
- `dart test` covers the new function directly (`stagingPathFor` stages inside
  the directory, under a name that is not the final one, and two attempts at one
  name do not collide) and the behaviour end to end: a receive that is cancelled
  leaves the folder empty, and the retry of the same file lands as `report.pdf`.

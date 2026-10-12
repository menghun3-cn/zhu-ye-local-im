# Agent Note: Make the profile store create the directory it writes to

Status: implemented

English | [中文](2026-09-30-profile-store-missing-parent-directory.zh.md)

## Problem

`profile_location.dart` decides where a Device's identity lives and states its
own half of the bargain in its header: *"Nothing here creates anything. These
functions decide a path; the store and the transfer sink are what make it
exist."*

`FileProfileStore.save` did not make it exist. It wrote the new content into a
sibling temp file, deleted the target, and renamed the temp over it — and
`File.writeAsString` does not create missing parents. So the first save on a
machine that had never run the app threw:

```
PathNotFoundException: Cannot open file,
  path = 'C:\Users\owner\AppData\Roaming\LocalTransfer\profile.json.tmp'
  (OS Error: The system cannot find the path specified., errno = 3)
```

This was not an edge case. Every directory this project computes a profile path
inside is absent on a first launch: `%APPDATA%/LocalTransfer` on Windows, and on
Android the `incoming` folder under the app's files directory when the user
accepts a Transfer into the field it is pre-filled with. `loadOrGenerateLocalProfile`
calls `save` immediately — it mints an identity and persists it before the Device
has a fingerprint to announce — so the failure landed before the first frame. On
Windows the app could not start at all.

No test caught it, and the reason is worth recording: every `FileProfileStore`
test built its store inside `Directory.systemTemp.createTemp`, which exists. The
suite was thorough about corruption, atomic replacement and left-over temp files,
and had nothing to say about the directory the file goes in, because the fixture
had already created it.

## Decision

`FileProfileStore.save` creates the parent directory of its target, recursively,
before writing the temp file:

```dart
await temp.parent.create(recursive: true);
```

Recursive rather than one level, because the path is computed elsewhere and this
store is in no position to hold an opinion about how deep it may be.

## Alternatives considered

**Have `openPlatformSeams` create the directory.** Rejected: it knows the profile
path but not the incoming directory, which the transfer sink is responsible for,
so the fix would cover half the paths and leave the other half in a third place.
The store owning its own file is the arrangement `profile_location.dart` already
describes.

**Have `profile_location.dart` create the directory while computing the path.**
Rejected: those functions are pure and are called by tests to ask what the Android
and Windows rules resolve to. A function that writes to disk when asked a question
cannot be used to ask the question.

**Put the profile somewhere guaranteed to exist**, such as `%APPDATA%` directly or
the system temp directory. Rejected: both scatter this Device's identity into a
namespace it does not own, and the temp directory does not survive a reboot —
which is the one property the file exists for.

**Treat a failed save as non-fatal and carry on in memory.** Rejected: it turns a
loud, fixable error into a silent one. A Device that cannot persist has to be
paired again after every restart, and nothing on screen would say why.

## Consequences

- A first launch now works on both v1 platforms. Both were affected and neither
  had been exercised from a clean profile directory.
- `test/profile/profile_store_test.dart` pins it with two cases that write into
  directories that do not exist yet — one level deep, and several.
- `test_flutter/platform/seams_test.dart` covers the same ground through the real
  entry point: it opens the seams against a temporary `%APPDATA%`, mints an
  identity, and opens them a second time to find the same Device.
- The store now makes filesystem changes beyond its own file. That is deliberate
  and it is a widening of what the class does; the alternative is an app that
  cannot start, which is not.

# Agent Note: The probe that survived two rewrites

Status: implemented

English | [中文](2026-10-20-the-probe-that-survived-two-rewrites.zh.md)

## Problem

Two releases in a row shipped a tag and no artifacts.

`v0.1.9` and `v0.1.10` both passed the version check, built the Android APK
successfully, and then failed in the same place: the Windows packaging script
verifies that the `app.so` inside the zip really is the current code, and that
verification could not find its own text.

The check is worth having. `build/dist/*.zip` does not update itself, so a
green test suite says nothing about the zip — the repository has already had a
"tests all green, package still old" incident, where a user reported a fix
that was not in the binary they were running. So the script searches the
packaged `app.so` for the sentences of recently added features, and fails the
build if any of them is missing.

The problem was what those sentences were. The probe list held **the Chinese
wording itself**, spelled out in the script:

```powershell
$newProbes = @(
    '还没有对话。只要扫描到设备，它就会自动出现在这里，可以直接连接。',
    ...
)
```

PR #103 reworded one message — the "About" page's description of what the
program does, in `aboutDescription` — to mention that the app now checks for
updates on a schedule. The wording changed; the key did not. The packaged
binary contains the new wording, the script kept looking for the old one, and
the release pipeline went permanently red.

**It had already happened once before.** The same file records an earlier
occasion in which `conversationListEmpty` and `conversationPickOne` were
reworded and the old sentences had to be swapped out by hand. The comment
above the list said so, in as many words: *"this list is a must-change item —
every time a feature is added, add that feature's own sentence and delete the
ones it replaced."*

That instruction is exactly what made it fail twice. It put a manual step
between "a developer rewords a message" and "a release can ship", and the
step was easy to forget — it lives in a script, several files away from the
message it concerns, and nothing fails when it is forgotten. The only thing
that notices is the release pipeline, and it notices by refusing to publish.

So the cost was not one broken release. It was two: nothing has been
published since `v0.1.8`, and the two tags `v0.1.9` and `v0.1.10` sit on
`master` naming releases that do not exist.

## Decision

**The probe list holds l10n keys; the script reads the current wording from
`app_zh.arb`.** The list moved to `scripts/packaging-probes.json` and names
words by key:

```json
{ "probes": ["conversationListEmpty", "aboutDescription", ...] }
```

The script resolves each key against `lib/l10n/app_zh.arb` and searches the
`app.so` for the wording that is there *now*. Rewording a message therefore
costs nothing: the key is unchanged, so the probe follows it.

The key is the stable thing. A word only leaves the list when it leaves the
product — and the script now says so when that happens, naming the key that
is missing instead of printing a Chinese sentence nobody can search for.

**The list lives in JSON rather than inline in the script.** An inline array
can only be read back by regular expression over the script's own source, and
this script's comments contain apostrophes (`'发送图片'` probe **must be
deleted**). A regex over that source is a way to be bitten by a comment. JSON
is read by a program, not by a pattern.

**`test/process/packaging_probes_test.dart` guards the part that is still a
human's judgement.** `dart test` — the gate that always runs on a developer
machine — now checks that every key in the list exists in `app_zh.arb`, that
none of them carries a placeholder (those survive in `app.so` only as
fragments), and that none of them occurs inside another word of the
application.

That last one is the check the old comment described in prose: a word like
「对话」 also occurs inside 「原生对话框」, so finding it proves nothing about
which build is in the package. The repository has been bitten by exactly that
before. It is now a failing test rather than a warning in a comment.

**Length is not the test.** The first version of that test required four
characters, on the theory that short words are weak probes. That is wrong:
「离线」 is two characters and appears in exactly one word of the whole
application, which makes it as good a proof as any sentence. What matters is
whether *another* word contains it, so that is what the test checks.

## Alternatives considered

**Rewrite the probe by hand, one more time, and leave the design alone.**
Rejected: this is the third occurrence of the same defect, and the previous
one was fixed the same way. It works until the next rewording.

**Drop the probe check, since it is the thing that keeps failing.** Rejected
on the same grounds the note on
[the first release](2026-10-12-a-tag-builds-the-three-packages.md) gives: it
is the only part of the whole repository that reads the **delivered artifact**
rather than the tree that produced it, and it has already caught two real
problems — a deleted sentence that should have been removed, and an icon font
that had stopped being regenerated. The package is what the user runs; the
check that opens it is the last honest gate.

**Probe for the app.so's hash instead of its text.** Rejected: a hash
proves "different from last time", not "is the current code". Two builds of
the same source differ, and a stale build differs too — it only fails to
differ if nobody changed anything.

**Probe every word of the application, so no list can go stale.** Rejected:
the words are in `app.so` only where the code can reach them, and a word
behind a feature that is compiled but never displayed is not there to be
found. More importantly, the whole value of the probe is that it names
*specific* things: it is a list someone chose deliberately, so that a missing
sentence has a name attached to it.

**Keep the sentences inline, but generate the file from the ARB.** Rejected:
this adds a code generator and a second place the list can live, to solve a
problem that reading one JSON file solves.

**Move the check into `release.yml` instead of the packaging script.**
Rejected: the packaging script is the only place that has the packaged
`app.so` in hand, and CI runs that script rather than a second implementation
of it — a separate packaging path is the thing the
[tag note](../process/2026-10-12-a-tag-builds-the-three-packages.md) was
written against.

## Consequences

- **Rewording a message no longer touches the release.** The probe follows
  the key.
- **The list is still a human's decision, and now a checked one.** A key that
  no longer exists, a key with a placeholder, and a key that collides with
  another word each fail `dart test` — on the machine, before the tag.
- **`scripts/packaging-probes.json` is a new file with a new format.** It is
  read by the packaging script and by the test, and it is the only place the
  probe list lives.
- **The gate still cannot see the packaged artifact.** `dart test` checks
  that the probe list is *sound*, not that the package *contains* it; that
  last step is what only a Windows build can do, and it is what the release
  pipeline does. The gap this note closes is the one where a reworded
  message made the release impossible — not the one where the package is
  stale.
- **`v0.1.9` and `v0.1.10` remain on `master` naming releases that do not
  exist.** They are not moved or deleted — a published tag is not to be
  overwritten — so the next release is `v0.1.11`, and those two tags are
  the record of two releases that were prepared and did not ship.


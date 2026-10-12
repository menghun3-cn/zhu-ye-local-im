# Agent Note: A fixed name for the package LAN scripts pull

Status: implemented

English | [中文](2026-10-12-a-fixed-name-for-the-package-lan-scripts-pull.zh.md)

## Problem

Every artifact this repository produces carries its version in its file name:
`LocalTransfer-<version>-windows-x64-portable.zip`, `…-setup.exe`, `…-android.apk`.
That is deliberate — a package whose name does not say what is in it gets installed
twice and discussed wrongly — and it means the name changes on every release, which
under the rhythm in `AGENTS.md` §9 is nearly every release.

So a script on the LAN that pulls the package from a machine serving `build/dist`
cannot hardcode the name. Its two options today are to be edited on every release,
or to fetch a directory listing and pattern-match it, which depends on which HTTP
server is serving the directory and how that server renders an index. Neither is a
property of the package; both are chores that go stale silently.

GitHub does not solve this case. `releases/latest` is a *release*, not a file:
`releases/latest/download/<name>` still needs the exact asset name, version
included, so the only version-independent URL is one that asks the API first. And
the LAN case is precisely the one where the network may not reach GitHub at all —
the machine hosting `build/dist` is the distribution channel.

Nothing in the repository published a version-independent name.

## Decision

`scripts/publish-latest.ps1` publishes, for one source file, one alias whose name
contains no version: a copy of the source under a fixed name in the same directory,
plus a `<alias>.sha256` sidecar holding the hash of what was copied.

Both packaging scripts call it as their **last** step, after their own verification
has passed — `pack-windows-portable.ps1` after the zip has been read back and
checked (and after the optional smoke test, when it runs), and
`pack-windows-installer.ps1` after the setup executable has been checked. The two
names are:

- `LocalTransfer-latest-windows-x64-portable.zip`
- `LocalTransfer-latest-windows-x64-setup.exe`

From that ordering comes the invariant that makes the alias worth trusting:
**`latest` exists if and only if a package passed every check.** A run that fails
anywhere leaves the previous alias untouched — old, but known good — instead of
publishing a package that failed a check and hoping the failure is noticed later.

Two details are load-bearing rather than cosmetic.

**The alias is published by rename, not by overwrite.** The helper copies the
source to `<alias>.new` and then renames it over the alias, because a rename within
a volume is atomic: a puller running concurrently with a repack reads either the
previous file or the new one, never a partially written one. Writing the alias in
place would leave a window in which the file has been truncated but not yet
refilled, and a puller that lands in that window gets a file of plausible length
that fails to unzip — far harder to diagnose than a missing file.

**The helper re-hashes the alias after the copy** and refuses to publish when it
does not match the source. The alias's only meaning is "this is the package that
was just verified"; a copy that silently did not happen is worse than no alias.

The sidecar is written in `sha256sum` format (`<lowercase hex><two spaces><file
name>`), with no BOM and LF only. Pullers get a check that a large download over
Wi-Fi arrived intact — the failure this is most likely to catch — and they get it in
a format their own tooling already reads, instead of one this repository invented.
The published hash is the one computed over the versioned file, so the alias and the
thing it duplicates can be compared against the same value.

The publish rule lives in one place. Each packer supplies only its own artifact and
the name to give it; neither reimplements the copy, the rename, or the hash check.
`pack-windows-installer.ps1`'s header already argues this way about verification — a
rule stated twice is a rule two files can disagree about — and the alias rule is the
same kind of rule.

**`release.yml`'s artifact paths were changed in the same commit.** They were
`build/dist/*-portable.zip` and `build/dist/*-setup.exe`, and the aliases match both
globs; left alone, a release would have carried five attachments instead of three,
two of them byte-identical duplicates of the pair beside them. The paths now name
the version explicitly. The count on the Releases page stays at three, which is what
[the released-artifacts note](2026-10-12-a-tag-builds-the-three-packages.md) and
`AGENTS.md` §9 both say.

## Verification

The helper was exercised on its own before either packer was wired to it: first
publication, republication over an existing alias, and the three refusals (missing
source, a `-Name` containing a directory, an empty source). The sidecar was read
back as bytes to confirm no BOM and no CR, and its content compared against
`Get-FileHash`. That no `.new` file survives a successful run is checked as well.
End to end, both packers were then run and the aliases they produced were opened and
hashed against their sources.

## Alternatives considered

**Write the alias with `Copy-Item -Force` onto the name.** The shortest version of
the feature — one line per packer. It lost on the truncation window described above
and on having no way to notice a copy that did not happen. Doing it by rename costs
one temporary file that lives for milliseconds.

**Let the CI glob pick the aliases up and attach them to the Release.** Free, since
the paths already matched, and it would give internet-connected machines the stable
URL `releases/latest/download/LocalTransfer-latest-windows-x64-portable.zip`. It
lost because it makes the release carry two names for each of two files, which
invites "which one do I download?" at exactly the moment a user is deciding, and
because the release-side notion of "latest" already exists and is not a file name —
it is the tag. Excluding them costs one comment in the workflow.

**The same logic written inline in both packers.** Lost to the rule that a shared
rule gets one implementation. The atomic rename and the after-copy hash check are
exactly the parts that would get fixed in one file and left wrong in the other, and
neither packer's own review would show it. A fourth script in `scripts/` is the
cheaper mistake.

**A `latest.zip` directory junction or symbolic link.** Lost because creating one on
Windows needs elevation or Developer Mode, it does not survive being copied to a
share or into a zip or across a filesystem without links, and a static file server
may refuse to follow it. A real file is boring and always works.

**One `latest.txt` manifest listing both artifacts and both hashes.** Attractive
because pullers would get the version too, and lost because it has two writers: the
portable script knows only the zip's hash and the installer only the executable's,
so each run would have to read the other's half and write it back — a merge problem
invented for nothing. A per-artifact `<alias>.sha256` gives each artifact exactly one
writer, and `sha256sum -c` already reads that format.

**Have the portable script publish both aliases.** It runs first, so the executable
does not exist yet; publishing its alias would mean either writing a name that points
at the previous release's installer or reordering the packers around a rule that has
nothing to do with either. Each artifact's alias is published by the script that
produces it.

## Consequences

**Bought.** A LAN-side puller has a fixed URL and a way to verify what it got. The
alias cannot be a package that failed a check, because it is written after the
checks. A repack is safe to run while something is downloading. Nothing has to learn
about versions in order to use it.

**Paid.** `build/dist` now holds a versioned pair, an alias pair, and two sidecars,
and each alias is only as current as the last successful run of the packer that
writes it. Running `pack-windows-installer.ps1` alone updates the installer alias and
leaves the zip alias at whatever build it last saw, so the two aliases can come from
different builds. That is accepted rather than fixed: each alias names its own
artifact, both packers print the version they published, and the alternative —
coupling the two scripts so that neither can run alone — would remove a script's
ability to be run on its own, which is how the installer is normally rebuilt.

**Not covered.** The alias says nothing about being *newer* than what a puller
already has. It is a name, not a comparison: a puller that wants to know whether it
needs to update should read the version out of the package it already holds — the
portable zip's `使用说明.txt` carries the version on line 1 and the commit on line 4
— or compare a stored hash against the sidecar.

**Still unexercised by the gate suite.** No gate in `AGENTS.md` §5 runs either
packer; the alias is exercised the first time a packer runs, which is a local pack or
a tag. A CI job that ran the two packers on a pull request would cover this and its
two predecessors ([the define without its D](../bug-fix/2026-10-12-a-define-that-was-spelled-without-its-d.md),
[the steps that had only ever run on one side](../bug-fix/2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md)),
and that job is still not written.

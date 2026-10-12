# Agent Note: Make the Windows package a scripted, self-checking build

Status: implemented

English | [中文](2026-10-08-packaging-is-a-script-not-a-ritual.zh.md)

## Problem

`build/dist/*.zip` is what a person outside this repository actually runs, and
it had quietly drifted from the source twice in one day.

The first time, a fix for a crash-on-open was committed, all six gates went
green, and the package still contained the previous build. The report came back
as "why is it grey on the other machine" — the other machine was running the
old `.zip`, because nothing in the gate set builds one. `dart test` and
`flutter test` measure the source tree; the archive measures the last time
somebody remembered to run `flutter build` and then re-assemble a directory by
hand.

The second time, the package was two commits stale, and it was missing
`vcruntime140.dll`, `vcruntime140_1.dll` and `msvcp140.dll` entirely — while its
own `使用说明.txt` promised they were included. The executable imports all three
dynamically, so the archive would fail to start on any machine without the VC++
redistributable installed. It could not fail here: this machine has them in
`System32`.

Neither failure is detectable by looking at the source, and neither is
reproducible by re-running the gates. Both are properties of an artifact that
was assembled by hand.

## Decision

Packaging is a script: `scripts/pack-windows-portable.ps1`. It builds, locates
the VC++ runtime from Visual Studio's redistributable directory, assembles the
directory, writes the archive, and then **verifies the archive it just wrote**.

The verification step is the point of the script, not a nicety:

- every required file is looked up **inside the archive**, not on disk;
- the layout is checked, so a package cannot silently gain an extra top-level
  directory;
- the newly added UI strings are searched for in the packaged `app.so`, and the
  strings are chosen to be full sentences the new code alone contains;
- the archive is extracted to a temporary directory and launched, checking that
  it stays responsive and binds its discovery and pairing ports.

`-SkipBuild` re-packs an existing build when only the readme changed.
`-Smoke` adds the launch check.

## Alternatives considered

**Add a gate to `AGENTS.md §5` that builds the package.** Rejected as the
primary mechanism: it would put a multi-minute Windows build in the path of
every commit, and a build that succeeds does not establish that the archive
contains the new code — the second failure above was a successful build.

**Trust the mtime of `build/windows/x64/runner/Release`.** Rejected: this was
the reasoning that produced the first stale package. It also cannot see the
missing runtime, which is a property of the assembly step rather than of the
build.

**Keep assembling by hand and write the checklist into the readme.** Rejected:
the manual step is precisely what was skipped, twice, under time pressure. A
checklist that lives next to the manual step does not survive the pressure that
makes the manual step get skipped.

**Copy the runtime DLLs from `C:\Windows\System32`.** Rejected: that is not a
licensed redistribution source, and it silently couples the package to whatever
version this machine happens to have. Visual Studio's
`VC\Redist\MSVC\<ver>\x64\Microsoft.VC143.CRT` is the supported source, and the
script searches for it across both program-files roots and all installed
editions rather than hardcoding a path.

## Consequences

- **The archive is now the thing that gets checked, not the source.** A green
  gate run no longer implies a correct package, and the script is the only way
  to get a package that has been checked at all.
- **The packaged readme is generated from `packaging/使用说明.txt`.** It lives in
  the repository rather than beside the build output, because it is a document a
  person maintains — keeping it under `build/` would mean a fresh clone can only
  produce the minimal fallback, and the full text (pairing, ports, firewall,
  troubleshooting) would exist on one machine. The build date and commit are
  rewritten on each run rather than stored in the template, where they would go
  stale. `build/dist/使用说明.txt` is still consulted as a second choice for
  compatibility with the earlier hand-assembly layout.
- **The script detects the stale-file case instead of deleting**: it overwrites
  in place and then warns about files present in the staging directory that the
  current build does not produce. The sandbox this was developed in refuses
  deletions under `build/dist` — including single files — so a
  delete-then-rebuild approach was not viable there. Overwriting is also the
  more conservative behaviour for a directory a person may be looking at.
- **The package grows by 173 KB** (three runtime DLLs), from 12.20 MB to
  12.44 MB. This is the cost of it actually running on a clean machine.
- Anyone changing a user-visible string should expect the verification step to
  fail until the probe list at the top of the script is updated. That is
  intentional: the list is the statement of what "this package is current"
  means.

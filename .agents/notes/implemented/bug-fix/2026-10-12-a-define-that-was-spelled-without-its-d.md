# Agent Note: A define that was spelled without its `/D`

Status: implemented

English | [中文](2026-10-12-a-define-that-was-spelled-without-its-d.zh.md)

## Problem

The third `v0.1.0` pipeline run got further than the first two — the version
check passed, the Android APK built, the portable zip was assembled, compressed,
smoke-tested and verified — and then stopped at `打安装包`, the step that turns
that verified directory into an Inno Setup installer. ISCC printed one line:

```
Unknown option: /LTDocs=D:\a\zhu-ye-local-im\zhu-ye-local-im\packaging
```

and [`scripts/pack-windows-installer.ps1`](../../../../scripts/pack-windows-installer.ps1)
threw `ISCC 失败 (exit 1)`. Nothing shipped.

ISCC receives preprocessor definitions as `/D名字=值`: the `/D` is the switch that
says "define this", and the name is `LTDocs`. The argument list passed six
definitions and **five of them were spelled `/DLT…`**. The sixth had lost its
`D` — one character, in a line that nothing had ever executed.

**The `.iss` was never parsed on that run, and the timing says so.** The whole
ISCC session — banner to exit — took 0.34 s (`==> ISCC` at `07:30:32.0258790`,
the throw at `07:30:32.3662966`), and CI's log contains **no** `Preprocessing`,
`Reading file:`, `Parsing` or `Compressing` line anywhere. A compile that gets as
far as reading the script takes 8.6 s here and prints dozens of them. So the run
never reached the file at all, and everything in it was unexercised for the third
time in a row.

**ISCC does not tolerate the misspelling; it just reports it badly.** Re-running
the same argument list here with ISCC 6.7.3 reproduces the run exactly: exit 1
after 0.021 s, seven lines of output, no `Parsing`, and the setup executable from
the previous attempt left untouched on disk. The complaint goes to **stderr**,
which is why PowerShell surfaced it as a `NativeCommandError` and why the captured
CI log places it *above* the banner ISCC prints first — a red job that reads as
though the compiler had started work. The failure is loud, and `$LASTEXITCODE`
catches it, so nothing was silent. What the message cannot do is name *which*
define is missing: it names an option the caller does not believe it passed.

Two things made that possible, and both are about where the mistake could have
been seen:

- **Nothing in this repository runs the installer script.** The six gates in
  `AGENTS.md` §5 do not enter `packaging/`, the script has no local caller, and
  the release job is its only invocation. Its first ever execution was a release.
- **The file the argument list was copied from taught the same spelling.**
  `packaging/local_transfer.iss`'s header comment listed all six defines as
  `/LTStage`, `/LTName`, … `/LTDocs` — no `/D` on any of them. A comment that
  documents an interface is read *as* the interface. It had been wrong since it
  was written and could never be noticed, because nothing consumed it.

There was a third reason the local escape hatch did not exist. The script looked
for ISCC only on `PATH` and under `C:\Program Files*\Inno Setup 6\` and the `D:`
equivalents. This machine has neither, and no `choco` — so "I'll just run it here
once" was not available either, which is how a step stays unrun for a year.

## Decision

**The argument is `/DLTDocs=`.** The typo is corrected, and so are the six lines
of the `.iss` header comment that taught it; the comment now also says what the
`/D` is for and records that it used to be written wrong, so the next reader does
not treat the old spelling as a template.

**The script no longer trusts that the two lists agree.** Before invoking ISCC it
extracts every `{#名字}` placeholder from the `.iss` and requires a matching
`/D名字=` in the argument list, failing with both lists printed if one is missing:

```powershell
$defined = @{}
foreach ($a in $isccArgs) {
    if ($a -match '^/D([A-Za-z_][A-Za-z0-9_]*)=') { $defined[$Matches[1]] = $true }
}
$issText = Get-Content -Path $iss -Raw -Encoding UTF8
$used = @(
    [regex]::Matches($issText, '\{#([A-Za-z_][A-Za-z0-9_]*)\}') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
)
$undefined = @($used | Where-Object { -not $defined.ContainsKey($_) })
```

The `.iss` is the authority on what it needs; the guard only checks that the
caller supplies it. It costs a file read and cannot drift, because a placeholder
added to the script and not defined on the command line fails the same way. For
this particular defect it changes nothing about *whether* the job goes red — ISCC
already exits 1 — and everything about *why the reader understands it*: one
message names the define that has no argument, the other names an option the
caller never thought it passed.

**ISCC is discovered where it actually installs.** The candidate list now starts
with `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` — the location Inno Setup's
own installer uses for `/CURRENTUSER`, which needs no administrator rights — and
the not-found message teaches that install command alongside the existing
`choco install innosetup -y`. Paths are built by string interpolation rather than
`Join-Path`, so a 32-bit host with no `ProgramFiles(x86)` produces a candidate
that `Test-Path` rejects instead of a throw.

**The step has now been run on this machine.** Inno Setup 6.7.3 was installed per
user from the official GitHub release (sha256 checked against the API's asset
digest), and
[`scripts/pack-windows-installer.ps1`](../../../../scripts/pack-windows-installer.ps1)
produced `build/dist/LocalTransfer-0.1.0-windows-x64-setup.exe`: 11,283,994 B,
`Successful compile (8.594 sec)`, and a version resource reading
`ProductVersion 0.1.0` / `ProductName 竹叶局域网传输` / `FileDescription 竹叶局域网传输 Setup`.
That last check is the point: the exit code reports that ISCC accepted its
arguments, and says nothing about what it then substituted into them. The version
resource is where the substitution is visible — on the artifact, not on the
console.

## Alternatives considered

**Fix the typo and stop there.** Rejected: the typo is one instance of "an
argument list and a script that must agree, maintained by hand and never
executed". Correcting the instance leaves the class intact, and the class has now
produced a red release job three times — the zip separator, the Kotlin import,
this one — with every occurrence in a step that only a tag ever runs.

**Give the guard its own list of expected names.** Rejected: that is a third copy
of the same fact, and the copy that drifts is always the one nobody runs. The
`.iss` already states which names it needs, in the only place that has to be
right for the installer to build.

**Make the comment authoritative and generate the argument list from it.**
Rejected: the comment is prose. `{#名字}` is a machine-readable token that the
preprocessor itself resolves, so the check reads the same thing the compiler
reads. Parsing a comment would re-introduce the failure mode it is meant to
catch — a document that is believed rather than consulted.

**Stop passing defines and hardcode the paths in the `.iss`.** Rejected: this is
what the defines exist to prevent. The stage directory is
`F:\asc_workspace\…` here and `D:\a\zhu-ye-local-im\…` on the runner, so one
`.iss` serves both only because the caller supplies the paths.

**Leave the ISCC search alone and install via `choco` here.** Rejected: there is
no `choco` on this machine, and requiring administrator rights to exercise a
build step is precisely how the step stays unrun. The per-user install is the
no-UAC path and costs one line in the candidate list.

**Vendor ISCC into the repository.** Rejected: 10 MB of third-party binary in git
so that one script can be run occasionally. The version belongs to whoever
installs it, and the `.iss` states the floor it needs.

**Add a workflow that runs the two packaging scripts on every pull request.**
Deferred, not rejected — the same open item
[the sibling note](2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md)
records. It is the change that would actually close this class, and it is larger
than a typo fix.

## Consequences

- **The installer path is proven on one machine, by one compiler.** CI's ISCC is
  a 6.x from `choco` (`C:\ProgramData\Chocolatey\bin\ISCC.exe`); this machine's is
  6.7.3 via `/CURRENTUSER`. Both are 6.x, and the download page's current release
  is already 7.1.0 — so a future `choco install` could move the compiler major
  without anyone choosing to. The `.iss` needs 6.3 or newer for
  `ArchitecturesAllowed=x64compatible`.
- **The `.iss` body has now been compiled once, by this machine.** Its `[Files]`
  section resolved every `Source` pattern: the `Compressing:` lines name the stage
  directory's contents, `packaging\安装说明.txt` from `{#LTDocs}`, and the
  readme. The previous three runs never got that far, so this is new information
  rather than a re-run.
- **The gate suite still does not enter `packaging/`.** What changed is that the
  script now refuses to hand a mismatched argument list to ISCC. A `.iss` that
  names a file which does not exist is still only caught by running it — the
  compile reports that, not the guard.
- The Chinese file names render as mojibake in a captured log because ISCC writes
  them in the machine's ANSI code page while the capture wrote UTF-8. That is
  why this script deliberately does *not* set `[Console]::OutputEncoding`, unlike
  the portable-pack script whose producer emits UTF-8. The two scripts are not
  inconsistent; they face opposite producers.
- **`v0.1.0` is deleted and re-pushed onto the new `master` tip.** The tag moves;
  the version does not. Legitimate for the same reason as before: the release
  pipeline failed on its own tooling rather than on the product, and `releases` is
  still empty, so nobody has downloaded anything under this tag name.

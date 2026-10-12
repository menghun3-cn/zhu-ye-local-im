# Agent Note: Two build steps that had only ever run on one side, and a third that had never run at all

Status: implemented

English | [中文](2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.zh.md)

## Problem

`v0.1.0` is the first tag this repository has ever pushed, so the release
workflow's first execution was also the pipeline's first execution. On it, the
version check passed and **both build jobs failed**. Nothing shipped: the
`release` job needs both of them, so no Release was created and no artifact was
ever uploaded.

Neither failure was in the product. Both were in the tools, and both were
assumptions that had only ever been exercised on the machine the tool was written
on — or, in one case, nowhere.

| Where | What it assumed | Why that stopped holding |
| --- | --- | --- |
| [`scripts/pack-windows-portable.ps1`](../../../../scripts/pack-windows-portable.ps1) | zip entry names are spelled with `\` | the separator follows the **PowerShell edition**: Windows PowerShell 5.1 (.NET Framework) writes `data\app.so`, PowerShell 7 (.NET 5+) normalizes to `data/app.so`. Every local run of the script is 5.1; the workflow's `shell: pwsh` is 7 |
| [`android/app/build.gradle.kts`](../../../../android/app/build.gradle.kts) | `java.util.Properties()` names the JDK package | in a Gradle Kotlin DSL script `java` is the Java plugin extension, so `java.util` is read as a member lookup on it — `Unresolved reference 'util'`, then the same for `'io'` |
| [`scripts/fetch-sources.ps1`](../../../../scripts/fetch-sources.ps1) | the file's own bytes are UTF-8 | with no BOM, PowerShell 5.1 decodes a `.ps1` as the machine's ANSI code page — 936 here — and the mojibake is a syntax error. Nine of them |

The first two are the failures that stopped the release. The third was found
while looking for others of the same kind; it had never been run anywhere, so
nothing had ever reported it.

**How the Kotlin one got there.** The signing block the pipeline needs was added
by `4f702ea`, *build the three release packages from a tag*, and the last Android
build on this machine is the emulator run of 2026-10-10 — five days earlier.
`git log -S 'java.util.Properties' -- android/app/build.gradle.kts` returns that
one commit. The block was therefore compiled for the first time in CI: the reason
the defect is a red job rather than a broken local build is that no local build
ever contained it.

**The zip one is the more instructive defect, because the check that failed was
doing its job.** `data\app.so` and `data\icudtl.dat` were both in the archive.
The verification could not see them and reported them missing. A verification
that is spelled in the vocabulary of the tool that produced the thing shares that
tool's blind spot — which is a different problem from a verification that is
absent, and a harder one to notice.

## Decision

**Zip entry names are normalized where they enter the dictionary, not at each
lookup.** `$entries` is now keyed by `$e.FullName -replace '/', '\'`. The three
call sites keep asking for `data\app.so` — the probe text, the icon font, the
`app.so` hash — and the answer no longer depends on which PowerShell produced the
archive.

**A `.kts` script imports what it uses.** `android/app/build.gradle.kts` opens with
`import java.io.FileInputStream` and `import java.util.Properties`, and the body
uses the short names. A fully-qualified `java.` prefix inside a build script is
not a way to avoid an import; it is a way to be shadowed by a plugin extension
that happens to own that name.

**`scripts/fetch-sources.ps1` carries the same BOM its siblings carry.** All four
scripts under `scripts/` now start with `EF BB BF`, which is what lets a
Chinese-comment script be parsed by both PowerShell editions instead of only by
the one whose code page happens to fit.

**A defect that only CI can see has to be reproduced here, not only fixed.** The
separator defect was reproduced on this machine by building a zip whose entries
carry forward slashes — the exact bytes PowerShell 7 produces — and running both
the old and the new lookup against it. The old logic reports the same two files
CI reported; the new one reports none. That reproduction is the only way this
machine can reach the CI condition, because PowerShell 7 is not installed on it.

## Alternatives considered

**Pin CI to Windows PowerShell 5.1 (`shell: powershell`).** Rejected: it makes a
maintenance-only host the contract. PowerShell 7 is where the language is going,
the workflow would have to decline it permanently, and the green result would
then depend on the older engine not being retired — the same fragility, moved
somewhere harder to see.

**Ask the dictionary for both spellings at each call site.** Rejected: three
lookups that each have to remember, and every future key that would have to
remember too. Normalizing at the one place the dictionary is filled is one place
to get right.

**Delete the zip-content verification, since it is the step that turned the job
red.** Rejected: it is the only check in the project that reads the deliverable
rather than the tree it was built from, and it has already caught two things a
build cannot — probes still looking for a sentence that had been deleted, and an
icon font that stopped being regenerated. A package is what users receive; a
check that opens it is the last honest gate.

**Drop only the `java.` prefix and leave the imports out.** Rejected: `Properties`
and `FileInputStream` are not in a script's default imports, so the failure would
have moved one line down and changed its name to `Unresolved reference
'Properties'`.

**Add a pull-request workflow that runs the packaging script, so this is caught
before a release exists.** Deferred, not rejected: it is the obvious next step and
a larger change than this one. What matters here is that *both* defects still
needed CI to find them, so the release job is not the wrong place to catch this
class — only a late one.

**Bump to `0.1.1` and leave the failed `v0.1.0` tag alone.** Rejected: `v0.1.0` is
the first release this project has ever cut, nothing was published under it, and
[the note that owns the pipeline](2026-10-12-a-tag-builds-the-three-packages.md)
already says what to do in exactly this case. Shipping `0.1.1` as the *first*
release would put a number in front of every user that nobody can account for.

## Consequences

- The zip fix is verified by the local reproduction above; the Kotlin fix is
  verified by Gradle's configuration phase (`gradle --dry-run help` in `android/`),
  which compiles both `.kts` scripts without building an APK. That is exactly the
  error the Android job died on.
- `scripts/fetch-sources.ps1` parses with zero PowerShell AST errors under 5.1,
  down from nine. Nothing had ever run it, so nothing had ever noticed.
- **The gate suite still cannot see this class of defect.** Nothing in `AGENTS.md`
  §5 runs a build script, and this machine has no PowerShell 7 — so a separator or
  an encoding assumption that differs between the two editions is still only
  caught by pushing a tag. This note records the gap rather than closing it.
- **`v0.1.0` is re-pushed onto a `master` tip that contains this fix.** The tag
  moves; the version does not. Anyone who already fetched the failed tag's tree
  gets a different commit for the same tag name — the price of shipping the first
  release under its own number, and acceptable only because nothing was published
  under it.
- The three artifacts remain partly unproven. The portable zip has now been
  assembled and compressed by CI and got as far as the verification that threw;
  the APK has still never compiled successfully; Inno Setup has still never
  compiled `packaging/local_transfer.iss`.

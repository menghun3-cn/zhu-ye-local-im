# Agent Note: A tag builds the three packages

Status: implemented

## Problem

Everything the product could tell a user about a new version pointed at GitHub
Releases, and nothing had ever been published there. The About card's download
button and the rail's update entry — the previous change — both open
`releases/latest`; that page was empty. A build reached another machine only if
somebody ran a PowerShell script on one particular Windows machine and sent the
zip over by hand.

Three specific drifts had grown in that gap.

**The version number had three sources and only two were compared.**
`pubspec.yaml` and `appVersion` are held together by `test/app/app_version_test.dart`,
but `scripts/pack-windows-portable.ps1` carried
`LocalTransfer-1.0.0-windows-x64-portable` as a literal. Nothing compared it to
anything, and a file name is the most visible claim a package makes.

**Release builds were signed with the debug key.** `android/app/build.gradle.kts`
still held Flutter's template line — `signingConfig = signingConfigs.getByName("debug")`
underneath a `TODO`. That is right for `flutter run --release` and wrong for a
published APK, because Android identifies an application by package name *plus*
signing key: every user who installs a debug-signed APK has to uninstall it
before a properly signed build can take its place. Nobody would notice until
users existed.

**There was no installer.** `packaging/` held one readme.

## Decision

**The tag is the trigger, and the only trigger.** `.github/workflows/release.yml`
runs on `push: tags: ['v*']`. Nothing is produced by pressing a button on a
machine, and pushing a branch produces no artifacts. This follows from §2.2 of
`AGENTS.md`, which already says the tag is pushed on `master`'s tip *after* the
`release/vX.Y.Z` pull request is merged — so the tag is the first moment at which
the code and the version number it claims are both final.

**The workflow refuses to build a mislabelled release.** The first job compares
the tag against `pubspec.yaml` and `lib/app/app_version.dart` and fails on any
disagreement. It is the only check in the pipeline that can prevent the failure
described above, and it runs before anything is compiled. `dart test` covers two
of those three; only CI can cover the tag.

**Three artifacts, named from the already-verified version.** Windows installer,
Windows portable zip, Android APK.

**CI calls the same scripts a developer calls**, rather than a hand-written
sequence of `flutter build` steps: the Windows job runs
`scripts/pack-windows-portable.ps1 -Smoke` in full, smoke test included. A
pipeline that builds its own way is a second packaging implementation, and
nothing would verify it.

**The installer is a second format, not a second pipeline.**
`scripts/pack-windows-installer.ps1` will not run unless the portable script has
already assembled `build/dist/LocalTransfer-<version>-windows-x64-portable/`, and
it re-checks that directory for the seven things a package must contain —
`local_transfer.exe`, `flutter_windows.dll`, `data\app.so`, the three VC++
runtime DLLs, and the readme. `packaging/local_transfer.iss` then copies that
directory wholesale. Neither script has its own opinion about what belongs in a
package, so there is no way for the two to disagree.

**Per-user installation.** `PrivilegesRequired=lowest`, installed under
`%LOCALAPPDATA%\Programs\LocalTransfer`, no UAC prompt. This application binds
three sockets and writes one file under `%APPDATA%`; it has no reason to ask for
administrator rights, and asking would only teach users to click through the
prompt. The cost is that the installer cannot add a firewall rule, which does
need elevation — the readme says so and gives the manual command, rather than
letting the installer appear to have handled it.

**Two readmes, because one of them would be lying.** The portable readme opens
with 「不需要安装、不写注册表、想删除就直接删掉整个文件夹」, which is false for
an installed copy. Rather than make one file hedge in both directions, the
installer ships `packaging/安装说明.txt` describing how to install, uninstall and
upgrade in place, and includes the portable readme unchanged for everything about
how the program works.

**A real keystore, and a loud failure when it is absent.**
`android/app/build.gradle.kts` reads `android/key.properties` when it exists and
falls back to the debug key when it does not, so `flutter run --release` keeps
working on any machine. The workflow is what makes that safe: it refuses to start
without all four secrets, and after building it runs `apksigner verify --print-certs`
and fails unless the certificate contains `CN=LocalTransfer`. A missing secret
therefore cannot produce a silently debug-signed release.

**The `.iss` must be UTF-8 with a BOM, and the packaging script enforces it.**
Inno Setup 6 decodes a BOM-less definition file as ANSI, and this machine's code
page is 936 — which can absorb much of simplified Chinese. The result is not an
error but a wizard and a shortcut quietly named gibberish. The script reads the
first three bytes and refuses to compile without `EF BB BF`.

**Version numbers are read, never repeated.** Both packaging scripts derive the
version from `pubspec.yaml`; the hard-coded one in the package name is gone. Four
things still carry a version, and each has exactly one source:

- the package name, and the `.iss`'s `LTVersion` — read from `pubspec.yaml` by the
  two scripts;
- the readme the portable package carries — the pack rewrites its **title line**
  from the same value, and fails outright if the rewritten line does not contain
  it;
- the Windows executable's version resource — `windows/runner/CMakeLists.txt`
  passes Flutter's `FLUTTER_VERSION*` into `Runner.rc`, so the `1.0.0` still
  visible in that file is only the template's `#else` fallback;
- Android's `versionName` and `versionCode`, injected by Flutter from the same
  file.

The readme's title was the one that stayed hardcoded, and only the first real
release could have shown it: the `v0.1.0` package's readme opened with
「竹叶局域网传输 1.0.0」, because the pack rewrote the two lines that change every
build and not the one that changes every release. §9 of `AGENTS.md` states the
policy that goes with all of this — patch digit for ordinary features and fixes,
minor digit only for a deliberate milestone, major untouched before 1.0.0.

## Testing

Verified on the machine this was written on:

- `scripts/pack-windows-installer.ps1` parses with zero PowerShell AST errors, and
  so do the four existing scripts.
- Running it end to end proves the version derivation (`1.0.0` from
  `pubspec.yaml`) and the completeness check (the assembled stage directory from
  a previous packaging run passed all seven items) — and it terminates at the
  missing ISCC with the message that tells you to run `choco install innosetup`.
- `.github/workflows/release.yml` parses with the repository's own `package:yaml`,
  and the resulting structure is the intended one: keys `name, on, permissions,
  jobs`; trigger `{push: {tags: [v*]}}`; jobs `version, windows, android, release`
  with 2/6/8/4 steps and every step having either `uses` or `run`.
- A real PKCS12 keystore was generated with the JDK's `keytool`, and it opens
  with the password it was created with — the certificate it holds is
  `CN=LocalTransfer, OU=Development, O=LocalTransfer, L=Hangzhou, ST=Zhejiang, C=CN`,
  valid for 10000 days.
- Both new Chinese files carry a UTF-8 BOM and the `.iss` is UTF-8 with BOM, and
  the readme matches its sibling's encoding.

**Not verified at the time, and what the first run said.** Inno Setup is not
installed on this machine, so `packaging/local_transfer.iss` still has never been
compiled; `flutter build windows` and `build apk` could not be run here at all
(this machine's Dart could not create child processes for a stretch, so
`flutter`, `dart test` and `flutter analyze` were all unavailable). Everything
above was a static check plus the two error paths of a script, and nothing more.
The first real exercise was the `v0.1.0` release. It passed the version check and
failed in both build jobs — not in the Inno Setup directive set, which was never
reached, but in `android/app/build.gradle.kts` and in the portable script's own
zip verification. `subosito/flutter-action@v2` resolved the pinned `3.47.5`
without complaint, so the other item that paragraph was watching for held. The
two defects and the reasoning behind their fixes are in
[the Agent Note that owns them](../bug-fix/2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md).

## Alternatives considered

**Releasing from a local script, with CI only building.** Rejected: the machine
that produces a release would become part of the release's meaning. Two runs of
the same tag would give different bytes, and "it works on my machine" would
become the release process.

**An MSI (WiX) instead of Inno Setup.** Rejected: better for group-policy
deployment, which this project has no use for, at a considerable cost in
definition complexity. Inno Setup is the common choice for Flutter desktop
applications and installs in one `choco` line.

**A machine-wide install into `Program Files`.** Rejected: it makes every install
and uninstall require elevation, in exchange for nothing this program needs.

**Making the installer build its own copy of the app.** Rejected: two builds of
the same source is two chances for them to differ, and the portable script is
where the verification lives.

**Keeping the debug signing key and documenting it.** Rejected: it is invisible
until the day a user tries to upgrade, and by then the only fix is an uninstall.

**Having CI tag the release (`TAG_MODE=ci`).** Rejected for now, but only
narrowly: `git-publish` supports it, and it would remove the last manual step.
It stays `local` because the tag is the input this workflow's version check is
built to trust, and a workflow that both writes the tag and trusts it would be
checking its own work.

**Pinning the Inno Setup version in CI.** Rejected: `choco install innosetup`
takes the current 6.x, which is what a developer following the readme gets. The
`#define`s and the BOM check are what keep the definition portable.

**Shipping the Chinese Inno Setup translation.** Deferred, not rejected: Inno
Setup ships no official simplified-Chinese messages file, so it would mean
vendoring an unofficial `.isl` of unknown provenance. The wizard chrome is
therefore English while every string belonging to this product is Chinese. Worth
revisiting if the mixture bothers anyone.

## Consequences

**Bought.** A release is one command away from being real: push a tag on
`master` and three packages appear on the Releases page with the changelog entry
as their description. The rail's update entry and the About card now have
somewhere to point.

**The version number is checked before anything is built.** A tag that disagrees
with `pubspec.yaml`, or a `pubspec.yaml` that disagrees with `appVersion`, stops
the release instead of publishing something whose name is wrong.

**`.github/` exists now, and nothing gated it.** There is no pull-request
workflow: the six gates in `AGENTS.md` §5 still run on a developer's machine and
nowhere else. A `gates.yml` running `dart test`, `dart format`, `flutter analyze`
and the two documentation verifiers on every pull request is the obvious next
step, and it is deliberately not in this change.

**The release pipeline's first execution was the `v0.1.0` release, and it failed
there.** The failure was in the pipeline rather than in the product — the version
check passed and both build jobs died in tooling — so the tag was deleted and
re-pushed onto a `master` tip carrying the fixes, which is exactly the case this
paragraph was written for. A tag that moves is a real cost, and it is paid
knowingly: nothing was published under it, so nobody has downloaded anything. The
defects are in
[their own Agent Note](../bug-fix/2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md).

**CI uses whatever Flutter version is pinned in the workflow.** Bumping it is now
a deliberate edit in a second place, not an automatic follow of `stable`. That is
the trade for reproducible release artifacts.

**The keystore cannot be regenerated.** It is the identity of this application on
Android. If it is lost, no future APK can upgrade an installed copy. It lives
outside the repository, and its only other copy must be the GitHub Secrets the
workflow reads.

**A locally built APK is signed with the release key only if `android/key.properties`
exists.** Otherwise the build succeeds and produces a debug-signed package, which
is correct for `flutter run` and wrong to hand anybody. CI is the check for that;
on a developer machine, `apksigner verify --print-certs` is the check, and the
readme says so.

# Agent Note: Bootstrap the Flutter application shell

Status: implemented

English | [中文](2026-09-29-flutter-project-bootstrap.zh.md)

## Problem

The repository is documentation-complete and code-empty. [AGENTS.md](../../../../AGENTS.md)
section 5 requires every change to pass the Agent Note verifier, the translation-pair
verifier, `flutter analyze` with `dart format --set-exit-if-changed .`, and
`flutter test`; section 8 pins the toolchain to the current Flutter stable. But the
repository has no `pubspec.yaml`, no `lib/`, no `test/`, and no platform project
directory — so most of those gates have nothing to run against, and no feature can land.

Neither v1 platform is verified here either. The Windows desktop and Android build
pipelines have only ever been exercised on throwaway probe projects, never on this
repository.

## Decision

The application is generated into the repository root from the current stable toolchain
with `flutter create --org cn.hnasct --project-name local_transfer --platforms=windows,android .`,
and the generated result is then adjusted in six ways.

**Identity.** Dart package `local_transfer`; Android `namespace` and `applicationId`
`cn.hnasct.local_transfer`; Windows runner `local_transfer`.

**Platform scope.** Only `windows/` and `android/` exist, matching
[the v1 scope note](2026-09-29-v1-scope-windows-and-android.md). No other platform
directory is generated, so no build pipeline exists that nothing builds.

**Toolchain pin.** `pubspec.yaml` declares `environment.sdk: ^3.13.4`. `pubspec.lock`
is committed: this is an application, not a published library, so the resolved
dependency versions are part of what ships.

**Dependencies.** Zero third-party packages beyond the SDK — `flutter`,
`cupertino_icons`, and the `flutter_lints` dev dependency that `analysis_options.yaml`
activates. Discovery, Transfer, and clipboard behavior are all still unimplemented.

**Shell instead of demo.** The template's counter demo is removed. `lib/main.dart`
holds `LocalTransferApp` and `HomePage`, which render the product title and an empty
state and nothing else; `test/widget_test.dart` asserts exactly that shell. The gate
goes green on the shell that actually shipped, not on a counter that never will.

**Workspace hygiene.** `.gitignore` ignores `.workbuddy/`, the local agent workspace,
which must never enter the repository.

## Alternatives considered

**Initialise the project inside the first feature change.** Rejected: it would mix two
unrelated failure classes in one review — whether the toolchain can build at all, and
whether the feature is correct — and would leave the gates unusable until that feature
was written.

**Keep the template counter demo until the first real feature.** Rejected: the demo
would become the `flutter test` baseline, so a green gate would mean a counter worked,
not that the product did.

**Hand-write `pubspec.yaml` and the platform projects instead of running `flutter create`.**
Rejected: `windows/runner` and `android/app` are version-specific scaffolds that move
with the toolchain; hand-written copies drift from what the installed Flutter expects,
and the breakage surfaces long after the mistake.

**Name the Dart package `ai_local_im` after the repository.** Rejected:
[CONTEXT.md](../../../../CONTEXT.md) names the product **Local Transfer**. The package
name appears in every import and in build artifacts, so it follows the product, not the
repository.

**Generate every platform now and delete the unused ones later.** Rejected: it creates
four build pipelines — iOS, macOS, Linux, Web — that no gate builds and no one
maintains, and "later" has no owner.

## Consequences

The gate suite becomes executable, which is the point: `flutter analyze`,
`dart format --set-exit-if-changed .`, and `flutter test` now have a target, and the
Windows and Android builds can be run against this repository rather than a probe.

The cost is a large amount of tool-generated surface — 49 files, most of them platform
scaffolding. A Flutter upgrade rewrites many of them, and those diffs are mechanical
noise that still has to be reviewed.

`applicationId` is now `cn.hnasct.local_transfer` and is effectively permanent: an
Android application ID cannot change once the app has been released.

`.metadata` records the Flutter channel and revision that generated the project, so
tooling can tell when a migration is owed.

No platform plugin is present, so the Windows `.plugin_symlinks` constraint — creating
symbolic links needs Developer Mode on the development machine, which is not enabled —
is not yet exercised. The first plugin with a Windows implementation is what will meet
it.

The project begins cold on capability: nothing of Discovery, Transfer, or Clipboard
Mirroring exists, and each still has to choose between `dart:io` and a platform plugin.

## Testing

`flutter test` executes `test/widget_test.dart`, which asserts that the shell renders
its title and empty state. The platform pipelines are verified by running
`flutter build windows --debug` and `flutter build apk --debug` against this repository,
not against a probe project.

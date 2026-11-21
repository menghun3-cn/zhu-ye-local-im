# Agent Note: A Pascal keyword broke the installer script

Status: implemented

English | [中文](2026-11-21-a-pascal-keyword-broke-the-installer-script.zh.md)

## Problem

The v0.1.58 release pipeline failed at the Inno Setup compile step:
`local_transfer.iss:159: Identifier expected`. The Android APK job succeeded;
only the Windows packaging job died, and the Release job was skipped behind it.

Line 159 is the `var` block of `CurStepChanged`, which declared a variable
named `Program`. `program` is a reserved word in Inno Setup's Pascal scripting
language — the same language family as Object Pascal, where it opens the
program block — so the compiler rejected the identifier before it ever looked
at what the variable held. The bug shipped inside the firewall-exception
feature: the installer script had never been compiled on any machine before
that release, because the feature's own gate ran `flutter analyze` and the
Dart suites, neither of which parses `.iss` files.

## Decision

Rename the variable to `AppExe` at both use sites — the declaration feeds
two netsh `add rule` lines, and the first fix renamed only the TCP one, so
the UDP line kept the reserved word and the compiler stopped one line
later. The netsh command lines themselves, the UAC elevation, and the
firewall rules are unchanged: the string literal `program="..."` inside
them is data for `netsh.exe`, not Pascal, and was never the problem.

## Alternatives considered

**Install Inno Setup locally and compile the script as a gate.** Rejected for
this fix: the repository's packaging gate is `pack-windows-installer.ps1`,
which already runs ISCC end-to-end on any machine that has it — the failure
was that CI was the first machine to ever compile the file. The durable answer
to "script changes go ungated" is recorded in the note below, not in adding a
second compile path here.

**Rename to a different identifier (`Exe`, `Target`, `Path`).** Equivalent;
`AppExe` was chosen because it says what the string is — the installed
executable — rather than what it is used for.

## Consequences

- The release pipeline compiles the installer again; the fix ships in the
  version after `v0.1.59` because that tag already pointed at a commit that
  still carried the reserved word on the UDP line, and tags are never moved.
- `.iss` edits remain ungated locally: `flutter analyze`, `dart test`, and
  `flutter test` cannot see them, and the note-format gate does not either.
  The only compile happens in `pack-windows-installer.ps1` / CI. A syntax
  error in this file is therefore only ever caught at packaging time — which
  is exactly where this one was caught, one release late.

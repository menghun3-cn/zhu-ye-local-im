# Agent Note: Upgrade to current Flutter stable before writing any code

Status: implemented

English | [中文](2026-09-29-upgrade-flutter-before-coding.zh.md)

## Problem

The development machine has Flutter 3.29.2 / Dart 3.7.2 installed, while
current stable is 3.47.5 / Dart 3.13.4 — roughly eight months and six minor
versions behind. The packages this product depends on most cannot take their
current versions on Dart 3.7.2:

| Package | Latest | Requires | Newest usable on Dart 3.7.2 |
| --- | --- | --- | --- |
| `nsd` | 5.0.1 | Dart `^3.11.0` | 5.0.0 |
| `bonsoir` | 7.1.5 | Dart `>=3.8.0` | 5.1.11 (2025-02) |
| `flutter_secure_storage` | 11.2.0 | Dart `>=3.8.0` | none |

Discovery and secure key storage are the two areas where platform quirks are
densest, and therefore exactly where an outdated dependency costs the most.
`bonsoir` 5.1.11 would forgo 19 months of upstream fixes.

## Decision

Upgrade the toolchain to current stable **before the first line of product
code**, and treat the upgrade as a prerequisite step rather than part of v1
feature work. It is done and verified — a trivial app builds and runs on both
Windows and Android — before the project skeleton is laid down.

## Alternatives considered

**Stay on 3.29.2 and pin old packages.** Zero migration cost today. Rejected:
incurs permanent dependency debt at the start of the project, on the two
packages most likely to need upstream fixes, and forfeits Dart 3.8+ language
features.

**Upgrade later, once product code exists.** Rejected: the same migration then
becomes a toolchain migration *plus* a dependency audit across a mature
codebase, with real code to break.

## Consequences

- The Android SDK, build tooling, and any IDE configuration must be
  re-validated after the upgrade, since the path crosses six minor versions.
- Until the upgrade completes, no dependency decisions can be finalised and no
  product code should be written against the old SDK constraints.
- The dependency baseline recorded in `docs/dart-dependency-baseline.md`
  assumes the upgraded toolchain; it is invalid on 3.29.2.

# Agent Note: The changelog gate needed its history backfilled

Status: implemented

English | [中文](2026-11-06-changelog-gate-backfill.zh.md)

## Problem

`dart test` failed in `test/process/changelog_entries_test.dart` on seven
counts. Three release tags — `v0.1.30`, `v0.1.31`, `v0.1.32` — had no
`CHANGELOG.md` entry at all, so their GitHub Release bodies and in-app update
notes were empty. Six released versions also had user-visible commits that no
bullet mentioned: the English commit subjects produced only English
fragments, while the authored bullets are Chinese prose, and the test's
`translated` word map did not cover the recurring feature words involved
(`download`, `presence`, `secret`, `image`, `low-frequency`). Two `docs:`
commits in `v0.1.27` were genuinely absent from the entry.

## Decision

Backfill, do not weaken:

- Added the missing `0.1.30`, `0.1.31`, and `0.1.32` entries dated
  2026-11-03, written from the commits each tag actually contains. `0.1.32`
  carried only the release chore, so its entry says so explicitly.
- Added the two missing `0.1.27` bullets: the AGENTS.md safety-rules doc
  change (the existing bullet now names the file so the `agents` fragment
  matches) and the site download area's removed Android trial label.
- Extended the `translated` map in `changelog_entries_test.dart` with the
  recurring feature words that were missing. The map is the designed
  extension point for exactly this gap; adding fragments can only turn a
  false negative into a pass, never the reverse.

## Alternatives considered

**Rewrite the failing entries wholesale.** Rejected: the entries are what
those releases published, and the test's own doctrine is that a release note
rewritten after the fact no longer says what was announced. The fix touches
only what was actually missing.

**Drop the versions or commits from the check.** Rejected: an exemption list
is how the gate rots. The tags exist and shipped; the entries must too.

**Require English fragments in Chinese bullets.** Rejected: it would make
every future English-subject commit fail until someone edits prose to satisfy
a matcher. The translation map exists precisely so authored Chinese notes
can refer to English-named features.

## Consequences

`dart test` is green again on `develop`-line history. The translation map is
now the place to look when a new recurring feature name starts producing
false "unmentioned commit" failures — extend it there rather than editing
published bullets to satisfy the matcher.

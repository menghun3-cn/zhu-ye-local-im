# Agent Note: The changelog matcher knows gesture and address wording

Status: implemented

English | [中文](2026-10-27-changelog-matcher-knows-gesture-and-address.zh.md)

## Problem

The release-note gate incorrectly reported two `v0.1.21` commits as missing
from their changelog entry. Both bullets were present in Chinese, but the
matcher only knew translations for recurring discovery words such as
`device`, `discover`, and `connect`. It therefore could not connect
`long-press` to `长按` or `address` to `地址`, and failed an already-published
entry for wording it had in fact described.

## Decision

The matcher's bilingual vocabulary now maps `long-press` to `长按` and
`address` to `地址`. A commit subject needs only one translated fragment to
match an authored bullet, so these additions repair both false negatives
without changing the `v0.1.21` release notes or weakening the gate to
substring matching over every English word.

The mapping stays deliberately feature-specific. Broad translations such as
`conversation` would match many unrelated bullets and turn the check into a
test that almost always passes.

## Testing

Two regression cases in `test/process/changelog_entries_test.dart` pair the
English commit subjects with the Chinese bullets shipped in `v0.1.21`. The
full changelog test now checks every guarded release, including `0.1.21`,
without altering historical entries.

## Alternatives considered

**Rewrite the `v0.1.21` changelog bullets to contain English words.** Rejected:
those entries are already published release notes, and their Chinese prose is
the user-facing history rather than a fixture for the matcher.

**Treat any commit with Chinese text anywhere in the release entry as
mentioned.** Rejected: that would stop detecting omitted changes as soon as a
release had any shared vocabulary.

**Map broad words such as `conversation` and `composer` as well.** Rejected:
those appear throughout the changelog and would produce false matches in
future releases. The two missing terms are enough to identify these commits
without making the gate less useful.

## Consequences

- The existing `v0.1.21` entry passes without being rewritten.
- Future long-press and address changes can be matched against Chinese notes.
- The matcher still requires a distinctive translated fragment rather than
  accepting any mention of the release.

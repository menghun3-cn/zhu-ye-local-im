# Agent Note: Changelog bullets carry their commit fingerprints

Status: proposed

English | [中文](2026-11-27-changelog-bullets-carry-commit-fingerprints.zh.md)

## Problem

The changelog completeness gate added after the emoji release shipped
unannounced
([that note](../implemented/bug-fix/2026-10-20-the-changelog-that-did-not-mention-emoji.md))
verifies coverage by guessing: it extracts distinguishing fragments from an
English commit subject and looks for them in the Chinese bullet. That guess
is unsound in both directions. It false-positives whenever a recurring
English word lacks a `translated` entry — `remark`, `dialog`, `wrap` all
failed released entries that did mention the change, most recently
`v0.1.63`/`v0.1.64`. And it false-negatives whenever a bullet happens to
contain a mapped common word: any entry mentioning 「设备」 "covers" every
commit whose fragments include `device → 设备`, so a genuinely omitted
commit can pass. The map is a manual patch that grows one word at a time
(see
[the backfill](../implemented/process/2026-11-06-changelog-gate-backfill.md)
and
[the matcher note](../implemented/testing/2026-10-27-changelog-matcher-knows-gesture-and-address.md)),
and it can never be complete.

The timing is wrong too. Entries are authored at release time, so an
omission is only discovered by `dart test` after the version exists — the
gate audits history rather than guarding the release. And the matcher's
prose heuristics exist at all only because the commit↔bullet link was
never recorded as data.

## Proposal

Make the link data. Every bullet of a fingerprinted version entry carries
the commits it covers as an HTML comment at the end of the line:

```markdown
- 可以给已发现的设备设置本地备注名 <!-- @c2bb4be -->
- 修复「修改备注」弹窗的说明文字被截断 <!-- @db2ed9b -->
```

A bullet covering several commits lists them in one comment:
`<!-- @c2bb4be @db2ed9b -->`. The comment is invisible wherever the entry is
rendered — the GitHub Release body and the in-app update panel — and
parseable by the gate.

**Generation owns the fingerprints; humans own only the prose.** The
`git-publish` changelog step emits the entry as structured bullets: it
consumes the full user-visible commit list of the range, assigns each
commit to a bullet (one-to-one by default; merging bullets concatenates
their fingerprint sets), and writes the comments itself. Every
user-visible commit appears in exactly one bullet's fingerprint set —
coverage is a property of generation, not of anyone remembering.

**Verification becomes exact, in two places:**

- *Pre-tag:* the release flow checks, before the tag is pushed, that the
  fingerprint set of the pending entry equals the user-visible commits
  since the previous tag — the same commit-set computation the test uses.
  A miss names the exact hashes and the release stops while fixing is
  still free.
- *Post-release:* `changelog_entries_test.dart` verifies every version
  from `exactFrom` (the first release cut under this scheme, expected
  `0.1.65`) by set equality between parsed fingerprints and the range's
  commits. Versions before `exactFrom` keep the existing fragment matcher
  unchanged — published history is frozen, exactly as `guardedFrom`
  froze pre-`0.1.8` entries.

The `translated` map, `distinguishingFragments`, and
`commonChinesePairs` become legacy-only machinery serving frozen history;
they are not extended for new words.

The human confirmation step in `git-publish` is unchanged in kind: it
reviews prose. Fingerprints are tool-owned — an edit that drops or
alters one fails the format gate and the test.

## Alternatives considered

**A `Changelog:` trailer on each commit.** Rejected: it makes every
commit body carry release-note prose — the user-facing changelog sentence
lives in `git log` forever, in a second language, for a document that is
authored once per release. The commit message is the wrong place for it.

**towncrier-style fragment files under `changelog.d/`.** Rejected: clean
commits and exact linkage, but every user-visible PR grows a file whose
only content is one sentence, and coverage enforcement moves to the PR
layer where the local `dart test` gate cannot see it.

**Accumulate bullets under `[Unreleased]`.** Rejected: every PR edits the
same region of `CHANGELOG.md`; parallel worktree development makes the
conflicts routine, and the file becomes a merge hotspot.

**magpie's approach: no persisted changelog, LLM-generates notes at
release.** Rejected for this repository: the entry must live in
`CHANGELOG.md` because it feeds the GitHub Release body, the in-app
update panel, and the version history — it cannot be an ephemeral view
over commit subjects. (Its lesson is still borrowed: generation may
degrade to a plain commit list rather than block a release.)

**Keep the fragment matcher and grow the `translated` map.** Rejected:
that is the status quo that produced today's false positives, and the
map can never be complete — every new English feature word is a new
chance to fail a correct entry or pass an incomplete one.

**Full LLM authoring of bullets at release time.** Deferred, not
rejected: with fingerprints the prose could later be generated and the
human step reduced to review — the same shape magpie uses — but that is
a separate decision about who writes sentences, not about how coverage
is verified.

## Acceptance criteria

- A version entry generated under the scheme has every user-visible
  commit of its range fingerprinted exactly once; the pre-tag check
  passes before the tag exists.
- `dart test` verifies fingerprinted versions by exact set equality and
  leaves pre-`exactFrom` versions on the existing matcher.
- The format gate rejects a fingerprinted-version bullet with no
  fingerprint, a malformed one, or a duplicated hash.
- Rendering checks confirm the comments stay invisible in the GitHub
  Release body and the in-app update panel.

## Risks

- **A human edit strips or edits a fingerprint.** Caught by the format
  gate and the test; the remedy is to restore the tool-written comment,
  not to re-derive it.
- **Multi-commit bullets make hash bookkeeping manual.** Merging bullets
  concatenates fingerprint sets; splitting one requires splitting them.
  The generator's default one-to-one mapping keeps this rare.
- **A consumer renders `CHANGELOG.md` without stripping HTML comments.**
  Verified during implementation; if the About panel shows raw text, the
  fingerprint syntax moves to a form that renderer also hides.
- **The pre-tag check needs the pending entry identifiable.** It reads
  the entry the release step just wrote; a release that bypasses
  `git-publish` gets no check — the same exemption every release-time
  gate already has.

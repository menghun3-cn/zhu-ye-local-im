# Agent Note: Changelog bullets carry their commit fingerprints

Status: proposed

English | [中文](2026-11-27-changelog-bullets-carry-commit-fingerprints.zh.md)

## Problem

The changelog completeness gate added after the emoji release shipped
unannounced
([that note](../../implemented/bug-fix/2026-10-20-the-changelog-that-did-not-mention-emoji.md))
verifies coverage by guessing: it extracts distinguishing fragments from an
English commit subject and looks for them in the Chinese bullet. That guess
is unsound in both directions. It false-positives whenever a recurring
English word lacks a `translated` entry — `remark`, `dialog`, `wrap` all
failed released entries that did mention the change, and `dart test` is
red on exactly those two versions today. And it false-negatives whenever a
bullet happens to contain a mapped common word: any entry mentioning 「设备」
"covers" every commit whose fragments include `device → 设备`, so a
genuinely omitted commit can pass. The map is a manual patch that grows one
word at a time (see
[the backfill](../../implemented/process/2026-11-06-changelog-gate-backfill.md)
and
[the matcher note](../../implemented/testing/2026-10-27-changelog-matcher-knows-gesture-and-address.md)),
and it can never be complete.

The timing is wrong too. Entries are authored at release time, so an
omission is only discovered by `dart test` after the version exists — the
gate audits history rather than guarding the release. And the matcher's
prose heuristics exist at all only because the commit↔bullet link was
never recorded as data.

## Proposal

Make the link data. In every fingerprinted version entry, each bullet's
fingerprint is an HTML comment on **its own line, as the last line of the
bullet block** — after the `- ` line and every wrapped continuation line,
before the next bullet, heading, or blank line:

```markdown
- 可以给已发现的设备设置本地备注名，方便区分多台设备
  <!-- @c2bb4be -->
- 修复「修改备注」弹窗的说明文字被截断
  <!-- @db2ed9b -->
```

The fingerprint line is indented like the bullet's continuation lines so it
stays inside the list item when the entry is rendered as markdown. A bullet
covering several commits lists them space-separated in one comment:
`<!-- @c2bb4be @39bd4f1 -->`. Each `@` token is the commit's abbreviated
hash (`git rev-parse --short` form, a unique prefix).

**The own-line placement is load-bearing, not cosmetic.** The in-app update
panel parses release notes with `readUpdateNotes`
(`lib/ui/update_notes.dart`): it strips whole-line `<!--` comments but does
not strip inline ones, and already-shipped clients run the same parser —
a fingerprint trailing a bullet's text would be drawn verbatim on old
clients while new ones hide it. A comment on its own last line is skipped
by that parser unchanged, so the syntax needs no app change and no client
version skew. For the same reason the fingerprint must be the block's
*last* line: the parser resumes a wrapped bullet only across indented
continuation lines, so a comment line placed before them would orphan the
rest of the sentence.

**Generation owns the fingerprints; humans own only the prose.** The
`git-publish` changelog step emits the entry as structured bullets: it
consumes the full commit set of the range, assigns each commit to a bullet
(one-to-one by default; merging bullets concatenates their fingerprint
sets), and writes the comment lines itself. Every commit in the set
appears in exactly one bullet's fingerprint set — coverage is a property
of generation, not of anyone remembering.

**The commit set is defined once, in Dart.** "User-visible commits of the
range" is not a one-line predicate: it is the three filters
`releaseCommits` already applies — the `prevTag..tag` log range on the
production topology, the `isUserVisible` prefix filter (`feat`, `fix`,
`refactor`, `perf`, `docs`, including `!`), and `changedSomethingNew`, the
tree-diff against the previous tag that drops commits the earlier release
already shipped under a different id (excluding `CHANGELOG.md`). The
pre-tag check and the post-release test must share this one implementation
— the check is a Dart entry point exercised by `dart test`, not a second
port in PowerShell or Python that can drift.

**Failures are loud, never silent.** Where the legacy matcher returned
`true` on a git error (`changedSomethingNew`'s `exitCode != 0` fallbacks),
the exact path treats an unanswerable question as a failure: a range that
cannot be computed, a commit whose files cannot be diffed, or a fingerprint
that does not resolve to a commit in the range fails the gate. No retries,
no "assume covered".

**Verification becomes exact, in two places:**

- *Pre-tag:* `pre-publish-check.ps1` gains a step that runs the shared
  Dart check against the pending entry before the tag is pushed: the
  fingerprint set of the entry being released must equal the commit set
  `prevTag..HEAD` produces on the release branch. A miss names the exact
  hashes and the release stops while fixing is still free. This is a new
  invocation inside the existing script — `dart test` itself is not added
  to it.
- *Post-release:* `changelog_entries_test.dart` verifies every version
  from `exactFrom` by set equality between parsed fingerprints and the
  range's commit set.

**Migration: `exactFrom` is `0.1.63`, not the next release.** The two
versions whose entries provably mention their commits — `v0.1.63`
(`c2bb4be` 备注名, `39bd4f1` 官网描述) and `v0.1.64` (`db2ed9b` 备注弹窗)
are a verified one-to-one mapping — get their fingerprints backfilled as
tool-written invisible metadata. Published prose is untouched; a comment
line is not a rewrite of what was announced. With both backfilled,
`dart test` goes green on the day the scheme lands instead of carrying a
permanently red gate, and every version from `0.1.63` on is held to exact
set equality. Versions before `0.1.63` keep the existing fragment matcher
unchanged — same freeze `guardedFrom` applied to pre-`0.1.8` entries.

The `translated` map, `distinguishingFragments`, and
`commonChinesePairs` become legacy-only machinery serving frozen history;
they are not extended for new words.

The human confirmation step in `git-publish` is unchanged in kind: it
reviews prose. Fingerprints are tool-owned — an edit that drops or alters
one fails the format gate and the test.

## Alternatives considered

**A `Changelog:` trailer on each commit.** Rejected: it makes every
commit body carry release-note prose — the user-facing changelog sentence
lives in `git log` forever, in a second language, for a document that is
authored once per release. The commit message is the wrong place for it.

**towncrier-style fragment files under `changelog.d/`.** Rejected: clean
commits and exact linkage, but every user-visible PR grows a file whose
only content is one sentence, and coverage enforcement moves to the PR
layer where the local `dart test` gate cannot see it.

**A sidecar fingerprint manifest** (e.g. `CHANGELOG.fingerprints` mapping
version → hashes). Rejected: the link lives in a second file that must be
kept in sync with the entry it describes, every consumer of the entry
alone loses the association, and a merge conflict in the manifest is
exactly as likely as one in the entry — without the entry carrying its own
proof.

**Fingerprint only from the next release (`exactFrom = 0.1.65`) and leave
`0.1.63`/`0.1.64` on the legacy matcher.** Rejected: the legacy matcher is
what is failing today, and the test reads all history — those versions
never scroll out, so the gate would stay red forever. The only cost of
backfilling is invisible comment lines on the three affected bullets whose
commit↔bullet mapping is already verified one-to-one.

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

- A version entry generated under the scheme has every commit of its
  range fingerprinted exactly once; each fingerprint is an own-line,
  block-final HTML comment matching `^\s*<!--\s*@[0-9a-f]+(\s+@[0-9a-f]+)*\s*-->\s*$`.
- The commit-set predicate has exactly one implementation, shared by the
  pre-tag check and `dart test`; both compute it identically.
- `pre-publish-check.ps1` invokes the pre-tag fingerprint check; the
  check fails on unanswerable git queries, not only on mismatched sets.
- `dart test` verifies versions `>= 0.1.63` by exact set equality —
  `0.1.63`/`0.1.64` included via backfilled fingerprints — and leaves
  earlier versions on the existing matcher; the suite is green.
- The format gate rejects, for fingerprinted versions: a bullet with no
  fingerprint, a fingerprint line that is not block-final, a malformed
  fingerprint, a duplicated hash, and a hash that is not a commit of the
  version's range.
- Rendering is verified against `readUpdateNotes`: own-line comments are
  skipped by the parser as shipped, so no client change is needed; the
  check is re-run at implementation time rather than assumed.

## Risks

- **A human edit strips or edits a fingerprint, or inserts one mid-block.**
  Caught by the format gate and the test; the remedy is to restore the
  tool-written comment, not to re-derive it.
- **Multi-commit bullets make hash bookkeeping manual.** Merging bullets
  concatenates fingerprint sets; splitting one requires splitting them.
  The generator's default one-to-one mapping keeps this rare.
- **The own-line rule interacts with hand-wrapping.** Continuation lines
  are indented; the fingerprint line uses the same indent and must come
  after all of them. The format gate enforces block-final position so a
  mid-block comment cannot orphan wrapped prose in `readUpdateNotes`.
- **Backfilled fingerprints edit published entries.** They are invisible
  metadata, not prose; if a future consumer renders raw `CHANGELOG.md`
  without stripping HTML comments the same own-line syntax is what it
  must learn to skip — the format is already the one `readUpdateNotes`
  drops.
- **The pre-tag check needs the pending entry identifiable.** It reads
  the entry the release step just wrote; a release that bypasses
  `git-publish` gets no check — the same exemption every release-time
  gate already has.

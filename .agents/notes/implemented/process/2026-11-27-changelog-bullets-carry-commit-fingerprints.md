# Agent Note: Changelog bullets carry their commit fingerprints

Status: implemented

English | [中文](2026-11-27-changelog-bullets-carry-commit-fingerprints.zh.md)

## Problem

The changelog completeness gate added after the emoji release shipped
unannounced
([that note](../../implemented/bug-fix/2026-10-20-the-changelog-that-did-not-mention-emoji.md))
verified coverage by guessing: it extracted distinguishing fragments from an
English commit subject and looked for them in the Chinese bullet. That guess
was unsound in both directions. It false-positived whenever a recurring
English word lacked a `translated` entry — `remark`, `dialog`, `wrap` all
failed released entries that did mention the change, and `dart test` was
red on exactly those two versions. And it false-negatived whenever a bullet
happened to contain a mapped common word: any entry mentioning 「设备」
"covered" every commit whose fragments included `device → 设备`, so a
genuinely omitted commit could pass. The map was a manual patch that grew
one word at a time (see
[the backfill](../../implemented/process/2026-11-06-changelog-gate-backfill.md)
and
[the matcher note](../../implemented/testing/2026-10-27-changelog-matcher-knows-gesture-and-address.md)),
and it could never be complete.

The timing was wrong too. Entries were authored at release time, so an
omission was only discovered by `dart test` after the version existed — the
gate audited history rather than guarding the release. And the matcher's
prose heuristics existed at all only because the commit↔bullet link was
never recorded as data.

## Decision

The link is data. In every fingerprinted version entry (`exactFrom` =
`0.1.63`), each bullet's fingerprint is an HTML comment on **its own line,
as the last line of the bullet block** — after the `- ` line and every
wrapped continuation line, before the next bullet, heading, or blank line:

```markdown
- 可以给已发现的设备设置本地备注名，方便区分多台设备
  <!-- @c2bb4be -->
```

The fingerprint line is indented like the bullet's continuation lines so it
stays inside the list item when the entry renders as markdown. A bullet
covering several commits lists them space-separated in one comment:
`<!-- @c2bb4be @39bd4f1 -->`. Each `@` token is the commit's abbreviated
hash, matched as a unique prefix of the full hash.

**The own-line placement is load-bearing.** The in-app update panel parses
release notes with `readUpdateNotes` (`lib/ui/update_notes.dart`): it skips
whole-line `<!--` comments but does not strip inline ones, and already-shipped
clients run the same parser — a fingerprint trailing a bullet's text would
be drawn verbatim on old clients. A comment on its own last line is skipped
by that parser unchanged, so the syntax needed no app change and no client
version skew. For the same reason the fingerprint must be the block's
*last* line: the parser resumes a wrapped bullet only across indented
continuation lines, so a comment placed before them would orphan the rest
of the sentence.

**Generation owns the fingerprints; humans own only the prose.** The
`git-publish` changelog step emits the entry as structured bullets: it
consumes the commit set printed by
`dart run test/process/changelog_fingerprint_check.dart --commits`, assigns
each commit to a bullet (one-to-one by default; merging bullets concatenates
their `@` tokens into one comment line), and writes the comment lines
itself. Every commit in the set appears in exactly one bullet's fingerprint
set — coverage is a property of generation, not of anyone remembering.

**The commit set has exactly one implementation, in Dart.** "User-visible
commits of the range" is three filters, not a one-line predicate: the
`prevTag..tag` log range on the production topology, the `isUserVisible`
prefix filter (`feat`, `fix`, `refactor`, `perf`, `docs`, including `!`),
and `changedSomethingNew`, the tree-diff against the previous tag that drops
commits the earlier release already shipped under a different id (excluding
`CHANGELOG.md`). All of it lives in `test/process/changelog_commits.dart`,
shared by the post-release test and the pre-tag check — no second port in
PowerShell or Python that could drift. Git failures are loud: where the
legacy matcher returned `true` on a git error, the shared predicate throws,
so an unanswerable question fails the gate. There are no retries and no
assume-covered fallback.

**Verification is exact, in two places:**

- *Pre-tag:* `dart run test/process/changelog_fingerprint_check.dart`
  compares the pending entry's resolved fingerprint set against
  `prevTag..HEAD` on the release branch and names missing and unexpected
  hashes. `pre-publish-check.ps1` and `pre-publish-check.example.sh` invoke
  it when the script exists, so the check also runs as a pre-publish gate.
- *Post-release:* `changelog_entries_test.dart` verifies every version from
  `exactFrom` (`0.1.63`) by set equality between parsed fingerprints and the
  range's commit set, including duplicate-claim detection that set equality
  alone cannot see. Versions before `exactFrom` keep the legacy fragment
  matcher unchanged.

**Migration: `exactFrom` is `0.1.63`, and `0.1.63`/`0.1.64` are
backfilled.** Those two entries' commit↔bullet mapping was verified
one-to-one, so their fingerprints were written as tool-owned invisible
metadata — published prose untouched, a comment line is not a rewrite of
what was announced. With both backfilled, `dart test` went green on the day
the scheme landed instead of carrying a permanently red gate. The
`translated` map, `distinguishingFragments`, and `commonChinesePairs` are
legacy-only machinery serving frozen history; they are not extended for new
words.

**Format enforcement is split by what each gate can see.**
`changelog_check.py` validates fingerprint *syntax* on the pending entry —
own-line block-final position, the `<!-- @hash… -->` shape, no duplicate
token in the entry — for versions at or above `--fingerprint-from`
(`0.1.63`). Set equality, hash-to-commit resolution, and duplicate claims
across bullets belong to the Dart side, which owns the commit predicate.

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
what was failing, and the test reads all history — those versions never
scroll out, so the gate would have stayed red forever. The cost of
backfilling was invisible comment lines on the three affected bullets whose
commit↔bullet mapping was already verified one-to-one.

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
that was the status quo that produced the false positives, and the map
could never be complete — every new English feature word was a new chance
to fail a correct entry or pass an incomplete one.

**Full LLM authoring of bullets at release time.** Deferred, not rejected:
with fingerprints the prose could later be generated and the human step
reduced to review — the same shape magpie uses — but that is a separate
decision about who writes sentences, not about how coverage is verified.

## Consequences

What the scheme buys: coverage is a property of generation — the commit set
is enumerated by `--commits`, every commit lands in exactly one fingerprint
set, and both gates compare sets rather than guess at prose. The pre-tag
check names offending hashes while the release is still un-pushed, and
`dart test` is exact and green. The fingerprint lines are invisible in the
GitHub Release body and the in-app update panel: `readUpdateNotes` skips
whole-line comments as shipped, verified against the parser rather than
assumed.

What it costs: every user-visible release now has a mechanical step — the
draft must carry correct fingerprints or both gates fail; `git-publish`'s
step 3 was rewritten to make the tool the fingerprint's author and the human
the prose's. The commit-set predicate is three git queries per commit, so
the post-release test's runtime is dominated by `changedSomethingNew`'s
per-commit diffs — the same cost the legacy matcher already paid. The
legacy matcher and its `translated` map remain in the tree serving frozen
history, a deliberate duplication kept until the pre-`0.1.63` entries are
themselves considered closed.

What pins the behavior: `test/process/changelog_entries_test.dart` (exact
set equality for `>= 0.1.63`, parser unit tests, legacy matcher below),
`test/process/changelog_fingerprint_check.dart` (`--commits` listing and
the pre-tag comparison), `changelog_check.py`'s `--fingerprint-from`
syntax rules, and the `pre-publish-check` scripts' invocation of the Dart
check.

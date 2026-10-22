# Agent Note: The changelog that did not mention emoji

Status: implemented

English | [中文](2026-10-20-the-changelog-that-did-not-mention-emoji.zh.md)

## Problem

The emoji feature shipped. It was merged, released, and installed by users —
and it was never announced.

`feat: 会话支持发送表情，表情按钮旁附最近使用与全部表情` is the subject of
commit `7eb9ecf`, merged into `develop` by PR #104 and carried by tag
`v0.1.10`. It is in the code of every build since. But the `CHANGELOG.md`
entry for `v0.1.10` lists the draggable divider and the bubble-width fix, and
does not mention emoji. The entry for `v0.1.11` — the first release that was
actually published, and therefore the first release whose notes any user could
read — does not mention it either.

That matters because the changelog is not a document that sits in the
repository. `release.yml` takes the version's `CHANGELOG.md` section and
publishes it as the GitHub Release body, and the About card reads the same
body to show what a newer version changes. The changelog *is* the release
notes and the in-app update panel. A feature that is missing from it is a
feature the user is never told about, on the one screen that exists to tell
them.

The gap was not a matter of taste about wording. The commit was in the range
the release was generated from:

```console
$ git log v0.1.9..v0.1.10 --oneline
a5f9ae1 Merge pull request #106 from menghun3-cn/release/v0.1.10
d664b8a chore(release): 0.1.10
8729602 Merge pull request #105 from menghun3-cn/feat/message-bubble-width
edfe596 refactor: 会话列的最小宽度改为推出来的，两栏宽度改为量出来的
d683bc5 feat: 会话列表与会话之间加分隔条，可拖动调整两栏比例
abb215f fix: 消息气泡宽度上限此前从未生效，长消息会横穿整个会话
b1cf41b Merge pull request #104 from menghun3-cn/feat/send-emoji
7eb9ecf feat: 会话支持发送表情，表情按钮旁附最近使用与全部表情
```

The emoji commit is right there in the list, and the entry that was written
from it does not mention it.

**How that is possible.** The changelog for a release is written by hand, at
release time, by whoever is releasing. The `git-publish` skill asks for a
draft and shows it for confirmation, and the format gate
(`changelog_check.py`) checks that the entry is *well-formed* — a title with a
version and a date, categories from the allowed set, at least one bullet
under each. Every one of those checks is about the shape of the entry and none
of them is about its **content**: nothing asks whether a commit in the range
is represented.

So a `feat:` commit can simply be left out, and nothing fails. The release
goes out, the notes go out, and the feature is invisible.

This is the same defect class as the one recorded in
[the probe that survived two rewrites](../bug-fix/2026-10-20-the-probe-that-survived-two-rewrites.md):
a step that a human has to remember, living in a different place from the
thing it is about, whose only failure mode is silence. That note fixed it for
the packaging probe by making the list self-maintaining and the judgement
machine-checked. The same treatment belongs here.

## Decision

**The changelog gets a completeness check, and it runs in the gate that always
runs.** `test/process/changelog_entries_test.dart` reads `CHANGELOG.md` and the
git history, and fails when a release entry does not account for a commit in
its range.

The check works on the **subject line** of the commit, because that is what
the changelog entry is derived from. Every commit in a version's range whose
subject carries a `feat:`, `fix:`, `refactor:`, `perf:` or `docs:` prefix
must be accounted for by some bullet under that version's entry. The
commit's own subject is the token the bullet has to mention — the check
looks for a distinguishing fragment of it in the bullet text.

`chore:`, `test:` and `ci:` commits are infrastructure and are excluded, which
matches the classification rules in the `git-publish` skill itself.

**A version's range is what it *changed*, not what its history contains.**
The release tags do not sit on one line: a release tag points at the merge
commit on the production branch, and that commit brings the integration
branch's work in under *new* commit ids. So `v0.1.12..v0.1.13` lists changes
`v0.1.12` already shipped, and the integration branch's commits are not even
ancestors of the earlier tag. The check therefore asks each candidate
commit a question about the **tree**: does the previous release's tree
already have what this commit changed? A commit that changed nothing the
previous release did not have is a change that release already announced,
and it is not asked about again.

**The changelog itself is excluded from that question.** The changelog is
what a release *produces*, not what it carries: it differs between every
two releases by definition, and it says nothing about what the release
contains. Counting it would make every commit that touched the changelog
look like a new change.

**The rule holds from `v0.1.8` onwards.** The entries before it were
written when a version's notes were a summary rather than a list, and
rewriting history is not what a test is for: those entries are what those
releases published, and a release note rewritten after the fact is a
release note that no longer says what was announced. The entries from
`v0.1.8` on were written as lists, and those are the ones this check holds
to.

**The check names what it expected.** A failure says which version's entry is
short and which commit is missing, rather than only that "the changelog is
wrong". A gate that cannot name the omission leaves the reader to find it.

**The missing entries are added.** The emoji feature first shipped in
`v0.1.10`, and `v0.1.11` is the first release that was actually published;
both entries carry the bullet, because both describe a build that contains
the feature — and because `v0.1.10` is the tag whose release never appeared,
so its notes are the record of what that tag was supposed to ship.

The check found one more omission while it was being put in place: `v0.1.13`
left out the README change and the screenshot-script fix that shipped with
it. Its entry now carries both, and the published release body was updated
to match — a note that says one thing in the repository and another on the
release page is the same defect this check exists to prevent, one level up.

**A shipped feature is also announced from its own Agent Note.** The note for
the emoji feature records the decision and its alternatives; it says nothing
about the changelog, because the changelog is written at release time by a
different step. The gate is what makes the two meet.

## Alternatives considered

**Trust the confirmation prompt in the `git-publish` skill.** Rejected: the
prompt asks a human to check a list of commits against a list of bullets,
which is exactly the comparison that already failed. A prompt can be
forgotten, skipped, or read quickly; a test cannot.

**Generate the changelog from the commits.** Rejected: the changelog is
written in Chinese prose that a person authored — "消息气泡的宽度上限此前从未
生效" is not a mechanical transformation of "fix: 消息气泡宽度上限此前从未生效".
Generating it would replace the authored sentences with commit subjects, which
would be a worse release note for the reader. The check keeps the authorship
and verifies the coverage.

**Check that every `feat:` has an Agent Note instead.** Rejected: that is a
different property, and it would not have caught this. The emoji feature
*did* have a complete Agent Note triplet; the changelog still left it out.

**Only check the newest version.** Rejected: `v0.1.10` shipped without the
feature in its notes too, and its tag is still on `master` naming a release
that never appeared. A gate that only looks forward leaves the existing
record wrong. The rule is bounded at the other end instead — it starts at
`v0.1.8`, where the entries began being written as lists.

**Ask the history rather than the tree.** Rejected, and it was tried first:
the natural question is "is this commit an ancestor of the previous
release's tag", and the answer is no for every commit on the integration
branch — the production branch merges that work in under new ids. A history
that answers "no" to work the previous release demonstrably shipped makes
the check count the same work twice and fail every release. The tree
answers the question that is actually being asked.

**Put the check in `changelog_check.py` instead of `dart test`.** Rejected on
one ground and one only: `changelog_check.py` is a template in the
`git-publish` skill, shared across repositories and written in Python, while
this repository's own gate is `dart test` — the one that runs on every
developer machine without a Python toolchain. The check needs git history,
which the skill's script has no reason to know about, and this repository's
test gate is the one that already guards everything else about the release
process.

## Consequences

- **A feature cannot ship unannounced without a red gate.** The next release
  that leaves a `feat:` out of its entry fails `dart test`.
- **The check reads git history, so it needs a repository.** It skips itself
  when the history is not available (a source tarball, a shallow clone) rather
  than failing on a technicality — the gate for that case is the release
  itself, which always runs in the full repository.
- **The emoji bullet now appears under `v0.1.10` and `v0.1.11`.** The
  published `v0.1.11` release body is fixed on GitHub by editing the
  release, since the notes were already published without it.
- **The `v0.1.13` entry gained the two bullets it was missing**, and its
  published release body was edited to match.
- **The same class of omission is now caught for every future feature.** The
  periodic-update feature had the same gap in `v0.1.9` and is covered by
  the same check.
- **Entries before `v0.1.8` are left as they were published.** The check
  does not ask for them to be rewritten, because a release note that is
  rewritten after the fact is a release note that no longer says what was
  announced.

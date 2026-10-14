# Agent Note: What a newer version says it changes

Status: implemented

English | [中文](2026-10-13-what-a-newer-version-says-it-changes.zh.md)

## Problem

The About card could say *that* a newer build exists — 「有新版本 v0.1.2。」 — and
nothing about what is in it. The release's own notes were in hand the whole
time: `release.yml` publishes the version's `CHANGELOG.md` section as the release
body, so the answer `parseRelease` was already reading to find `tag_name` and
`assets` carried the changes in a field nothing looked at.

That left the card describing a decision the user was being asked to make
without saying anything the decision rests on. The button beside that sentence —
下载并更新 — replaces the folder this program runs from and restarts it. The
version number answers "is this newer"; it cannot answer "is this worth
interrupting what I am doing", which is the question a person standing in front
of that button actually has. A user could open the download page and read the
notes in a browser, and the browser may well be the one place on this machine
that cannot reach GitHub — which is the defect the sibling note records.

Two smaller facts pushed the same way. The check already pays for the body: it
is in the same response. And the four existing outcomes already spend a line on
detail — 「已是最新版本。」 and 「有新版本 v…。」 are different sentences — so the
card was already the place where the answer is spelled out; only the part that
matters to the reader was missing.

## Decision

**The body is carried, not interpreted, on the way in.** `UpdateCheck.notes`
holds what the release said, null unless the outcome is `available` and the body
was not blank:

```dart
notes: body is String && body.trim().isNotEmpty ? body : null,
```

Null rather than `''` so a surface has one thing to ask. Whitespace-only is null
for the same reason — a body of blank lines is a release with nothing to say,
and a card that opened a panel to show nothing would be claiming news.

**`lib/ui/update_notes.dart` reads the markdown into lines whose kind is data.**
`UpdateNoteKind` is `heading`, `item` or `text`, and `readUpdateNotes` returns a
list of them. It imports nothing — no Flutter, no localizations — which is what
lets `test/ui/update_notes_test.dart` cover it in `dart test`, the one gate that
always runs.

The reading makes three decisions worth naming:

- **Wrapped lines are put back together.** A `CHANGELOG.md` entry is hand-wrapped
  at about eighty columns, so one sentence is often three source lines. Shown as
  three lines, a reader would be reading the author's line breaks rather than
  what changed. A continuation is recognized by its indentation, and only under
  an item — a blank line, a heading or a new item ends the one above it.
- **The space a wrap took away is put back only where one belongs.** A Chinese
  sentence broken between two characters resumes without one (「取回新包、」then
  「按发布方…」); a break after an ASCII word needs it (`sha256` then 「核一遍」
  is `sha256 核一遍`). The rule is one comparison against `0x80`, applied to both
  sides of the break, and the release notes contain both cases.
- **The markup goes away.** `###`, `**`, backticks and a link's address are all
  things the reader did not type and does not need: a section is drawn as a
  section, an emphasis as prose, and `[发布说明](https://…)` as 发布说明.

**The card draws a labelled panel under the version sentence, and only when
there is something to put in it.** The label (`l10n.aboutUpdateNotes`, 更新日志)
is there because the panel is a *quotation* — the release's words — and a
quotation with no attribution inside a card that is otherwise this application's
own voice would read as a claim this application is making about itself. The
fill is `surfaceSunken`, the one this design gives an inset panel, which is also
what keeps a twelve-line changelog from reading as part of the card's own text.
Sections are set apart by weight rather than by size — smaller would read as a
footnote, larger would compete with the version line above. An item's text hangs
beside its bullet rather than under it, so a wrapped item does not read as a
sub-item of itself.

**No dependency was added.** There is no markdown renderer here, and the whole
of the markdown this application will ever be handed is what its own release
pipeline writes.

## Alternatives considered

**Render the markdown properly, with a package.** Rejected: a renderer, a
dependency and a version to track, for one panel on one page — and a renderer
would also bring a great deal of markdown this card will never see (tables,
images, code blocks, footnotes). The shape is known because this repository
publishes it, and the reading that shape needs is forty lines.

**Draw the body as it arrived.** Rejected: the first thing a reader would see is
`### 新增` and `**应用内一键更新**`, which is the release's file format rather than
the release's news. The two decisions above — reflow and strip — exist because a
card is not a file viewer.

**Keep the author's line breaks and draw each source line as its own line.**
Rejected: it is the simplest reading there is, and it shows a reader three short
ragged lines where the author wrote one sentence. The reflow's only real cost is
the space heuristic, which is tested in both directions.

**Put the notes somewhere else — a dialog, or a page of their own.** Rejected:
the panel belongs where the decision is taken. The card already holds the
button, the version and the address; sending a reader to a second surface to
find out whether they want the thing the first surface is offering is a trip for
a paragraph.

**Read the changelog out of the build's own files.** Rejected twice over: the
installed build does not carry `CHANGELOG.md` — `packaging/` ships the readme and
nothing else — and the section it would find describes the version *running*,
which is the one version on this card the user is not being asked about.

**Cap the panel and let it scroll.** Rejected: a nested scroll region inside the
page's own list, whose wheel and drag gestures have to be argued about, for a
body of a dozen lines that the page can simply be taller than.

**Show the notes only when the version is a milestone (a second-digit bump).**
Rejected: not proposed in earnest — there is no reading of this product's
version numbers under which a patch release's changes are less worth reading
than a minor one's, and the release pipeline does not distinguish them in the
notes either.

## Consequences

- **The card answers the question it was inviting.** 检查更新 now leads to the
  version, what changed, and then the two ways to act on it.
- **The About card is taller, and its height now depends on the release.** The
  whole note is drawn; the page scrolls, and nothing is truncated — one release
  whose notes run long is a long card rather than a hidden one. `UpdateNoteKind`
  is what keeps that from being shapeless: headings and items are laid out as
  headings and items, not as one wall of text.
- **`UpdateCheck` gained a field, and both branches are covered.** The About
  page's tests assert the panel and its four lines for a release with notes, and
  assert that a release without them shows the version and no label at all.
- **The notes are GitHub's answer, quoted, and nothing verifies them.** The
  digest beside them is checked against the file that arrives; the notes are not
  part of any such check and cannot be. They are rendered as the release wrote
  them, which is also why the stripper has to be right rather than clever.
- **A release published with `--generate-notes` reads differently.** GitHub's own
  generator writes 「What's Changed」 over bullet items and a `**Full Changelog**`
  line; that arrives as a heading, some items and a paragraph, which is honest
  and readable, and is not the sentence anybody wrote.
- **`update_notes.dart` is the third thing that knows what a release looks like**,
  after `release.yml` and `CHANGELOG.md`. It is the only one of the three that
  reads the format rather than writing it, and it is the only one whose input is
  not this repository's to change.

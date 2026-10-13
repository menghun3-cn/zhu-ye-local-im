/// What a release says about itself, read as the lines a surface draws.
///
/// The release body is markdown: this project's own pipeline writes it as the
/// version's `CHANGELOG.md` section, so it is a couple of `### 新增` headings
/// over `- **一句话**：说明…` items, and GitHub's own fallback generator writes
/// something of the same shape. Two ways to show that were rejected and one was
/// taken. Rendering it as markdown would mean a renderer and a dependency for
/// one card; drawing it raw would put `###` and `**` in front of somebody who
/// asked what changed. What is left is this: read the body into lines whose
/// *kind* is decided here, and let the surface decide what each kind looks
/// like.
///
/// Nothing in this file imports Flutter, which is what lets `dart test` — the
/// one gate that always runs — cover it directly.
library;

/// What one line of a release's notes is.
enum UpdateNoteKind {
  /// A section of the notes: `### 新增` becomes 新增.
  heading,

  /// One item of a list: `- **修复**：…` becomes 修复：….
  item,

  /// A line that is neither, drawn as it was written.
  text,
}

/// One line of a release's notes.
final class UpdateNote {
  /// Names a [kind] of line, spelled [text].
  const UpdateNote(this.kind, this.text);

  /// What sort of line this is.
  final UpdateNoteKind kind;

  /// The line's words, with the markdown that marked it up taken off.
  final String text;
}

/// Reads [notes] into the lines to draw.
///
/// Null and nothing-but-blank both give an empty list: a release that carries
/// no notes and one whose notes are an empty string are one thing to a card
/// that has nothing to show either way.
///
/// Wrapped lines are put back together rather than left as they were written.
/// A CHANGELOG entry is hand-wrapped at about eighty columns, so one sentence
/// can be three source lines — and a reader shown those three as three lines
/// would be reading the author's line breaks instead of what changed.
List<UpdateNote> readUpdateNotes(String? notes) {
  if (notes == null) return const [];
  final lines = <UpdateNote>[];
  // Whether the line before this one belonged to the item being read: only an
  // item resumes, and only across a break with no blank line in it.
  var openItem = false;
  for (final raw in notes.split('\n')) {
    final right = raw.trimRight();
    final line = right.trim();
    if (line.isEmpty) {
      openItem = false;
      continue;
    }
    if (_isRule(line) || line.startsWith('<!--')) {
      openItem = false;
      continue;
    }
    final indented = right.startsWith(' ') || right.startsWith('\t');
    if (indented && openItem) {
      final resumed = _plain(line);
      if (resumed.isNotEmpty) {
        final last = lines.removeLast();
        lines.add(UpdateNote(last.kind, _resume(last.text, resumed)));
      }
      continue;
    }
    if (line.startsWith('#')) {
      // The hashes are the markdown's way of saying "this is a section"; every
      // line here is drawn by the surface, which says it with type instead.
      _append(lines, UpdateNoteKind.heading, line.replaceFirst(_heading, ''));
      openItem = false;
      continue;
    }
    final item = _item.firstMatch(line);
    if (item != null) {
      openItem = _append(lines, UpdateNoteKind.item, item.group(2)!);
      continue;
    }
    openItem = false;
    _append(lines, UpdateNoteKind.text, line);
  }
  return lines;
}

/// Adds a line of [kind] saying [text], answering whether it was added.
///
/// False when the markup left nothing to say — a `###` with no title after it,
/// say — which is also how the caller learns that there is no item to resume.
bool _append(List<UpdateNote> lines, UpdateNoteKind kind, String text) {
  final plain = _plain(text);
  if (plain.isEmpty) return false;
  lines.add(UpdateNote(kind, plain));
  return true;
}

/// Joins a wrapped line onto the one before it.
///
/// The space the wrap took away is put back *only* where one belongs. A Chinese
/// sentence broken between two characters resumes without one — 「取回新包、」
/// followed by 「按发布方…」 — while a break after an ASCII word, or before one,
/// needs it: `sha256` followed by 「核一遍」 is `sha256 核一遍`, and the release
/// notes do contain that.
String _resume(String text, String next) {
  final after = text.codeUnitAt(text.length - 1);
  final before = next.codeUnitAt(0);
  final needs = after < 0x80 || before < 0x80;
  return needs ? '$text $next' : '$text$next';
}

/// [line] with the markdown that marked it up taken off.
String _plain(String line) {
  var text = line;
  // A link keeps its words and loses its address. Nothing on this card is
  // clickable, and an address in the middle of a sentence is longer than the
  // sentence.
  text = text.replaceAllMapped(_link, (match) => match.group(1)!);
  // Emphasis markers. The notes are drawn as prose, so a `**` a user never
  // typed would be read as punctuation that belongs to the release.
  text = text.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
  return text.trim();
}

/// Whether [line] is a horizontal rule — `---` between sections.
bool _isRule(String line) => _rule.hasMatch(line.replaceAll(' ', ''));

/// A heading's leading hashes and the space after them.
final RegExp _heading = RegExp(r'^#+\s*');

/// An item of a list: a bullet or a number, and the words after it.
final RegExp _item = RegExp(r'^(-|\*|\+|\d+\.)\s+(.*)$');

/// A markdown link, whose words are group 1 and whose address is dropped.
final RegExp _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');

/// Three or more of the same rule character and nothing else.
final RegExp _rule = RegExp(r'^([-*_])\1{2,}$');

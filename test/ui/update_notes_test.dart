import 'package:local_transfer/ui/update_notes.dart';
import 'package:test/test.dart';

/// Reading a release's notes into lines a card can draw.
///
/// The input is what this project's own pipeline publishes: the version's
/// `CHANGELOG.md` section, hand-wrapped at about eighty columns, with `###`
/// section titles over `- **一句话**：说明…` items. What is under test is the
/// reading — that sections are told from items, that a sentence wrapped across
/// three source lines comes back as one line, and that the markup a reader
/// never typed does not reach the screen.
///
/// Plain Dart, so `dart test` — the one gate that always runs — covers it.
void main() {
  /// The lines [notes] read into, as (kind, text) pairs.
  List<(UpdateNoteKind, String)> read(String? notes) => [
    for (final note in readUpdateNotes(notes)) (note.kind, note.text),
  ];

  test('tells a section from an item, and drops the markup', () {
    const notes = '''
### 新增

- **应用内一键更新**：程序取回新包、按发布方公布的校验值核一遍。
- **未读提示**：未读的会话在预览前显示 `[N]`。

### 变更

- **控件尺寸对齐主流**：「检查更新」改用实心按钮。
''';

    expect(read(notes), [
      (UpdateNoteKind.heading, '新增'),
      (UpdateNoteKind.item, '应用内一键更新：程序取回新包、按发布方公布的校验值核一遍。'),
      (UpdateNoteKind.item, '未读提示：未读的会话在预览前显示 [N]。'),
      (UpdateNoteKind.heading, '变更'),
      (UpdateNoteKind.item, '控件尺寸对齐主流：「检查更新」改用实心按钮。'),
    ]);
  });

  test('reads a wrapped sentence as one line', () {
    // One item, three source lines. A reader shown the fragments would be
    // reading the author's line breaks instead of what changed.
    const notes = '''
- 程序取回新包、
  按发布方公布的 sha256 核一遍、
  解压后交给新包自己替换本目录。
''';

    expect(read(notes), [
      (UpdateNoteKind.item, '程序取回新包、按发布方公布的 sha256 核一遍、解压后交给新包自己替换本目录。'),
    ]);
  });

  test('puts the space back only where the wrap took one away', () {
    // A Chinese sentence broken between two characters resumes without a space;
    // a break after an ASCII word needs it. The release notes contain both, and
    // a rule that guessed one of the two would write a sentence that reads as a
    // typo.
    expect(read('- 发布方公布的 sha256\n  核一遍'), [
      (UpdateNoteKind.item, '发布方公布的 sha256 核一遍'),
    ]);
    expect(read('- 拿固定地址去取\n  LocalTransfer-latest.zip'), [
      (UpdateNoteKind.item, '拿固定地址去取 LocalTransfer-latest.zip'),
    ]);
    expect(read('- 取回新包、\n  按校验值核一遍'), [(UpdateNoteKind.item, '取回新包、按校验值核一遍')]);
  });

  test('leaves a blank line, a rule and a comment out', () {
    // The notes are prose and a list; the punctuation markdown uses to lay
    // itself out is not something a reader asked to see.
    const notes = '''
<!-- 一条写给维护者的注释 -->
---

这是正文。
''';

    expect(read(notes), [(UpdateNoteKind.text, '这是正文。')]);
  });

  test('reads the other two ways to spell a list item', () {
    expect(read('* 星号'), [(UpdateNoteKind.item, '星号')]);
    expect(read('1. 编号'), [(UpdateNoteKind.item, '编号')]);
  });

  test("keeps a link's words and drops its address", () {
    // Nothing on the card is clickable, and an address in the middle of a
    // sentence is longer than the sentence.
    expect(read('- 见 [发布说明](https://example.test/notes) 一节'), [
      (UpdateNoteKind.item, '见 发布说明 一节'),
    ]);
  });

  test('reads notes written with Windows line endings', () {
    expect(read('### 修复\r\n\r\n- 修好了\r\n'), [
      (UpdateNoteKind.heading, '修复'),
      (UpdateNoteKind.item, '修好了'),
    ]);
  });

  test('has nothing to draw for notes that are not there', () {
    expect(readUpdateNotes(null), isEmpty);
    expect(readUpdateNotes(''), isEmpty);
    expect(readUpdateNotes('   \n\t\n'), isEmpty);
  });
}

import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/emoji_colour.dart';

/// The faces the composer offers, and the fonts that draw them.
///
/// The composer offers code points, and the platform draws them. On Windows
/// that leaves a trap: two system fonts claim the emoji code points, and the
/// one that comes first in the fallback chain wins — the symbol font draws
/// them as plain outlines, the emoji font draws them in colour. A face can
/// therefore be *grey* without a single line of this application's code
/// being wrong, which is a defect nobody can see in the diff.
///
/// These tests pin the two facts that make a face colourful: the chain puts
/// the colour font in front, and every face in the table has a colour glyph
/// to be drawn with. The second one is the one that catches a new face
/// nobody can draw — a code point the machine has no colour glyph for comes
/// out as an empty box, and no chain order can fix that.
void main() {
  group('the emoji colour', () {
    test('every face in the table has a colour glyph to be drawn with', () {
      final font = File(colourFontPaths.values.first);
      if (!font.existsSync()) {
        // A machine without the colour font cannot answer the question, and
        // a skipped question is honest: failing here would make the suite
        // depend on a machine rather than on the code.
        markTestSkipped('the colour font is not installed on this machine');
        return;
      }

      final uncoloured = <String>[
        for (final entry in emojiTable)
          if (!emojiColour(entry.emoji.runes.first).isColoured)
            '${entry.name} (${entry.emoji})',
      ];

      expect(
        uncoloured,
        isEmpty,
        reason: 'a face with no colour glyph is drawn as an empty box',
      );
    });

    test('the faces that need a variation selector carry one', () {
      // Some code points default to the *text* presentation, which is a
      // plain outline rather than a coloured face. The variation selector
      // U+FE0F is what asks for the coloured one instead.
      const textPresentation = {
        0x270B, // raised hand
        0x2753, // question mark ornament
        0x2757, // exclamation mark ornament
        0x2B50, // white medium star
        0x26A1, // high voltage
      };

      for (final entry in emojiTable) {
        final codePoint = entry.emoji.runes.first;
        if (!textPresentation.contains(codePoint)) continue;
        expect(
          entry.emoji.runes.contains(0xFE0F),
          isTrue,
          reason: '${entry.name} defaults to a plain outline without U+FE0F',
        );
      }
    });

    test('no face is offered twice', () {
      final seen = <String>{};
      final duplicates = <String>[
        for (final entry in emojiTable)
          if (!seen.add(entry.emoji)) entry.name,
      ];
      expect(duplicates, isEmpty);
    });
  });
}

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  const faces = ['😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😗', '😋', '😜'];

  group('the recent emoji store', () {
    test('an empty strip is an empty strip', () {
      expect(recentEmojis(faces, null), isEmpty);
      expect(recentEmojis(faces, const []), isEmpty);
    });

    test('stored faces come back newest first and capped', () {
      final stored = recentEmojis(faces, [
        '😍',
        '😀',
        '😁',
        '😊',
        '😂',
        '🤣',
        '😘',
        '😋',
      ]);
      expect(stored, ['😍', '😀', '😁', '😊', '😂', '🤣', '😘', '😋']);
    });

    test('faces this build no longer knows are dropped', () {
      expect(recentEmojis(faces, ['😀', '👻', '😁']), [
        '😀',
        '😁',
      ], reason: 'a strip must not show a face nobody can send');
    });

    test('remembering moves a face to the front without duplicating', () {
      var stored = rememberRecentEmoji(faces, null, face: '😀');
      stored = rememberRecentEmoji(faces, stored, face: '😂');
      stored = rememberRecentEmoji(faces, stored, face: '😀');
      expect(stored, ['😀', '😂']);
    });

    test('remembering caps the strip at the limit', () {
      var stored = const <String>[];
      for (final face in faces) {
        stored = rememberRecentEmoji(faces, stored, face: face, limit: 8);
      }
      expect(stored, hasLength(8));
      expect(stored, isNot(contains('😀')));
    });

    test('a face outside the table is refused', () {
      expect(rememberRecentEmoji(faces, null, face: '👻'), isEmpty);
    });
  });
}

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('CrockfordBase32', () {
    test('alphabet has 32 distinct symbols and omits the confusables', () {
      expect(CrockfordBase32.alphabet, hasLength(32));
      expect(CrockfordBase32.alphabet.split('').toSet(), hasLength(32));
      for (final symbol in ['I', 'L', 'O', 'U']) {
        expect(
          CrockfordBase32.alphabet.contains(symbol),
          isFalse,
          reason: '$symbol is excluded to keep codes unambiguous',
        );
      }
    });

    test('encodes hand-checkable values', () {
      // 0x00 -> 00000000 -> 00000 00000 -> "00"
      expect(CrockfordBase32.encode([0]), '00');
      // 0xFF -> 11111111 -> 11111 111|00 -> "Z" then 28 -> "ZW"
      expect(CrockfordBase32.encode([0xFF]), 'ZW');
    });

    test('round-trips every length that matters', () {
      for (var length = 0; length <= 40; length++) {
        final bytes = List<int>.generate(length, (i) => (i * 37 + 11) % 256);
        final code = CrockfordBase32.encode(bytes);
        expect(
          CrockfordBase32.decode(code),
          bytes,
          reason: 'length $length should survive a round trip',
        );
      }
    });

    test('decoding folds the characters a human confuses', () {
      // The canonical string is '0' at index 0 and '1' at index 1, so a code a
      // human typed with a confusable in either slot must decode identically.
      final canonical = CrockfordBase32.decode('0123456789ABCDEFGH');
      // 'O' folds to '0'.
      expect(CrockfordBase32.decode('O123456789ABCDEFGH'), canonical);
      expect(CrockfordBase32.decode('o123456789abcdefgh'), canonical);
      // 'I' and 'L' both fold to '1'.
      expect(CrockfordBase32.decode('0I23456789ABCDEFGH'), canonical);
      expect(CrockfordBase32.decode('0L23456789ABCDEFGH'), canonical);
    });

    test('decoding ignores display separators', () {
      expect(CrockfordBase32.decode('ZW-00'), CrockfordBase32.decode('ZW00'));
    });

    test('rejects a symbol outside the alphabet', () {
      expect(
        () => CrockfordBase32.decode('ZWU0'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('code presentation', () {
    test('groups a code for display without losing symbols', () {
      expect(groupCode('ABCDEFGHJK'), 'ABCDE-FGHJK');
    });

    test('normalises a typed code', () {
      expect(normaliseCode(' abc-de fghjk '), 'ABCDEFGHJK');
      expect(normaliseCode('abcd efghjk'), 'ABCDEFGHJK');
    });
  });
}

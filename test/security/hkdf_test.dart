import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

String _hex(List<int> bytes) => toHex(bytes);

void main() {
  group('HKDF-SHA256', () {
    // RFC 5869, Appendix A.1.
    test('matches test case 1', () {
      final ikm = Uint8List.fromList(List.filled(22, 0x0b));
      final salt = fromHex('000102030405060708090a0b0c');
      final info = fromHex('f0f1f2f3f4f5f6f7f8f9');

      final prk = HkdfSha256.extract(salt: salt, ikm: ikm);
      expect(
        _hex(prk),
        '077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5',
      );

      final okm = HkdfSha256.expand(prk: prk, info: info, length: 42);
      expect(
        _hex(okm),
        '3cb25f25faacd57a90434f64d0362f2a'
        '2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });

    // RFC 5869, Appendix A.3: zero-length salt and info.
    test('matches test case 3, with empty salt and info', () {
      final ikm = Uint8List.fromList(List.filled(22, 0x0b));
      final prk = HkdfSha256.extract(salt: const [], ikm: ikm);
      expect(
        _hex(prk),
        '19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04',
      );
      final okm = HkdfSha256.expand(prk: prk, info: const [], length: 42);
      expect(
        _hex(okm),
        '8da4e775a563c18f715f802a063c5a31'
        'b8a11f5c5ee1879ec3454e5f3c738d2d9'
        'd201395faa4b61a96c8',
      );
    });

    test('is deterministic for the same inputs', () {
      final a = HkdfSha256.deriveKey(
        ikm: [1, 2, 3],
        salt: [4],
        info: [5],
        length: 32,
      );
      final b = HkdfSha256.deriveKey(
        ikm: [1, 2, 3],
        salt: [4],
        info: [5],
        length: 32,
      );
      expect(a, b);
    });

    test('separates domains: a different info yields a different key', () {
      final a = HkdfSha256.deriveKey(
        ikm: [1, 2, 3],
        salt: [4],
        info: [5],
        length: 32,
      );
      final b = HkdfSha256.deriveKey(
        ikm: [1, 2, 3],
        salt: [4],
        info: [6],
        length: 32,
      );
      expect(a, isNot(b));
    });

    test('refuses to expand past its ceiling', () {
      expect(
        () => HkdfSha256.expand(
          prk: List.filled(32, 1),
          info: const [],
          length: HkdfSha256.maxOutputLength + 1,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('refuses a negative length', () {
      expect(
        () => HkdfSha256.expand(
          prk: List.filled(32, 1),
          info: const [],
          length: -1,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('produces the requested number of bytes across block boundaries', () {
      for (final length in [1, 31, 32, 33, 64, 100]) {
        final out = HkdfSha256.expand(
          prk: List.filled(32, 7),
          info: const [1, 2],
          length: length,
        );
        expect(out, hasLength(length));
      }
    });
  });

  group('constantTimeEquals', () {
    test('is true for equal sequences', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('is false on a single differing byte', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('is false for different lengths', () {
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('randomBytes', () {
    test('produces the requested length', () {
      expect(randomBytes(32), hasLength(32));
      expect(randomBytes(0), isEmpty);
    });

    test('does not repeat across calls', () {
      expect(randomBytes(32), isNot(randomBytes(32)));
    });
  });
}

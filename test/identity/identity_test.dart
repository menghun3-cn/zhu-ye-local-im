import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Fingerprint', () {
    test('derives the SHA-256 of the public key', () {
      // A published SHA-256 test vector, so this is not merely self-consistent.
      expect(
        Fingerprint.ofPublicKey(utf8.encode('abc')).hex,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('is stable for the same key and different for another', () {
      final a = Fingerprint.ofPublicKey(utf8.encode('device-a'));
      expect(a, Fingerprint.ofPublicKey(utf8.encode('device-a')));
      expect(a, isNot(Fingerprint.ofPublicKey(utf8.encode('device-b'))));
    });

    test('accepts uppercase and normalises to lowercase', () {
      final upper = Fingerprint('A' * 64);
      expect(upper.hex, 'a' * 64);
    });

    test('rejects a wrong length', () {
      expect(() => Fingerprint('ab'), throwsA(isA<FormatException>()));
      expect(() => Fingerprint('a' * 63), throwsA(isA<FormatException>()));
      expect(() => Fingerprint('a' * 65), throwsA(isA<FormatException>()));
    });

    test('rejects characters outside hex', () {
      expect(() => Fingerprint('z' * 64), throwsA(isA<FormatException>()));
    });

    test('shortens for display without exceeding the value', () {
      expect(Fingerprint('ab' * 32).short(), 'abababab');
      expect(Fingerprint('ab' * 32).short(128), 'ab' * 32);
    });

    test('orders consistently, so lists can be sorted', () {
      final low = Fingerprint('0' * 64);
      final high = Fingerprint('f' * 64);
      expect(low.compareTo(high), isNegative);
      expect([high, low]..sort(), [low, high]);
    });
  });

  group('hex helpers', () {
    test('round-trip', () {
      expect(toHex(fromHex('00ff10')), '00ff10');
    });

    test('reject malformed input rather than truncating', () {
      expect(() => fromHex('abc'), throwsA(isA<FormatException>()));
      expect(() => fromHex('zz'), throwsA(isA<FormatException>()));
    });
  });

  group('base64url helpers', () {
    test('round-trip, and stay free of characters that need escaping', () {
      final encoded = toBase64Url(List<int>.generate(32, (i) => i * 7 % 256));
      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
      expect(
        fromBase64Url(encoded),
        List<int>.generate(32, (i) => i * 7 % 256),
      );
    });

    test('reject malformed input', () {
      expect(() => fromBase64Url('!!!!'), throwsA(isA<FormatException>()));
    });
  });

  group('ClipboardCapability', () {
    test('Windows can both originate and apply', () {
      final capability = ClipboardCapability.forPlatform(
        DevicePlatform.windows,
      );
      expect(capability.canOriginate, isTrue);
      expect(capability.canApply, isTrue);
    });

    test('Android can apply but not originate in the background', () {
      final capability = ClipboardCapability.forPlatform(
        DevicePlatform.android,
      );
      expect(capability.canOriginate, isFalse);
      expect(capability.canApply, isTrue);
    });

    test('an unknown platform claims neither ability', () {
      final capability = ClipboardCapability.forPlatform(DevicePlatform.other);
      expect(capability.canOriginate, isFalse);
      expect(capability.canApply, isFalse);
      expect(capability.canMirrorAtAll, isFalse);
    });

    test('survives a JSON round trip', () {
      const original = ClipboardCapability(canOriginate: true, canApply: false);
      expect(ClipboardCapability.fromJson(original.toJson()), original);
    });

    test('rejects a non-boolean field', () {
      expect(
        () => ClipboardCapability.fromJson({
          'canOriginate': 'yes',
          'canApply': true,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DeviceDescriptor', () {
    test('strips control characters from an alias', () {
      // A name carrying a terminal escape or a newline exists to mislead
      // whoever reads the list of Devices.
      final descriptor = DeviceDescriptor(
        fingerprint: Fingerprint('a' * 64),
        alias: 'evil\u001b[31m\nname\u0007',
        platform: DevicePlatform.windows,
        capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
      );
      expect(descriptor.alias, 'evil[31mname');
    });

    test('collapses whitespace and trims', () {
      final descriptor = DeviceDescriptor(
        fingerprint: Fingerprint('a' * 64),
        alias: '  Desk   top  ',
        platform: DevicePlatform.windows,
        capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
      );
      expect(descriptor.alias, 'Desk top');
    });

    test('falls back when nothing usable is left', () {
      final descriptor = DeviceDescriptor(
        fingerprint: Fingerprint('a' * 64),
        alias: '\u0000\u0001',
        platform: DevicePlatform.windows,
        capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
      );
      expect(descriptor.alias, DeviceDescriptor.fallbackAlias);
    });

    test('truncates an over-long alias rather than rejecting the peer', () {
      final descriptor = DeviceDescriptor(
        fingerprint: Fingerprint('a' * 64),
        alias: 'x' * 500,
        platform: DevicePlatform.windows,
        capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
      );
      expect(descriptor.alias, hasLength(DeviceDescriptor.maxAliasLength));
    });

    test('rejects a listen port outside the valid range', () {
      expect(
        () => DeviceDescriptor(
          fingerprint: Fingerprint('a' * 64),
          alias: 'x',
          platform: DevicePlatform.windows,
          capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
          listenPort: 70000,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('round-trips through JSON, applying sanitisation on the way in', () {
      final original = DeviceDescriptor(
        fingerprint: Fingerprint('b' * 64),
        alias: 'Laptop',
        platform: DevicePlatform.android,
        capability: ClipboardCapability.forPlatform(DevicePlatform.android),
        listenPort: 51000,
      );
      final decoded = DeviceDescriptor.fromJson(original.toJson());
      expect(decoded.fingerprint, original.fingerprint);
      expect(decoded.alias, 'Laptop');
      expect(decoded.platform, DevicePlatform.android);
      expect(decoded.capability, original.capability);
      expect(decoded.listenPort, 51000);
    });

    test('rejects a malformed descriptor', () {
      expect(
        () => DeviceDescriptor.fromJson({
          'fp': 'a' * 64,
          'alias': 42,
          'platform': 'windows',
          'clip': {'canOriginate': true, 'canApply': true},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeviceDescriptor.fromJson({
          'fp': 'a' * 64,
          'alias': 'x',
          'platform': 'beos',
          'clip': {'canOriginate': true, 'canApply': true},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PairingSecret', () {
    test('derives the same secret from the same typed code', () {
      final code = PairingSecret.generateCode();
      expect(
        PairingSecret.fromCode(code).matches(PairingSecret.fromCode(code)),
        isTrue,
      );
    });

    test('a code survives display grouping and lowercase', () {
      final code = PairingSecret.generateCode();
      final typed = normaliseCode(groupCode(code).toLowerCase());
      expect(
        PairingSecret.fromCode(typed).matches(PairingSecret.fromCode(code)),
        isTrue,
      );
    });

    test('different codes yield different secrets', () {
      expect(
        PairingSecret.fromCode('ABCDE12345')
            .matches(PairingSecret.fromCode('ABCDE12346')),
        isFalse,
      );
    });

    test('rejects a code of the wrong length', () {
      expect(
        () => PairingSecret.fromCode('ABC'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a code containing a symbol no code could hold', () {
      expect(
        () => PairingSecret.fromCode('ABCDE1234U'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a generated code is exactly ten symbols of the alphabet', () {
      for (var i = 0; i < 50; i++) {
        final code = PairingSecret.generateCode();
        expect(code, hasLength(PairingSecret.codeSymbols));
        for (final symbol in code.split('')) {
          expect(CrockfordBase32.alphabet, contains(symbol));
        }
      }
    });

    test('a full-strength secret round-trips through its transport form', () {
      final secret = PairingSecret.random();
      expect(
        PairingSecret.fromTransportString(secret.toTransportString())
            .matches(secret),
        isTrue,
      );
      expect(secret.entropyBits, 256);
    });

    test('a typed code is reported as the weaker path it is', () {
      expect(PairingSecret.fromCode('ABCDE12345').entropyBits, lessThan(64));
    });

    test('refuses to hold too little key material', () {
      expect(
        () => PairingSecret.fromBytes(List.filled(8, 1)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('never prints its key material', () {
      final secret = PairingSecret.random();
      expect(secret.toString(), contains('redacted'));
      expect(secret.toString(), isNot(contains(toHex(secret.bytes))));
    });
  });
}

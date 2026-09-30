import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:local_transfer/core/identity/owner_identity.dart';

void main() {
  group('OwnerIdentity', () {
    test('a fresh identity has a 64-hex fingerprint', () async {
      final identity = await OwnerIdentity.generate();
      expect(identity.fingerprint.hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('two generated identities never share a fingerprint', () async {
      final a = await OwnerIdentity.generate();
      final b = await OwnerIdentity.generate();
      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('the same seed reproduces the same fingerprint', () async {
      final first = await OwnerIdentity.generate();
      final seed = await first.exportSeed();
      final restored = await OwnerIdentity.fromSeed(seed);
      expect(restored.fingerprint, first.fingerprint);
    });

    test('a seed of the wrong length is rejected loudly', () async {
      expect(() => OwnerIdentity.fromSeed(Uint8List(31)), throwsArgumentError);
      expect(() => OwnerIdentity.fromSeed(Uint8List(33)), throwsArgumentError);
    });

    test('a signature verifies against the right key and message', () async {
      final identity = await OwnerIdentity.generate();
      final publicKey = await identity.publicKey();
      final signature = await identity.sign('hello'.codeUnits);
      expect(
        await OwnerIdentity.verify(publicKey, 'hello'.codeUnits, signature),
        isTrue,
      );
    });

    test('a tampered message fails verification', () async {
      final identity = await OwnerIdentity.generate();
      final publicKey = await identity.publicKey();
      final signature = await identity.sign('hello'.codeUnits);
      expect(
        await OwnerIdentity.verify(publicKey, 'hellO'.codeUnits, signature),
        isFalse,
      );
    });

    test('a signature from another key fails verification', () async {
      final signer = await OwnerIdentity.generate();
      final other = await OwnerIdentity.generate();
      final signature = await signer.sign('hello'.codeUnits);
      expect(
        await OwnerIdentity.verify(
          await other.publicKey(),
          'hello'.codeUnits,
          signature,
        ),
        isFalse,
      );
    });

    test('garbage key material fails verification without throwing', () async {
      final identity = await OwnerIdentity.generate();
      final signature = await identity.sign('hello'.codeUnits);
      expect(
        await OwnerIdentity.verify(Uint8List(3), 'hello'.codeUnits, signature),
        isFalse,
      );
      expect(
        await OwnerIdentity.verify(
          await identity.publicKey(),
          'hello'.codeUnits,
          Uint8List(3),
        ),
        isFalse,
      );
    });

    test('toString never names the seed', () async {
      final identity = await OwnerIdentity.generate();
      final seed = await identity.exportSeed();
      expect(identity.toString(), isNot(contains(seed)));
    });
  });
}

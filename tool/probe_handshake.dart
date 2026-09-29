// ignore_for_file: avoid_print
//
// A handshake probe run by hand (`dart run tool/probe_handshake.dart`) to
// bisect a failing handshake stage by stage. Its printed output is the whole
// point — a throwaway diagnostic entry point has no logging framework to use.

import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:local_transfer/core/core.dart';

Future<void> stage(String name, Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    await body().timeout(const Duration(seconds: 4));
    print('OK   $name (${sw.elapsedMilliseconds}ms)');
  } on Object catch (error) {
    print('FAIL $name (${sw.elapsedMilliseconds}ms): $error');
  }
}

Future<void> main() async {
  await stage('1 transport plumbing', () async {
    final pair = MemoryTransportPair();
    final got = Completer<List<int>>();
    pair.b.incoming.listen((data) {
      if (!got.isCompleted) got.complete(data);
    });
    pair.a.add([1, 2, 3]);
    final received = await got.future;
    if (received.length != 3) throw StateError('got $received');
  });

  await stage('2 decodeFrames over memory transport', () async {
    final pair = MemoryTransportPair();
    final frames = decodeFrames(pair.b.incoming);
    final got = Completer<Frame>();
    frames.listen((frame) {
      if (!got.isCompleted) got.complete(frame);
    });
    pair.a.add(encodeFrame(ControlFrame({'t': 'hello'})));
    final frame = await got.future;
    if (frame is! ControlFrame) throw StateError('got $frame');
  });

  await stage('3 x25519 key exchange', () async {
    final x = X25519();
    final a = await x.newKeyPair();
    final b = await x.newKeyPair();
    final aPub = await a.extractPublicKey();
    final bPub = await b.extractPublicKey();
    final ab = await x.sharedSecretKey(keyPair: a, remotePublicKey: bPub);
    final ba = await x.sharedSecretKey(keyPair: b, remotePublicKey: aPub);
    final abBytes = await ab.extractBytes();
    final baBytes = await ba.extractBytes();
    if (abBytes.length != 32) {
      throw StateError('shared length ${abBytes.length}');
    }
    if (!constantTimeEquals(abBytes, baBytes)) {
      throw StateError('shared secrets disagree');
    }
  });

  await stage('4 chacha20 poly1305', () async {
    final cipher = Chacha20.poly1305Aead();
    final key = SecretKey(List.filled(32, 9));
    final box = await cipher.encrypt([1, 2, 3], secretKey: key, aad: [4, 5]);
    final plain = await cipher.decrypt(box, secretKey: key);
    if (plain.length != 3) throw StateError('got $plain');
  });

  await stage('5 hkdf over the real ikm sizes', () async {
    final ikm = Uint8List(64);
    final salt = Uint8List(64);
    final prk = HkdfSha256.extract(salt: salt, ikm: ikm);
    final key = HkdfSha256.expand(prk: prk, info: [1, 2], length: 32);
    if (key.length != 32) throw StateError('key length ${key.length}');
  });

  await stage('6 mutual handshake over memory transport', () async {
    final pair = MemoryTransportPair();
    final secret = PairingSecret.fromBytes(List.filled(32, 7));
    DeviceDescriptor device(String label, int seed) => DeviceDescriptor(
      fingerprint: Fingerprint.ofPublicKey(Uint8List(8)..fillRange(0, 8, seed)),
      alias: label,
      platform: DevicePlatform.windows,
      capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
    );
    final a =
        SecureLink.establish(
              transport: pair.a,
              role: LinkRole.initiator,
              local: device('a', 1),
              secret: secret,
              timeout: const Duration(seconds: 3),
            )
            .then((link) => 'A ok fp=${link.peer.fingerprint.short()}')
            .catchError((Object e) => 'A err: $e');
    final b =
        SecureLink.establish(
              transport: pair.b,
              role: LinkRole.responder,
              local: device('b', 2),
              secret: secret,
              timeout: const Duration(seconds: 3),
            )
            .then((link) => 'B ok fp=${link.peer.fingerprint.short()}')
            .catchError((Object e) => 'B err: $e');
    final results = await Future.wait([a, b]);
    print('     results: $results');
    if (results.any((r) => r.contains('err'))) {
      throw StateError('one side failed');
    }
  });

  print('probe finished');
}

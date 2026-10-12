import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  final me = testDevice('me');
  final alice = testDevice('alice', listenPort: 51001);
  final bob = testDevice(
    'bob',
    platform: DevicePlatform.android,
    listenPort: 51002,
  );
  // Same Fingerprint, different Alias: the same Device renamed itself.
  final renamedAlice = testDevice(
    'alice',
    alias: 'alice-renamed',
    listenPort: 51001,
  );

  final here = InternetAddress.loopbackIPv4;
  final elsewhere = InternetAddress('192.168.7.42');

  group('PeerRegistry', () {
    test('lists a peer that announces, with where to reach it', () {
      final registry = PeerRegistry(localFingerprint: me.fingerprint);

      expect(
        registry.observe(device: alice, address: elsewhere),
        isTrue,
        reason: 'a new peer changes the list',
      );

      final peer = registry.peers.single;
      expect(peer.device.alias, 'alice');
      expect(peer.fingerprint, alice.fingerprint);
      expect(peer.address.address, '192.168.7.42');
      expect(peer.sessionPort, 51001);
      expect(peer.isReachable, isTrue);

      registry.close();
    });

    test('never lists this Device, however it hears about itself', () {
      final registry = PeerRegistry(localFingerprint: me.fingerprint);

      expect(registry.observe(device: me, address: here), isFalse);
      expect(registry.peers, isEmpty);

      registry.close();
    });

    test('a peer that announces repeatedly is not a new event', () {
      final registry = PeerRegistry(localFingerprint: me.fingerprint);

      expect(registry.observe(device: alice, address: here), isTrue);
      expect(
        registry.observe(device: alice, address: here),
        isFalse,
        reason: 'the same peer at the same address is not a visible change',
      );
      expect(registry.peers, hasLength(1));

      registry.close();
    });

    test('a renamed peer and a peer that moved are visible changes', () {
      final registry = PeerRegistry(localFingerprint: me.fingerprint);

      registry.observe(device: alice, address: here);
      expect(registry.observe(device: renamedAlice, address: here), isTrue);
      expect(registry.peers.single.device.alias, 'alice-renamed');

      expect(registry.observe(device: alice, address: elsewhere), isTrue);
      expect(registry.peers.single.address.address, '192.168.7.42');

      registry.close();
    });

    test('a peer that goes quiet is dropped once its sighting ages out', () {
      var now = DateTime(2026, 9, 29, 12);
      final registry = PeerRegistry(
        localFingerprint: me.fingerprint,
        ttl: const Duration(seconds: 10),
        clock: () => now,
      );

      registry.observe(device: alice, address: here);
      registry.observe(device: bob, address: here);

      now = now.add(const Duration(seconds: 5));
      expect(registry.expire(), isEmpty, reason: 'both are still fresh');

      // Only alice keeps announcing.
      registry.observe(device: alice, address: here);
      now = now.add(const Duration(seconds: 9));
      final dropped = registry.expire();

      expect(dropped, [bob.fingerprint]);
      expect(registry.peers.single.fingerprint, alice.fingerprint);

      registry.close();
    });

    test(
      'expiry emits a change, and an empty list once all are gone',
      () async {
        var now = DateTime(2026, 9, 29, 12);
        final registry = PeerRegistry(
          localFingerprint: me.fingerprint,
          ttl: const Duration(seconds: 10),
          clock: () => now,
        );
        final seen = <List<DiscoveredPeer>>[];
        registry.changes.listen(seen.add);

        registry.observe(device: alice, address: here);
        await until(() => seen.length == 1, description: '新 peer 触发一次事件');

        now = now.add(const Duration(seconds: 11));
        registry.expire();
        await until(() => seen.length == 2, description: '过期触发一次事件');

        expect(seen.last, isEmpty);
        expect(registry.peers, isEmpty);

        registry.close();
      },
    );

    test('clear forgets everyone and says so once', () async {
      final registry = PeerRegistry(localFingerprint: me.fingerprint);
      registry.observe(device: alice, address: here);
      registry.observe(device: bob, address: here);

      final seen = <int>[];
      registry.changes.listen((peers) => seen.add(peers.length));
      registry.clear();

      await until(() => seen.length == 1, description: 'clear 触发一次事件');
      expect(seen.single, 0);
      expect(registry.peers, isEmpty);
      // A second clear has nothing to say.
      registry.clear();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen, hasLength(1));

      registry.close();
    });

    test('peers are listed most recently seen first', () {
      var now = DateTime(2026, 9, 29, 12);
      final registry = PeerRegistry(
        localFingerprint: me.fingerprint,
        clock: () => now,
      );

      registry.observe(device: alice, address: here);
      now = now.add(const Duration(seconds: 2));
      registry.observe(device: bob, address: here);

      expect(registry.peers.map((peer) => peer.device.alias), ['bob', 'alice']);

      registry.close();
    });
  });
}

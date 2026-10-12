import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

DiscoveryService _service(
  BeaconTransport transport,
  String label, {
  DevicePlatform platform = DevicePlatform.windows,
  int? port,
  Duration announce = const Duration(milliseconds: 40),
  Duration sweep = const Duration(milliseconds: 30),
  Duration ttl = const Duration(seconds: 10),
}) => DiscoveryService(
  transport: transport,
  local: testDevice(label, platform: platform, listenPort: port),
  announceInterval: announce,
  sweepInterval: sweep,
  peerTtl: ttl,
);

void main() {
  group('DiscoveryService over a link', () {
    test('two Devices announcing find each other', () async {
      final hub = MemoryBeaconHub();
      final alpha = _service(hub.a, 'alpha', port: 51001);
      final beta = _service(
        hub.b,
        'beta',
        platform: DevicePlatform.android,
        port: 51002,
      );

      alpha.start();
      beta.start();
      await until(
        () => alpha.currentPeers.length == 1 && beta.currentPeers.length == 1,
        description: '两端互相发现',
      );

      expect(alpha.currentPeers.single.device.alias, 'beta');
      expect(alpha.currentPeers.single.device.platform, DevicePlatform.android);
      expect(alpha.currentPeers.single.sessionPort, 51002);
      expect(beta.currentPeers.single.device.alias, 'alpha');

      await alpha.close();
      await beta.close();
    });

    test('a probe is answered in one round trip, not one announce period', () async {
      // Both Devices would take 30 seconds to announce on their own, so nothing
      // is learned unless the probe is answered directly.
      final hub = MemoryBeaconHub();
      const silent = Duration(seconds: 30);
      final beta = _service(
        hub.b,
        'beta',
        port: 51002,
        announce: silent,
        sweep: silent,
      );
      beta.start();

      final alpha = _service(
        hub.a,
        'alpha',
        port: 51001,
        announce: silent,
        sweep: silent,
      );
      alpha.start();

      await until(
        () => alpha.currentPeers.length == 1 && beta.currentPeers.length == 1,
        timeout: const Duration(seconds: 5),
        description: '一轮之内互相发现',
      );

      expect(alpha.currentPeers.single.device.alias, 'beta');
      expect(beta.currentPeers.single.device.alias, 'alpha');

      await alpha.close();
      await beta.close();
    });

    test('a Device that stops announcing leaves the list', () async {
      final hub = MemoryBeaconHub();
      final alpha = _service(
        hub.a,
        'alpha',
        port: 51001,
        ttl: const Duration(milliseconds: 200),
        sweep: const Duration(milliseconds: 20),
      );
      final beta = _service(
        hub.b,
        'beta',
        port: 51002,
        ttl: const Duration(milliseconds: 200),
      );

      alpha.start();
      beta.start();
      await until(
        () => alpha.currentPeers.length == 1,
        description: 'alpha 先发现 beta',
      );

      await beta.stop();
      await until(
        () => alpha.currentPeers.isEmpty,
        timeout: const Duration(seconds: 5),
        description: 'beta 停播后从列表消失',
      );

      await alpha.close();
      await beta.close();
    });

    test('a host claiming this Device Fingerprint is not a peer', () async {
      // The Fingerprint is a claim, not proof: anyone can broadcast it. It must
      // never turn this Device into its own peer.
      final hub = MemoryBeaconHub();
      final alpha = _service(hub.a, 'alpha', port: 51001);
      alpha.start();

      final impostor = hub.join();
      impostor.broadcast(
        Beacon(
          kind: BeaconKind.announce,
          device: testDevice('alpha', listenPort: 51001),
          nonce: 'ffffffffffffffff',
        ).encode(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(alpha.currentPeers, isEmpty);

      await alpha.close();
    });

    test('the peers stream reports the whole list on every change', () async {
      final hub = MemoryBeaconHub();
      final alpha = _service(hub.a, 'alpha', port: 51001);
      final beta = _service(hub.b, 'beta', port: 51002);

      final snapped = <List<DiscoveredPeer>>[];
      alpha.peers.listen(snapped.add);

      alpha.start();
      beta.start();
      await until(
        () => snapped.isNotEmpty && snapped.last.length == 1,
        description: 'peer 流报告当前列表',
      );

      expect(snapped.last.single.device.alias, 'beta');
      expect(alpha.peers, isA<Stream<List<DiscoveredPeer>>>());

      await alpha.close();
      await beta.close();
    });

    test('a stopped Device neither announces nor records anything', () async {
      final hub = MemoryBeaconHub();
      final alpha = _service(hub.a, 'alpha', port: 51001);
      alpha.start();
      await alpha.stop();
      expect(alpha.isRunning, isFalse);

      final beta = _service(hub.b, 'beta', port: 51002);
      beta.start();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        alpha.currentPeers,
        isEmpty,
        reason: 'a stopped Device is not listening',
      );
      expect(
        beta.currentPeers,
        isEmpty,
        reason:
            'a stopped Device is not announcing, so a peer that starts '
            'afterwards finds nothing',
      );

      await alpha.close();
      await beta.close();
    });

    test(
      'a datagram sent before a Device starts is not replayed to it',
      () async {
        // The in-memory link drops what nobody is listening for, so "did this
        // Device hear that?" has one answer. If it buffered instead, a stopped
        // Device could be observed recording something it never read.
        final hub = MemoryBeaconHub();
        final beta = _service(hub.b, 'beta', port: 51002);

        hub.a.broadcast(
          Beacon(
            kind: BeaconKind.announce,
            device: testDevice('alpha', listenPort: 51001),
            nonce: '0123456789abcdef',
          ).encode(),
        );
        beta.start();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(beta.currentPeers, isEmpty);

        await beta.close();
      },
    );

    test('start and stop are idempotent', () async {
      final hub = MemoryBeaconHub();
      final alpha = _service(hub.a, 'alpha', port: 51001);

      alpha.start();
      alpha.start();
      expect(alpha.isRunning, isTrue);
      await alpha.stop();
      await alpha.stop();
      expect(alpha.isRunning, isFalse);

      await alpha.close();
    });
  });
}

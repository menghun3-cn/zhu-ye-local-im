import 'dart:async';
import 'dart:io';

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

/// A transport that records the unicast probe and answers it on demand.
final class _ProbeTransport implements BeaconTransport {
  final StreamController<BeaconDatagram> _received =
      StreamController<BeaconDatagram>();

  List<int>? sent;
  InternetAddress? sentTo;
  int? sentPort;

  /// Every unicast send this transport was asked for, in order.
  final List<({InternetAddress address, int port})> sends = [];

  /// How many broadcasts this transport was asked for.
  int broadcasts = 0;

  @override
  Stream<BeaconDatagram> get received => _received.stream;

  @override
  void send(
    List<int> datagram, {
    required InternetAddress address,
    required int port,
  }) {
    sent = datagram;
    sentTo = address;
    sentPort = port;
    sends.add((address: address, port: port));
  }

  void answer(DeviceDescriptor device, InternetAddress from) {
    _received.add(
      BeaconDatagram(
        beacon: Beacon(
          kind: BeaconKind.announce,
          device: device,
          nonce: '0123456789abcdef',
        ),
        address: from,
        port: 41000,
      ),
    );
  }

  @override
  void broadcast(List<int> datagram) {
    broadcasts++;
  }

  @override
  Future<void> close() => _received.close();
}

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

    test('a unicast probe is answered by the Device at that address', () async {
      final transport = _ProbeTransport();
      final alpha = DiscoveryService(
        transport: transport,
        local: testDevice('alpha', listenPort: 51001),
        announceInterval: const Duration(seconds: 30),
        sweepInterval: const Duration(seconds: 30),
      );
      alpha.start();

      final target = InternetAddress('192.0.2.10');
      final answer = alpha.probeHost(
        target,
        timeout: const Duration(seconds: 2),
      );
      await until(
        () => transport.sentPort == discoveryPort,
        description: 'the unicast probe to be sent',
      );
      expect(transport.sentTo?.address, target.address);

      transport.answer(testDevice('beta', listenPort: 51002), target);
      final peer = await answer;
      expect(peer?.device.alias, 'beta');
      expect(peer?.address.address, target.address);
      expect(peer?.sessionPort, 51002);

      await alpha.close();
    });

    test('unicast targets are probed on their own cadence', () async {
      final transport = _ProbeTransport();
      final alpha = DiscoveryService(
        transport: transport,
        local: testDevice('alpha', listenPort: 51001),
        announceInterval: const Duration(seconds: 30),
        sweepInterval: const Duration(seconds: 30),
        unicastTargets: () async => [
          InternetAddress('100.64.0.1'),
          InternetAddress('100.64.0.2'),
          // A duplicate must not cost a second datagram.
          InternetAddress('100.64.0.1'),
        ],
        unicastProbeInterval: const Duration(milliseconds: 40),
      );
      alpha.start();

      await until(() => transport.sends.length >= 4, description: '两轮单播探测发出');

      // Two distinct targets per round: the duplicate was dropped.
      expect(transport.sends.map((send) => send.address.address).toSet(), {
        '100.64.0.1',
        '100.64.0.2',
      });
      expect(
        transport.sends.every((send) => send.port == discoveryPort),
        isTrue,
      );

      await alpha.close();
    });

    test('unicast targets are capped per round', () async {
      final transport = _ProbeTransport();
      final alpha = DiscoveryService(
        transport: transport,
        local: testDevice('alpha', listenPort: 51001),
        announceInterval: const Duration(seconds: 30),
        sweepInterval: const Duration(seconds: 30),
        unicastTargets: () async => [
          for (var i = 0; i < 10; i++) InternetAddress('100.64.0.$i'),
        ],
        unicastProbeInterval: const Duration(milliseconds: 40),
        maxUnicastTargets: 3,
      );
      alpha.start();

      await until(() => transport.sends.length >= 3, description: '第一轮单播探测发出');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // Ten targets were offered; every round sent a multiple of the cap,
      // never all ten.
      expect(transport.sends.length, greaterThanOrEqualTo(3));
      expect(transport.sends.length % 3, 0);

      await alpha.close();
    });

    test('a failing unicast provider does not stop discovery', () async {
      final transport = _ProbeTransport();
      var calls = 0;
      final alpha = DiscoveryService(
        transport: transport,
        local: testDevice('alpha', listenPort: 51001),
        announceInterval: const Duration(milliseconds: 40),
        sweepInterval: const Duration(seconds: 30),
        unicastTargets: () async {
          calls++;
          throw StateError('no directory');
        },
        unicastProbeInterval: const Duration(milliseconds: 40),
      );
      alpha.start();

      await until(
        () => transport.broadcasts > 0 && calls > 0,
        description: '广播照常、provider 被调用',
      );
      expect(alpha.isRunning, isTrue);

      await alpha.close();
    });

    test('an announce answering a unicast probe joins the peer list', () async {
      final transport = _ProbeTransport();
      final alpha = DiscoveryService(
        transport: transport,
        local: testDevice('alpha', listenPort: 51001),
        announceInterval: const Duration(seconds: 30),
        sweepInterval: const Duration(seconds: 30),
        unicastTargets: () async => [InternetAddress('100.64.0.9')],
        unicastProbeInterval: const Duration(milliseconds: 40),
      );
      alpha.start();

      await until(() => transport.sends.isNotEmpty, description: '单播探测发出');
      transport.answer(
        testDevice('beta', listenPort: 51002),
        InternetAddress('100.64.0.9'),
      );

      await until(
        () => alpha.currentPeers.length == 1,
        description: '应答者进入 peer 列表',
      );
      final peer = alpha.currentPeers.single;
      expect(peer.device.alias, 'beta');
      expect(peer.address.address, '100.64.0.9');
      expect(peer.sessionPort, 51002);

      await alpha.close();
    });

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

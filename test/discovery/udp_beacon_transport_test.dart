import 'dart:io';
import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// Binds a discovery socket on loopback with an ephemeral port and **no**
/// broadcast targets, so a test never puts a packet on the real LAN.
Future<UdpBeaconTransport> bindLoopback({
  int? broadcastPort,
  Future<List<InternetAddress>> Function()? targets,
}) => UdpBeaconTransport.bind(
  port: 0,
  broadcastPort: broadcastPort,
  address: InternetAddress.loopbackIPv4,
  targets: targets ?? () async => const <InternetAddress>[],
  targetRefreshInterval: Duration.zero,
);

void main() {
  final device = testDevice('device-a', listenPort: 51001);

  Uint8List announce({String nonce = '0123456789abcdef'}) =>
      Beacon(kind: BeaconKind.announce, device: device, nonce: nonce).encode();

  group('UdpBeaconTransport', () {
    test(
      'a datagram sent to a peer arrives decoded, with its source port',
      () async {
        final sender = await bindLoopback();
        final receiver = await bindLoopback();
        addTearDown(() async {
          await sender.close();
          await receiver.close();
        });

        final arrived = receiver.received.first;
        sender.send(
          announce(),
          address: InternetAddress.loopbackIPv4,
          port: receiver.port,
        );

        final datagram = await arrived.timeout(const Duration(seconds: 5));
        expect(datagram.beacon.kind, BeaconKind.announce);
        expect(datagram.beacon.device.fingerprint, device.fingerprint);
        expect(datagram.beacon.device.alias, 'device-a');
        expect(datagram.address.address, '127.0.0.1');
        expect(
          datagram.port,
          sender.port,
          reason: 'the source port is what an answer has to be addressed to',
        );
      },
    );

    test(
      'a malformed datagram is dropped and the receive loop survives',
      () async {
        final sender = await bindLoopback();
        final receiver = await bindLoopback();
        addTearDown(() async {
          await sender.close();
          await receiver.close();
        });

        final datagrams = <BeaconDatagram>[];
        final errors = <Object>[];
        receiver.received.listen(datagrams.add, onError: errors.add);

        // A stranger can send these at any time; none may stop discovery.
        sender.send(
          'not a beacon at all'.codeUnits,
          address: InternetAddress.loopbackIPv4,
          port: receiver.port,
        );
        sender.send(
          [0xff, 0xfe, 0xfd],
          address: InternetAddress.loopbackIPv4,
          port: receiver.port,
        );
        sender.send(
          announce(nonce: 'abcdef0123456789'),
          address: InternetAddress.loopbackIPv4,
          port: receiver.port,
        );

        await until(
          () => datagrams.isNotEmpty,
          timeout: const Duration(seconds: 5),
          description: '坏包之后的好包仍然到达',
        );

        expect(datagrams, hasLength(1));
        expect(datagrams.single.beacon.nonce, 'abcdef0123456789');
        expect(errors, isEmpty, reason: '坏包被丢弃，而不是让流报错');
      },
    );

    test('broadcast reaches the targets and the port it was configured with', () async {
      // The receiver listens on a known port; the sender is told that peers are
      // addressed on that port and that the local host is the target, so a real
      // broadcast send lands on it. This exercises the broadcast path end to
      // end without touching the physical LAN.
      final receiver = await bindLoopback();
      addTearDown(receiver.close);
      final sender = await bindLoopback(
        broadcastPort: receiver.port,
        targets: () async => [InternetAddress.loopbackIPv4],
      );
      addTearDown(sender.close);

      final arrived = receiver.received.first;
      await until(
        () => sender.broadcastTargets.isNotEmpty,
        description: '广播目标被缓存',
      );
      expect(sender.broadcastPort, receiver.port);

      sender.broadcast(announce());

      final datagram = await arrived.timeout(const Duration(seconds: 5));
      expect(datagram.beacon.kind, BeaconKind.announce);
      expect(datagram.beacon.nonce, '0123456789abcdef');
    });

    test('the default targets include the limited broadcast address', () async {
      // Network enumeration may legitimately return nothing on a headless or
      // isolated host, so only the invariant is asserted here.
      expect(limitedBroadcastAddress.address, '255.255.255.255');
      final targets = await defaultBroadcastTargets();
      expect(
        targets.map((address) => address.address),
        contains('255.255.255.255'),
      );
    });

    test('close is idempotent and stops delivery', () async {
      final receiver = await bindLoopback();
      final arrived = <BeaconDatagram>[];
      receiver.received.listen(arrived.add);

      await receiver.close();
      await receiver.close();

      expect(arrived, isEmpty);
    });
  });
}

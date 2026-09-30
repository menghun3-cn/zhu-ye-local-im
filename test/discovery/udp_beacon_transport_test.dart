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

    test('every datagram in a burst is delivered', () async {
      // A `RawDatagramSocket` accepts one datagram at a time: a `send` issued
      // while another is still in flight returns 0 and the datagram is gone.
      // A burst is not exotic — an announce is one `send` per broadcast target,
      // and a probe can be answered in the same tick as the announce timer
      // fires — so a transport that ignores the return value loses beacons on
      // exactly the path it exists to serve.
      //
      // The window is a few hundred microseconds wide, so one round of this can
      // slip through; several in a row will not.
      final sender = await bindLoopback();
      final receiver = await bindLoopback();
      addTearDown(() async {
        await sender.close();
        await receiver.close();
      });

      const bursts = 8;
      const perBurst = 4;
      final sent = <String>[];
      final datagrams = <Uint8List>[];
      for (var burst = 0; burst < bursts; burst++) {
        for (var i = 0; i < perBurst; i++) {
          final nonce =
              '${burst.toString().padLeft(4, '0')}'
              '${i.toString().padLeft(4, '0')}';
          sent.add(nonce);
          datagrams.add(announce(nonce: nonce));
        }
      }
      final arrived = <String>[];
      receiver.received.listen(
        (datagram) => arrived.add(datagram.beacon.nonce),
      );

      // Encoding happens up front on purpose: the loop below has to be nothing
      // but `send`, so that it is the sends that are back to back. Encoding a
      // beacon in between takes long enough for the previous write to complete,
      // which hides the very window this test exists to cover.
      for (final datagram in datagrams) {
        sender.send(
          datagram,
          address: InternetAddress.loopbackIPv4,
          port: receiver.port,
        );
      }

      await until(
        () => arrived.length >= sent.length,
        timeout: const Duration(seconds: 10),
        description: '整个突发都到达',
      );
      expect(arrived, unorderedEquals(sent));
    });

    test('a broadcast sends to every target, not only the first', () async {
      // Both targets are the same address because two sockets cannot share one
      // UDP port; what is under test is that the transport performs one `send`
      // per target. The second one is the datagram a socket with a single
      // outstanding write drops, and repeating the broadcast turns a margin
      // that is normally a few hundred microseconds wide into a certainty.
      final receiver = await bindLoopback();
      addTearDown(receiver.close);
      final sender = await bindLoopback(
        broadcastPort: receiver.port,
        targets: () async => [
          InternetAddress.loopbackIPv4,
          InternetAddress.loopbackIPv4,
        ],
      );
      addTearDown(sender.close);

      final arrived = <String>[];
      receiver.received.listen(
        (datagram) => arrived.add(datagram.beacon.nonce),
      );
      await until(
        () => sender.broadcastTargets.length == 2,
        description: '两个广播目标都被缓存',
      );

      const rounds = 10;
      for (var round = 0; round < rounds; round++) {
        sender.broadcast(announce(nonce: round.toString().padLeft(16, '0')));
      }

      await until(
        () => arrived.length >= rounds * 2,
        timeout: const Duration(seconds: 10),
        description: '每个目标各收到每一条广播',
      );
      expect(arrived, hasLength(rounds * 2));
    });

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

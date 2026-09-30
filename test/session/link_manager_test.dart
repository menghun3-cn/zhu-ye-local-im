import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:local_transfer/core/core.dart';

import '../support/harness.dart';
import '../transfer/support.dart';

/// One Device's manager, with its own identity and secret, listening on a
/// free loopback port.
final class TestPeerDevice {
  TestPeerDevice._({
    required this.device,
    required this.manager,
    required this.secret,
  });

  static Future<TestPeerDevice> start(
    String label, {
    PairingSecret? secret,
    int port = 0,
  }) async {
    final resolved = secret ?? PairingSecret.fromBytes(List.filled(32, 9));
    final manager = LinkManager(
      local: testDevice(label),
      sessionSecret: resolved,
    );
    await manager.serve(port: port);
    return TestPeerDevice._(
      device: manager.advertised,
      manager: manager,
      secret: resolved,
    );
  }

  final DeviceDescriptor device;
  final LinkManager manager;
  final PairingSecret secret;

  /// Everything the manager emitted, in order.
  final List<LinkEvent> events = [];

  Fingerprint get fingerprint => device.fingerprint;

  int get port => manager.listenPort!;

  /// Starts recording events.
  void record() => manager.events.listen(events.add);

  /// The first event of type [T], or null.
  T? firstOf<T extends LinkEvent>() {
    for (final event in events) {
      if (event is T) return event;
    }
    return null;
  }

  Future<void> close() => manager.close();
}

/// Starts two Devices that have recorded their events.
Future<(TestPeerDevice, TestPeerDevice)> twoDevices() async {
  final alice = await TestPeerDevice.start('alice-wire');
  final bob = await TestPeerDevice.start('bob-wire');
  alice.record();
  bob.record();
  return (alice, bob);
}

/// A manager that is not serving and never will be, for construction checks.
LinkManager idleManager(String label) => LinkManager(
  local: testDevice(label),
  sessionSecret: PairingSecret.fromBytes(List.filled(32, 9)),
);

void main() {
  group('LinkManager serving', () {
    test('advertised carries the bound port once serving', () async {
      final alice = await TestPeerDevice.start('alice-wire');
      addTearDown(alice.close);
      expect(alice.manager.isServing, isTrue);
      expect(alice.manager.advertised.listenPort, alice.port);
      expect(alice.port, greaterThan(0));
    });

    test('a descriptor never advertises a port before serving', () {
      final manager = idleManager('alice-wire');
      expect(manager.isServing, isFalse);
      expect(manager.advertised.listenPort, isNull);
    });

    test('serving twice is a programming error, stated plainly', () async {
      final alice = await TestPeerDevice.start('alice-wire');
      addTearDown(alice.close);
      expect(alice.manager.serve(port: 0), throwsStateError);
    });

    test('closing the listener frees the port for another Device', () async {
      final alice = await TestPeerDevice.start('alice-wire');
      final port = alice.port;
      await alice.close();
      final again = idleManager('alice-wire-2');
      addTearDown(again.close);
      await again.serve(port: port);
      expect(again.listenPort, port);
    });
  });

  group('LinkManager sessions over real TCP', () {
    test('connect establishes a Session on both sides', () async {
      final (alice, bob) = await twoDevices();
      addTearDown(alice.close);
      addTearDown(bob.close);

      final session = await alice.manager.connect('127.0.0.1', bob.port);

      expect(session.peer, bob.fingerprint);
      expect(session.role, LinkRole.initiator);
      expect(session.isOpen, isTrue);
      expect(alice.manager.session(bob.fingerprint), session);
      expect(alice.manager.isConnectedTo(bob.fingerprint), isTrue);

      // The responder learned who dialled from the handshake itself.
      await until(
        () => bob.manager.session(alice.fingerprint) != null,
        description: 'bob holds a Session with alice',
      );
      final inbound = bob.manager.session(alice.fingerprint)!;
      expect(inbound.role, LinkRole.responder);
      expect(inbound.address, isNotNull);
      expect(inbound.peer, alice.fingerprint);

      // Both sides derived the same short authentication string from the
      // established link — the value a Pairing signs its admission over.
      expect(
        inbound.hub.link.shortAuthenticationString,
        session.hub.link.shortAuthenticationString,
      );
      expect(session.hub.link.shortAuthenticationString, hasLength(6));
    });

    test('both sides see the Session as an event', () async {
      final (alice, bob) = await twoDevices();
      addTearDown(alice.close);
      addTearDown(bob.close);

      await alice.manager.connect('127.0.0.1', bob.port);
      await until(
        () =>
            alice.firstOf<SessionEstablished>() != null &&
            bob.firstOf<SessionEstablished>() != null,
        description: 'both sides emitted SessionEstablished',
      );
      expect(
        alice.firstOf<SessionEstablished>()!.session.peer,
        bob.fingerprint,
      );
      expect(
        bob.firstOf<SessionEstablished>()!.session.peer,
        alice.fingerprint,
      );
    });

    test(
      'a second Session with the same peer is refused, the first survives',
      () async {
        final (alice, bob) = await twoDevices();
        addTearDown(alice.close);
        addTearDown(bob.close);

        final first = await alice.manager.connect('127.0.0.1', bob.port);
        await expectLater(
          alice.manager.connect('127.0.0.1', bob.port),
          throwsA(isA<HandshakeException>()),
        );
        expect(alice.manager.sessions, hasLength(1));
        expect(alice.manager.session(bob.fingerprint), first);
        expect(first.isOpen, isTrue);
        await until(
          () => bob.manager.sessions.length == 1,
          description: 'bob still holds exactly one Session',
        );
        expect(
          bob.firstOf<SessionRefused>(),
          isNotNull,
          reason: 'a refused connection is reported, not swallowed',
        );
      },
    );

    test(
      'a pinning caller refuses a peer that is not the expected Device',
      () async {
        final (alice, bob) = await twoDevices();
        final carol = await TestPeerDevice.start('carol-wire');
        addTearDown(alice.close);
        addTearDown(bob.close);
        addTearDown(carol.close);

        await expectLater(
          alice.manager.connect(
            '127.0.0.1',
            bob.port,
            expectedFingerprint: carol.fingerprint,
          ),
          throwsA(isA<HandshakeException>()),
        );
        // The dialing side must hold nothing: the pin is worthless if a Session
        // with the wrong Device exists even briefly. The responder cannot know
        // it was not wanted, so it may hold one momentarily — and then it goes
        // away, because the dialer closed the connection.
        expect(alice.manager.sessions, isEmpty);
        await until(
          () => bob.manager.sessions.isEmpty,
          description: 'bob dropped the unwanted Session',
        );
      },
    );

    test('a Device refuses a Session with itself', () async {
      final alice = await TestPeerDevice.start('alice-wire');
      alice.record();
      addTearDown(alice.close);

      await expectLater(
        alice.manager.connect('127.0.0.1', alice.port),
        throwsA(isA<HandshakeException>()),
      );
      expect(alice.manager.sessions, isEmpty);
      await until(
        () => alice.firstOf<SessionRefused>() != null,
        description: 'the listener reported the refused self-connection',
      );
    });

    test('a wrong Pairing Secret never becomes a Session', () async {
      final alice = await TestPeerDevice.start('alice-wire');
      final stranger = await TestPeerDevice.start(
        'stranger-wire',
        secret: PairingSecret.fromBytes(List.filled(32, 11)),
      );
      addTearDown(alice.close);
      addTearDown(stranger.close);

      await expectLater(
        stranger.manager.connect('127.0.0.1', alice.port),
        throwsA(isA<HandshakeException>()),
      );
      expect(stranger.manager.sessions, isEmpty);
      expect(alice.manager.sessions, isEmpty);
    });

    test(
      'a dead port is reported as a handshake failure, not a crash',
      () async {
        final alice = await TestPeerDevice.start('alice-wire');
        addTearDown(alice.close);
        // Bind a port to learn one that is currently free, then release it.
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final deadPort = probe.port;
        await probe.close();

        await expectLater(
          alice.manager.connect('127.0.0.1', deadPort),
          throwsA(isA<HandshakeException>()),
        );
        expect(alice.manager.sessions, isEmpty);
      },
    );

    test('closing one side is reported to the other as SessionLost', () async {
      final (alice, bob) = await twoDevices();
      addTearDown(alice.close);
      addTearDown(bob.close);

      final session = await alice.manager.connect('127.0.0.1', bob.port);
      await until(
        () => bob.manager.isConnectedTo(alice.fingerprint),
        description: 'bob holds the Session',
      );

      await session.close();

      await until(
        () => alice.manager.session(bob.fingerprint) == null,
        description: 'alice forgot the Session',
      );
      await until(
        () => bob.manager.session(alice.fingerprint) == null,
        description: 'bob forgot the Session',
      );
      final lost = bob.firstOf<SessionLost>();
      expect(lost, isNotNull);
      expect(lost!.peer, alice.fingerprint);
      expect(alice.firstOf<SessionLost>()!.peer, bob.fingerprint);
    });

    test('closing the manager ends its Sessions and stops listening', () async {
      final (alice, bob) = await twoDevices();
      addTearDown(bob.close);

      await alice.manager.connect('127.0.0.1', bob.port);
      await until(
        () => bob.manager.isConnectedTo(alice.fingerprint),
        description: 'bob holds the Session',
      );

      await alice.close();

      await until(
        () => bob.manager.session(alice.fingerprint) == null,
        description: 'bob saw the Session go away',
      );
      expect(alice.manager.isClosed, isTrue);
      expect(alice.manager.connect('127.0.0.1', bob.port), throwsStateError);
    });

    test('a Session carries a Transfer end to end', () async {
      final (alice, bob) = await twoDevices();
      addTearDown(alice.close);
      addTearDown(bob.close);

      final session = await alice.manager.connect('127.0.0.1', bob.port);
      await until(
        () => bob.manager.session(alice.fingerprint) != null,
        description: 'bob holds the Session',
      );
      final inbound = bob.manager.session(alice.fingerprint)!;

      final aliceEngine = TransferEngine(channel: session.hub.transfers);
      final bobEngine = TransferEngine(channel: inbound.hub.transfers);
      addTearDown(aliceEngine.close);
      addTearDown(bobEngine.close);

      final received = Completer<MemoryReceipt>();
      bobEngine.incoming.listen((transfer) async {
        received.complete(await acceptIntoMemory(transfer));
      });

      await aliceEngine.sendText('hello over a managed Session');
      final receipt = await received.future;

      expect(receipt.inlineText, 'hello over a managed Session');
      await until(
        () => receipt.transfer.isSettled,
        description: 'the receiving side settled the Transfer',
      );
    });
  });
}

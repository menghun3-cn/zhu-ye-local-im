import 'dart:io';
import 'dart:typed_data';

import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// One Device under test: the controller and the seams it was handed.
///
/// The seams are the in-memory ones — a profile store, a system clipboard, and
/// a shared beacon hub — so two of these run in one process. Everything below
/// the seams is the real thing: a real `ServerSocket`, a real handshake, real
/// sealed records. That is the point of the app layer being plain Dart.
final class TestDevice {
  TestDevice(this.controller, this.clipboard);

  final LocalTransferController controller;
  final MemorySystemClipboard clipboard;

  /// Offers this Device has been asked to answer, in arrival order.
  final List<IncomingTransfer> offers = [];

  Fingerprint get fingerprint => controller.self.fingerprint;

  /// Starts recording offers, the way a UI would by rendering them.
  void recordOffers() => controller.incoming.listen(offers.add);
}

/// Brings a Device up on [transport], with an ephemeral port for everything.
Future<TestDevice> startDevice(
  BeaconTransport transport,
  String alias, {
  ClipboardMode clipboardMode = ClipboardMode.off,
}) async {
  final clipboard = MemorySystemClipboard();
  final controller = LocalTransferController(
    store: MemoryProfileStore(),
    beaconTransport: transport,
    clipboard: clipboard,
    alias: alias,
    // Port 0 for both, so several Devices run on one host and a test never
    // fights another test over a fixed port.
    sessionListenPort: 0,
    pairingPort: 0,
    clipboardMode: clipboardMode,
  );
  await controller.start();
  addTearDown(controller.close);
  final device = TestDevice(controller, clipboard);
  device.recordOffers();
  return device;
}

/// Runs the typed-code Pairing between [host] and [guest] to completion.
///
/// Both users confirm, as they would on two screens: the code gets the two
/// Devices talking, and the confirmation is what turns that into membership.
Future<void> pairUp(TestDevice host, TestDevice guest) async {
  final invitation = await host.controller.invite();
  final guestAttempt = await guest.controller.join(
    host: InternetAddress.loopbackIPv4.address,
    code: invitation.code,
    port: invitation.port,
  );
  final hostAttempt = await invitation.attempt;
  expect(
    hostAttempt.sas,
    guestAttempt.sas,
    reason: 'both Devices must derive the same digits to compare',
  );
  await Future.wait([hostAttempt.confirm(), guestAttempt.confirm()]);
  await until(
    () => host.controller.isServing && guest.controller.isServing,
    description: 'both Devices to serve Sessions',
  );
}

/// Opens a Session from [from] to [to], once Discovery has placed [to].
Future<void> connect(TestDevice from, TestDevice to) async {
  final target = to.fingerprint;
  await until(
    () => from.controller.peers.any(
      (peer) => peer.fingerprint == target && peer.isDiallable,
    ),
    description: '${to.controller.self.alias} to be discovered with a port',
  );
  await from.controller.connect(target);
  await until(
    () =>
        from.controller.sessions.isNotEmpty &&
        to.controller.sessions.isNotEmpty,
    description: 'the Session to come up on both Devices',
  );
}

Directory tempDirectory(String prefix) {
  final directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

Fingerprint fingerprintOf(String label) =>
    Fingerprint.ofPublicKey(Uint8List.fromList(label.codeUnits));

void main() {
  group('a Device on its own', () {
    test('starts unpaired, and serves nothing', () async {
      final hub = MemoryBeaconHub();
      final solo = await startDevice(hub.a, 'Solo');

      expect(solo.controller.isPaired, isFalse);
      expect(solo.controller.isServing, isFalse);
      expect(solo.controller.listenPort, isNull);
      expect(solo.controller.sessions, isEmpty);
      expect(solo.controller.self.alias, 'Solo');
      expect(solo.controller.self.groupLength, 1);
      expect(solo.controller.self.capability.canMirrorAtAll, isTrue);
      expect(solo.controller.self.shortFingerprint, isNotEmpty);
    });

    test(
      'has nothing to authenticate a Session with, so dialling is refused',
      () async {
        final hub = MemoryBeaconHub();
        final solo = await startDevice(hub.a, 'Solo');
        await expectLater(
          solo.controller.connect(fingerprintOf('somebody')),
          throwsA(isA<AppStateException>()),
        );
      },
    );

    test('has nothing to send to', () async {
      final hub = MemoryBeaconHub();
      final solo = await startDevice(hub.a, 'Solo');
      await expectLater(
        solo.controller.sendText('anybody there?'),
        throwsA(isA<AppStateException>()),
      );
    });

    test('closing twice is harmless and stops serving', () async {
      final hub = MemoryBeaconHub();
      final solo = await startDevice(hub.a, 'Solo');
      await solo.controller.close();
      await solo.controller.close();
      expect(solo.controller.isServing, isFalse);
      expect(solo.controller.sessions, isEmpty);
    });
  });

  group('pairing two Devices', () {
    test('a typed code puts them in one group and starts them serving', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');

      await pairUp(alice, bob);

      expect(alice.controller.isPaired, isTrue);
      expect(bob.controller.isPaired, isTrue);
      expect(alice.controller.self.groupLength, 2);
      expect(bob.controller.self.groupLength, 2);
      expect(alice.controller.listenPort, isNotNull);
      expect(
        alice.controller.listenPort,
        isNot(bob.controller.listenPort),
        reason: 'two Devices on one host must not fight over a port',
      );

      // Each Device now knows the other by name, and knows it is in the group.
      await until(
        () => alice.controller.peers.any(
          (peer) => peer.alias == 'Bob' && peer.isInGroup,
        ),
        description: 'Alice to know Bob',
      );
      await until(
        () => bob.controller.peers.any(
          (peer) => peer.alias == 'Alice' && peer.isInGroup,
        ),
        description: 'Bob to know Alice',
      );
    });

    test('a code that does not match the invitation pairs nobody', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');

      final invitation = await alice.controller.invite();
      final wrong = PairingSecret.generateCode();
      expect(wrong, isNot(invitation.code));

      await expectLater(
        bob.controller.join(
          host: InternetAddress.loopbackIPv4.address,
          code: wrong,
          port: invitation.port,
        ),
        throwsA(isA<PairingException>()),
      );
      expect(alice.controller.isPaired, isFalse);
      expect(bob.controller.isPaired, isFalse);
      await invitation.cancel();
    });

    test('renaming keeps the group and changes what is announced', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);

      await alice.controller.rename('Alice (laptop)');

      expect(alice.controller.self.alias, 'Alice (laptop)');
      expect(
        alice.controller.isPaired,
        isTrue,
        reason: 'a new name must not cost the group',
      );
      expect(alice.controller.self.groupLength, 2);
      await until(
        () => alice.controller.isServing,
        description: 'Alice to serve again under her new name',
      );
      await until(
        () =>
            bob.controller.peers.any((peer) => peer.alias == 'Alice (laptop)'),
        description: 'Bob to hear the new name',
      );
    });
  });

  group('transfers between two paired Devices', () {
    late MemoryBeaconHub hub;
    late TestDevice alice;
    late TestDevice bob;

    setUp(() async {
      hub = MemoryBeaconHub();
      alice = await startDevice(hub.a, 'Alice');
      bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);
      await connect(alice, bob);
    });

    test('text travels, and both sides settle', () async {
      final sent = await alice.controller.sendText('hello from Alice');
      expect(sent.text, 'hello from Alice');

      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered a Transfer',
      );
      final offer = bob.offers.single;
      expect(offer.kind, PayloadKind.text);
      expect(offer.text, 'hello from Alice');
      expect(offer.state, TransferState.awaitingDecision);
      expect(offer.direction, TransferDirection.incoming);

      // The offer is visible to a UI, and undecided, before anybody answers it.
      final pending = bob.controller.transfers.single;
      expect(pending.needsDecision, isTrue);
      expect(pending.offer, same(offer));
      expect(pending.peer, alice.fingerprint);
      expect(alice.controller.transfers.single.peer, bob.fingerprint);

      await bob.controller.acceptInto(
        offer,
        tempDirectory('local-transfer-in-'),
      );

      await until(
        () =>
            offer.state == TransferState.completed &&
            sent.state == TransferState.completed,
        description: 'both sides to settle as completed',
      );
      expect(bob.controller.transfers.single.needsDecision, isFalse);
    });

    test('a file arrives byte for byte, across several chunks', () async {
      final home = tempDirectory('local-transfer-out-');
      final source = File('${home.path}${Platform.pathSeparator}payload.bin');
      // Larger than one chunk, so this exercises framing and reassembly and
      // not just a single message.
      final bytes = Uint8List.fromList(
        List.generate(200 * 1024, (index) => (index * 31) % 256),
      );
      source.writeAsBytesSync(bytes);

      final sent = await alice.controller.sendFile(source);

      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      final offer = bob.offers.single;
      expect(offer.kind, PayloadKind.file);
      final item = offer.items.single;
      expect(item.name, 'payload.bin');
      expect(item.size, bytes.length);
      expect(item.hasDigest, isTrue);
      expect(bob.controller.transfers.single.names, ['payload.bin']);

      final incoming = tempDirectory('local-transfer-in-');
      await bob.controller.acceptInto(offer, incoming);
      await until(
        () =>
            offer.state == TransferState.completed &&
            sent.state == TransferState.completed,
        description: 'both sides to settle as completed',
      );

      final written = File(
        '${incoming.path}${Platform.pathSeparator}payload.bin',
      );
      expect(written.existsSync(), isTrue);
      expect(written.readAsBytesSync(), bytes);
    });

    test('a refused offer is reported to the sender', () async {
      final sent = await alice.controller.sendText('not wanted');
      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered a Transfer',
      );

      await bob.controller.reject(bob.offers.single, RejectionReason.declined);

      await until(
        () => sent.state.isSettled,
        description: 'Alice to hear the refusal',
      );
      expect(await sent.outcome, isA<TransferRejected>());
      expect(bob.controller.transfers.single.state, TransferState.rejected);
    });

    test(
      'a peer this Device never learned an address for cannot be dialled',
      () async {
        await expectLater(
          alice.controller.connect(fingerprintOf('a stranger')),
          throwsA(isA<AppStateException>()),
        );
      },
    );

    test('sending does not answer an offer on the user behalf', () async {
      await alice.controller.sendText('first');
      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered a Transfer',
      );
      // Nothing has moved on Bob's side: the bytes are the sender's problem
      // until the user says yes.
      expect(bob.offers.single.state, TransferState.awaitingDecision);
      expect(bob.offers.single.transferredBytes, 0);
    });
  });

  group('clipboard mirroring inside the group', () {
    test('a copy travels to a peer that mirrors', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);
      await connect(alice, bob);

      alice.controller.setClipboardMode(ClipboardMode.mirror);
      bob.controller.setClipboardMode(ClipboardMode.mirror);

      alice.clipboard.copy('copied on Alice');

      await until(
        () => bob.clipboard.applied.contains('copied on Alice'),
        description: 'Bob to apply the mirrored entry',
      );
      expect(await bob.clipboard.read(), 'copied on Alice');
    });

    test('a staged entry waits for the user', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);
      await connect(alice, bob);

      alice.controller.setClipboardMode(ClipboardMode.mirror);
      bob.controller.setClipboardMode(ClipboardMode.stage);

      alice.clipboard.copy('review me');

      await until(
        () => bob.controller.stagedEntries.isNotEmpty,
        description: 'Bob to have a staged entry',
      );
      expect(
        bob.clipboard.applied,
        isEmpty,
        reason: 'a staged entry must not touch the clipboard on its own',
      );

      await bob.controller.applyStaged(bob.controller.stagedEntries.single);
      expect(bob.clipboard.applied, contains('review me'));
    });

    test('nothing travels while the clipboard is off', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);
      await connect(alice, bob);

      expect(alice.controller.clipboardMode, ClipboardMode.off);
      expect(bob.controller.clipboardMode, ClipboardMode.off);
      alice.clipboard.copy('private');

      // Nothing to wait *for*, so this settles the queue and then asserts.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bob.clipboard.applied, isEmpty);
      expect(bob.controller.stagedEntries, isEmpty);
    });
  });

  group('reaching a Device by Manual Address', () {
    test(
      'dials a Device Discovery never placed, and a Transfer lands',
      () async {
        // Two separate beacon networks: neither Device can discover the other,
        // which is the case a Manual Address exists for.
        final alice = await startDevice(MemoryBeaconHub().a, 'Alice');
        final bob = await startDevice(MemoryBeaconHub().a, 'Bob');
        await pairUp(alice, bob);

        expect(
          alice.controller.peers.any((peer) => peer.isDiallable),
          isFalse,
          reason: 'nothing has been discovered to dial',
        );
        await expectLater(
          alice.controller.connect(bob.fingerprint),
          throwsA(isA<AppStateException>()),
        );

        final port = bob.controller.listenPort;
        expect(port, isNotNull);
        await alice.controller.connectTo(
          address: InternetAddress.loopbackIPv4.address,
          port: port,
        );
        await until(
          () =>
              alice.controller.sessions.isNotEmpty &&
              bob.controller.sessions.isNotEmpty,
          description: 'the Session to come up on both Devices',
        );
        expect(
          alice.controller.peers
              .firstWhere((peer) => peer.isConnected)
              .fingerprint,
          bob.fingerprint,
          reason: 'the Device on the other end is the one that was dialled',
        );

        await alice.controller.sendText('over a typed address');
        await until(
          () => bob.offers.isNotEmpty,
          description: 'Bob to be offered the text',
        );
        expect(bob.offers.single.text, 'over a typed address');
      },
    );

    test('refuses an address to dial when there is none', () async {
      final solo = await startDevice(MemoryBeaconHub().a, 'Solo');
      await expectLater(
        solo.controller.connectTo(
          address: InternetAddress.loopbackIPv4.address,
        ),
        throwsA(isA<AppStateException>()),
        reason: 'an unpaired Device has no secret, so it dials on none',
      );

      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);

      await expectLater(
        alice.controller.connectTo(address: '   '),
        throwsA(isA<AppStateException>()),
      );
      await expectLater(
        alice.controller.connectTo(
          address: InternetAddress.loopbackIPv4.address,
          port: 0,
        ),
        throwsA(isA<AppStateException>()),
      );
      await expectLater(
        alice.controller.connectTo(
          address: InternetAddress.loopbackIPv4.address,
          port: 70000,
        ),
        throwsA(isA<AppStateException>()),
      );
    });

    test('still refuses a Device that holds no other group secret', () async {
      // Two Owner Groups on one host. Carol typed Bob's address — which is the
      // only thing a Manual Address gives up, since nothing is pinned — so the
      // handshake is what has to refuse her.
      final alice = await startDevice(MemoryBeaconHub().a, 'Alice');
      final bob = await startDevice(MemoryBeaconHub().a, 'Bob');
      await pairUp(alice, bob);
      final carol = await startDevice(MemoryBeaconHub().a, 'Carol');
      final dave = await startDevice(MemoryBeaconHub().a, 'Dave');
      await pairUp(carol, dave);

      await expectLater(
        carol.controller.connectTo(
          address: InternetAddress.loopbackIPv4.address,
          port: bob.controller.listenPort,
        ),
        throwsA(isA<HandshakeException>()),
      );
      expect(carol.controller.sessions, isEmpty);
      expect(bob.controller.sessions, isEmpty);
    });
  });
}

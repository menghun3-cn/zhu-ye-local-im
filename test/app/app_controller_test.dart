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
  String? defaultIncomingDirectory,
  MessageStore? messageStore,
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
    // Null unless a test says otherwise, and null is a real answer here: a
    // platform that offers no folder is the one case where an image is still
    // asked about rather than filed on arrival.
    defaultIncomingDirectory: defaultIncomingDirectory,
    // Null as well by default, which is what every other test in this file
    // wants: with no store there is no conversation to keep, and the live
    // list is the whole of it. A test about history hands in a store it keeps,
    // and then stands a second Device up over the same one — which is a
    // restart, as far as the conversation is concerned.
    messageStore: messageStore,
  );
  await controller.start();
  addTearDown(controller.close);
  final device = TestDevice(controller, clipboard);
  device.recordOffers();
  return device;
}

/// Runs the Pairing two people now do: [host] answers requests, [guest] picks it
/// out of its list, and the host's user allows it.
///
/// Both users confirm, as they would on two screens: allowing the request gets
/// the two Devices talking, and the confirmation is what turns that into
/// membership. The two halves are started before either is awaited — the dial
/// does not resolve until the other side allows it, which is the whole point of
/// the flow and would deadlock a sequential version.
Future<void> pairUp(TestDevice host, TestDevice guest) async {
  final request = host.controller.pairingRequests.first;
  final joinFuture = guest.controller.pairWith(
    host: InternetAddress.loopbackIPv4.address,
    port: host.controller.pairingPort,
  );
  final hostAttempt = await (await request).admit();
  final guestAttempt = await joinFuture;
  expect(
    hostAttempt.sas,
    guestAttempt.sas,
    reason: 'both Devices must derive the same digits to sign over',
  );
  await Future.wait([hostAttempt.confirm(), guestAttempt.confirm()]);
  await until(
    () => host.controller.isServing && guest.controller.isServing,
    description: 'both Devices to serve Sessions',
  );
}

/// Opens a Session from [from] to [to], once Discovery has placed [to].
///
/// Tolerates the Session already being up, and tolerates losing the race to get
/// there: since a discovered peer in the Owner Group is connected to
/// automatically, this dial may be a duplicate of one that has just happened,
/// and which of the two ends reaches the LinkManager first is not something a
/// test can or should pin down. Two shapes of "already connected" come back —
/// `AppStateException` when this Device had already wired the peer up, and
/// `HandshakeException` when the peer's dial beat ours to the same Session —
/// and a test that only wants to say "these two are talking" should not have to
/// care which one it got.
Future<void> connect(TestDevice from, TestDevice to) async {
  final target = to.fingerprint;
  await until(
    () =>
        from.controller.sessions.isNotEmpty ||
        from.controller.peers.any(
          (peer) => peer.fingerprint == target && peer.isDiallable,
        ),
    description: '${to.controller.self.alias} to be discovered with a port',
  );
  if (from.controller.sessions.isEmpty) {
    try {
      await from.controller.connect(target);
    } on AppStateException {
      // Already open, as this Device saw it.
    } on HandshakeException {
      // Already open, as the LinkManager saw it: the peer dialled us at the
      // same moment and its Session was established first.
    }
  }
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

/// Adds each Device to the other's clipboard-sharing whitelist.
///
/// Pairing alone shares no clipboard: being in the Owner Group says a Device
/// may hold a Session, and the whitelist is the separate, explicit decision to
/// let it read what is copied here. A test about sharing has to make that
/// decision, in both directions, the way two users would.
void shareClipboard(TestDevice a, TestDevice b) {
  a.controller.setClipboardPeer(b.fingerprint, value: true);
  b.controller.setClipboardPeer(a.fingerprint, value: true);
}

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

    test('a request the user refuses pairs nobody', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');

      final request = alice.controller.pairingRequests.first;
      final joinFuture = bob.controller.pairWith(
        host: InternetAddress.loopbackIPv4.address,
        port: alice.controller.pairingPort,
      );
      await (await request).refuse();

      // Which error depends on whether the refusal lands before or after the
      // caller's first message: a closed link ends the read, and a send onto a
      // link being torn down fails the handshake. Either way there is no
      // attempt to confirm, which is what the test is about.
      await expectLater(
        joinFuture,
        throwsA(anyOf(isA<PairingException>(), isA<HandshakeException>())),
      );
      expect(alice.controller.isPaired, isFalse);
      expect(bob.controller.isPaired, isFalse);
    });

    test(
      'turning requests off takes the listener down, and on brings it back',
      () async {
        final hub = MemoryBeaconHub();
        final alice = await startDevice(hub.a, 'Alice');

        expect(alice.controller.acceptsPairingRequests, isTrue);
        expect(alice.controller.isAcceptingPairings, isTrue);
        expect(alice.controller.pairingPort, isNotNull);

        await alice.controller.setAcceptsPairingRequests(false);

        expect(alice.controller.acceptsPairingRequests, isFalse);
        expect(
          alice.controller.isAcceptingPairings,
          isFalse,
          reason:
              'a Device that says it is not answering must not be listening',
        );
        expect(alice.controller.pairingPort, isNull);

        await alice.controller.setAcceptsPairingRequests(true);

        expect(alice.controller.acceptsPairingRequests, isTrue);
        expect(alice.controller.isAcceptingPairings, isTrue);
        expect(alice.controller.pairingPort, isNotNull);
      },
    );

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
      // 这条断言盯的不只是「Bob 收到广播了」，而是**谁赢**：Bob 与 Alice 之间
      // 那条 Session 的握手是在改名之前做的，握手里的名字**在 Session 活着期间
      // 不会变**。所以只要那条 Session 还挂着，一个「后写的来源覆盖先写的」的
      // 合并顺序就会把 Alice 的新名字盖回旧名字，而 Bob 会一直显示旧名。
      // 这条用例因此在 Session 恰好先掉线时绿、恰好后掉线时红 —— 红才是真相，
      // 别把它当环境抖动放过去。
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

      // Nothing is offered for a decision: text is answered on arrival, so it
      // never reaches the stream a UI draws its prompts from.
      await until(
        () => sent.state.isSettled,
        description: 'the text to settle on both sides',
      );
      expect(
        bob.offers,
        isEmpty,
        reason: 'text is not a question, so nothing is offered',
      );

      final received = bob.controller.transfers.single;
      expect(received.kind, PayloadKind.text);
      expect(received.text, 'hello from Alice');
      expect(received.direction, TransferDirection.incoming);
      expect(received.state, TransferState.completed);
      expect(
        received.needsDecision,
        isFalse,
        reason: 'nothing about a text needs deciding',
      );
      expect(received.offer, isNull);
      expect(received.peer, alice.fingerprint);
      expect(alice.controller.transfers.single.peer, bob.fingerprint);
      expect(sent.state, TransferState.completed);
    });

    test('text arrives with nothing written to disk', () async {
      // The whole reason text needs no prompt: there is no answer to give.
      // Accepting one opens no sink and names no directory, so an offer of text
      // is settled by the controller alone.
      final sent = await alice.controller.sendText('no files here');
      await until(
        () => sent.state.isSettled,
        description: 'the text to settle',
      );

      final received = bob.controller.transfers.single;
      expect(received.kind, PayloadKind.text);
      // A text offer's item carries its body inline, so it has no digest and
      // therefore no byte stream to write anywhere.
      for (final name in received.names) {
        expect(name, isNotEmpty);
      }
      expect(received.totalBytes, greaterThan(0));
      expect(received.transferredBytes, received.totalBytes);
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
      final written = File(
        '${incoming.path}${Platform.pathSeparator}payload.bin',
      );
      // The file appears once its bytes have been verified and moved out of the
      // staging name the receive wrote them under.
      await until(
        () =>
            offer.state == TransferState.completed &&
            sent.state == TransferState.completed &&
            written.existsSync(),
        description: 'both sides to settle as completed and the file to land',
      );

      expect(written.readAsBytesSync(), bytes);
      expect(
        incoming.listSync().map((entry) => fileNameOf(entry.path)),
        ['payload.bin'],
        reason:
            'the staging name the bytes were written under is gone once '
            'they have a name of their own',
      );
    });

    test('a receive that dies leaves no file, and frees its name', () async {
      // Writing straight to the final name made a dead Transfer look like a
      // received file: an empty "report.pdf" nobody could open, and — worse —
      // an occupied name, so the next attempt at the same file came out as
      // "report (2).pdf" beside it. The bytes are staged under a name of this
      // Device's own making now, and a Transfer that dies takes that name with
      // it.
      final home = tempDirectory('local-transfer-abandon-out-');
      final source = File('${home.path}${Platform.pathSeparator}report.pdf');
      // Several chunks, so the receive is genuinely still in flight when it is
      // given up on rather than a race this test might lose.
      final bytes = Uint8List.fromList(
        List<int>.generate(2 * 1024 * 1024, (index) => (index * 13) % 256),
      );
      source.writeAsBytesSync(bytes);

      final sent = await alice.controller.sendFile(source);
      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      final offer = bob.offers.single;

      final incoming = tempDirectory('local-transfer-abandon-in-');
      await bob.controller.acceptInto(offer, incoming);
      // Give up at once, which is what a cancel from either end looks like from
      // this side of the wire.
      await offer.cancel();
      // The outcomes, not the states: the sender finishing with the Transfer is
      // what releases the handle on the file it was sending, and a state that
      // has settled does not promise that yet.
      await Future.wait([offer.outcome, sent.outcome]);
      expect(offer.state, TransferState.cancelled);
      await until(
        () => incoming.listSync().isEmpty,
        description: 'the half-written file to be cleared away',
      );

      // Retry the same file. The name it asks for is still free, which is what
      // the staging name bought.
      final retry = await alice.controller.sendFile(source);
      await until(
        () => bob.offers.length == 2,
        description: 'Bob to be offered it again',
      );
      await bob.controller.acceptInto(bob.offers.last, incoming);
      final published = File(
        '${incoming.path}${Platform.pathSeparator}report.pdf',
      );
      await until(
        () => published.existsSync(),
        description: 'the retry to land',
      );
      await retry.outcome;
      expect(retry.state, TransferState.completed);

      expect(incoming.listSync().map((entry) => fileNameOf(entry.path)), [
        'report.pdf',
      ], reason: 'the attempt that never arrived must not occupy the name');
      expect(published.readAsBytesSync(), bytes);
    });

    test('a received picture keeps a path worth drawing', () async {
      // The conversation draws an image message from `localPath`, and an image
      // arrives in two halves: the offer first (no bytes, nothing to draw) and
      // the bytes only once the user has answered. This is the join between
      // them — a landed picture that no longer had a path would be a bubble
      // showing a file name for the rest of the conversation's life.
      final home = tempDirectory('local-transfer-picture-out-');
      final source = File('${home.path}${Platform.pathSeparator}photo.png');
      final bytes = Uint8List.fromList(
        List<int>.generate(64, (index) => (index * 5) % 256),
      );
      source.writeAsBytesSync(bytes);

      await alice.controller.sendImage(source);

      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the picture',
      );
      final offer = bob.offers.single;
      expect(offer.kind, PayloadKind.image);
      expect(
        bob.controller.transfers.single.localPath,
        isNull,
        reason: 'the bytes have not arrived, so there is nothing to draw yet',
      );

      final incoming = tempDirectory('local-transfer-picture-in-');
      await bob.controller.acceptInto(offer, incoming);
      expect(
        bob.controller.transfers.single.localPath,
        isNull,
        reason:
            'the answer is on the wire but the bytes are not here yet, so '
            'a path now would name a file that is empty or half written',
      );
      await until(
        () =>
            offer.state == TransferState.completed &&
            bob.controller.transfers.single.localPath != null,
        description: 'the picture to land under its own name',
      );

      final landed = bob.controller.transfers.single.localPath;
      expect(landed, isNotNull, reason: 'the receiver now has a picture');
      expect(File(landed!).readAsBytesSync(), bytes);
      // And the sender's own bubble points at the file it was asked to send,
      // which is what makes both sides of the conversation draw the same thing.
      expect(alice.controller.transfers.single.localPath, source.path);
    });

    test('a refused offer is reported to the sender', () async {
      // A file, because it is the kind that still waits: text is accepted on
      // arrival and so can never be refused.
      final home = tempDirectory('local-transfer-out-');
      final source = File('${home.path}${Platform.pathSeparator}unwanted.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      final sent = await alice.controller.sendFile(source);

      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
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

    test('a file is not accepted on the user behalf', () async {
      final home = tempDirectory('local-transfer-out-');
      final source = File('${home.path}${Platform.pathSeparator}waiting.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      final sent = await alice.controller.sendFile(source);

      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered a Transfer',
      );
      // Nothing has moved on Bob's side: the bytes are the sender's problem
      // until the user says yes, and where they land is the user's to say.
      expect(bob.offers.single.state, TransferState.awaitingDecision);
      expect(bob.offers.single.transferredBytes, 0);
      expect(bob.controller.transfers.single.needsDecision, isTrue);

      // Refused before this test ends, so the sender lets go of the file it is
      // holding open: an undecided Transfer keeps the source handle, and the
      // teardown that deletes the directory would then fail on Windows.
      // `outcome` is awaited rather than a state, because it is the sender
      // finishing with the Transfer — which is what releases the handle — and
      // not merely the state it lands in.
      final offered = bob.offers.single;
      await bob.controller.reject(offered);
      await sent.outcome;
      expect(offered.state.isSettled, isTrue);
    });

    test('text is accepted on the arrival, and never offered', () async {
      // The other half of the same rule, stated from the other side: what the
      // user would have been asked about text is a question with no answer, so
      // the controller answers it and no prompt is ever drawn.
      final sent = await alice.controller.sendText('goes straight through');
      await until(
        () => sent.state.isSettled,
        description: 'the text to settle',
      );

      expect(bob.offers, isEmpty, reason: 'there was nothing to ask');
      expect(bob.controller.transfers.single.state, TransferState.completed);
      expect(bob.controller.transfers.single.offer, isNull);
    });

    test('an image with nowhere to go is asked about after all', () async {
      // An image is the case that looks like a file and behaves like a text: it
      // does stream bytes and does land on disk, but the folder is not a
      // question the arrival raises — it is a setting this Device already has.
      // Both Devices here were started with no default folder, which is the one
      // configuration where that stops being true, so this test is the fallback:
      // with nowhere to write, the picture is asked about like a file.
      final home = tempDirectory('local-transfer-image-out-');
      final source = File('${home.path}${Platform.pathSeparator}photo.png');
      source.writeAsBytesSync(
        List<int>.generate(24, (index) => (index * 3) % 256),
      );

      final sent = await alice.controller.sendImage(source);

      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be asked about the picture',
      );
      expect(bob.offers.single.kind, PayloadKind.image);
      expect(bob.controller.transfers.single.needsDecision, isTrue);

      final inbox = tempDirectory('local-transfer-image-in-');
      await bob.controller.acceptInto(bob.offers.single, inbox);
      await until(
        () => sent.state == TransferState.completed,
        description: 'the transfer to finish once it is answered',
      );
    });
  });

  group('an image with somewhere to go', () {
    late MemoryBeaconHub hub;
    late TestDevice alice;
    late TestDevice bob;
    late Directory inbox;

    setUp(() async {
      hub = MemoryBeaconHub();
      inbox = tempDirectory('local-transfer-image-inbox-');
      alice = await startDevice(hub.a, 'Alice');
      // Bob is told where things go, the way the Windows build is told
      // Downloads. That is the whole difference between an image and a file: an
      // image has an answer already and a file does not.
      bob = await startDevice(
        hub.b,
        'Bob',
        defaultIncomingDirectory: inbox.path,
      );
      await pairUp(alice, bob);
      await connect(alice, bob);
    });

    test('an image lands without the user being asked', () async {
      final home = tempDirectory('local-transfer-image-out-');
      final source = File('${home.path}${Platform.pathSeparator}photo.png');
      final bytes = Uint8List.fromList(
        List<int>.generate(96, (index) => (index * 7) % 256),
      );
      source.writeAsBytesSync(bytes);

      final sent = await alice.controller.sendImage(source);

      await until(
        () => sent.state == TransferState.completed,
        description: 'the picture to arrive with nobody answering anything',
      );
      expect(
        bob.offers,
        isEmpty,
        reason: 'an image is not a question, so nothing is offered',
      );

      final received = bob.controller.transfers.single;
      expect(received.kind, PayloadKind.image);
      expect(received.state, TransferState.completed);
      expect(received.needsDecision, isFalse);
      expect(received.offer, isNull);

      // Both halves of what the conversation needs: a path to draw from, and
      // bytes on disk that hash to what was sent. The path does not appear the
      // instant the Transfer completes — the bytes are moved out of their
      // staging name first, and the conversation waits the moment out.
      await until(
        () => bob.controller.transfers.single.localPath != null,
        description: 'the picture to be published under its own name',
      );
      final landed = bob.controller.transfers.single.localPath;
      expect(landed, isNotNull, reason: 'the receiver can draw it');
      expect(File(landed!).readAsBytesSync(), bytes);
      expect(
        File(landed).parent.path,
        inbox.path,
        reason: 'it goes where this Device already puts received things',
      );
      // The sender named the file; where it lands is this side's setting.
      expect(fileNameOf(landed), 'photo.png');
    });

    test('a folder the user chose wins over the platform default', () async {
      final chosen = tempDirectory('local-transfer-image-chosen-');
      await bob.controller.setIncomingDirectory(chosen.path);

      final home = tempDirectory('local-transfer-image-out-');
      final source = File('${home.path}${Platform.pathSeparator}holiday.png');
      source.writeAsBytesSync(List<int>.generate(32, (index) => index));

      final sent = await alice.controller.sendImage(source);
      await until(
        () => sent.state.isSettled,
        description: 'the picture to arrive',
      );
      await until(
        () => bob.controller.transfers.single.localPath != null,
        description: 'the picture to be published under its own name',
      );

      final landed = bob.controller.transfers.single.localPath;
      expect(landed, isNotNull);
      expect(
        File(landed!).parent.path,
        chosen.path,
        reason: 'the setting the user made beats the one the platform offered',
      );
    });
  });

  group('clipboard mirroring inside the group', () {
    test('a copy travels to a peer that mirrors', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);
      await connect(alice, bob);
      shareClipboard(alice, bob);

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
      shareClipboard(alice, bob);

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

    test('a staged entry announces itself, so a screen can redraw', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);
      await connect(alice, bob);
      shareClipboard(alice, bob);

      alice.controller.setClipboardMode(ClipboardMode.mirror);
      bob.controller.setClipboardMode(ClipboardMode.stage);

      // `changes` is this controller's whole contract with a screen: it fires
      // whenever something a screen renders has changed. A staged entry *is*
      // something a screen renders — it is the list the user answers — so it
      // has to fire one. A surface that only redrew when something unrelated
      // happened would leave the entry invisible until the user navigated away
      // and came back, which is indistinguishable from it never arriving.
      var ticks = 0;
      final watch = bob.controller.changes.listen((_) => ticks++);
      addTearDown(watch.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final before = ticks;

      alice.clipboard.copy('announce me');
      await until(
        () => bob.controller.stagedEntries.isNotEmpty,
        description: 'Bob to have a staged entry',
      );
      // The list can land a tick before the announcement does, so this waits
      // for the announcement rather than asserting on one instant.
      await until(
        () => ticks > before,
        description: 'Bob to announce the staged entry',
      );
      expect(bob.controller.stagedEntries.single.text, 'announce me');
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

  group('connecting to a peer as soon as it is discovered', () {
    test('a discovered peer in the group gets a Session with no tap', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);

      // Nothing below this line asks for a connection. Both Devices discover
      // each other and dial on their own; the two dials race, and the loser is
      // refused by the LinkManager for a Session that already exists.
      await until(
        () =>
            alice.controller.sessions.isNotEmpty &&
            bob.controller.sessions.isNotEmpty,
        description: 'both Devices to connect without being asked',
      );
      expect(alice.controller.sessions, hasLength(1));
      expect(bob.controller.sessions, hasLength(1));
    });

    test('a peer outside the group is not connected to', () async {
      final hub = MemoryBeaconHub();
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob');
      // Both are on the same beacon network, so each sees the other. Neither
      // is in the other's Owner Group, so neither may dial: an unpaired Device
      // needs its user's consent, and there is no secret to handshake with.
      await until(
        () => alice.controller.peers.any((peer) => peer.alias == 'Bob'),
        description: 'Alice to see Bob',
      );
      // Alice's own connection is the point of asking whether she has one: a
      // few discovery rounds have gone by at this point.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(alice.controller.sessions, isEmpty);
      expect(bob.controller.sessions, isEmpty);
    });
  });

  group('the clipboard-sharing whitelist', () {
    late MemoryBeaconHub hub;
    late TestDevice alice;
    late TestDevice bob;

    setUp(() async {
      hub = MemoryBeaconHub();
      alice = await startDevice(hub.a, 'Alice');
      bob = await startDevice(hub.b, 'Bob');
      await pairUp(alice, bob);
      await connect(alice, bob);
      alice.controller.setClipboardMode(ClipboardMode.mirror);
      bob.controller.setClipboardMode(ClipboardMode.mirror);
    });

    test('a paired peer shares nothing until it is added', () async {
      // The whole point of the gate, stated from the controller: pairing is a
      // Session, not a grant to read the clipboard.
      expect(alice.controller.isClipboardPeer(bob.fingerprint), isFalse);
      expect(bob.controller.isClipboardPeer(alice.fingerprint), isFalse);

      alice.clipboard.copy('not for Bob');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bob.clipboard.applied, isEmpty);
      expect(bob.controller.stagedEntries, isEmpty);
    });

    test('adding a peer one way is still not enough', () async {
      // Consent is per Device. Bob has added Alice, Alice has not added Bob:
      // Bob's clipboard would go out, Alice's must not.
      shareClipboard(alice, bob);
      alice.controller.setClipboardPeer(bob.fingerprint, value: false);

      alice.clipboard.copy('still not for Bob');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bob.clipboard.applied, isEmpty, reason: 'Alice never said yes');
    });

    test('a copy travels once both sides have added each other', () async {
      shareClipboard(alice, bob);

      alice.clipboard.copy('for Bob after all');
      await until(
        () => bob.clipboard.applied.contains('for Bob after all'),
        description: 'Bob to apply the mirrored entry',
      );
      expect(await bob.clipboard.read(), 'for Bob after all');
    });

    test(
      'adding a peer again is not a change, so nothing is punished',
      () async {
        shareClipboard(alice, bob);
        // Idempotent: a second tick must not disturb the Session or the
        // clipboard, and must not be mistaken for a fresh grant.
        shareClipboard(alice, bob);
        expect(alice.controller.isClipboardPeer(bob.fingerprint), isTrue);
        expect(alice.controller.sessions, isNotEmpty);

        alice.clipboard.copy('after a double tick');
        await until(
          () => bob.clipboard.applied.contains('after a double tick'),
          description: 'Bob to apply the entry',
        );
      },
    );
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
          () =>
              bob.controller.transfers.isNotEmpty &&
              bob.controller.transfers.single.state.isSettled,
          description: 'Bob to receive the text',
        );
        expect(bob.controller.transfers.single.text, 'over a typed address');
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

  group('the conversation outlives the process', () {
    late MemoryBeaconHub hub;
    late MemoryMessageStore kept;

    setUp(() {
      hub = MemoryBeaconHub();
      kept = MemoryMessageStore();
    });

    /// Two paired Devices, the second of which keeps its conversation in
    /// [kept], and a Session already up between them.
    ///
    /// The store is the only part of a Device that survives a restart, so
    /// handing the same one to a second Device is what a restart *is* on one
    /// host, and it is how the tests below assert that a message comes back.
    ///
    /// The Session is dialled rather than left to the automatic connect a
    /// discovered group member gets: pairing says a Device *may* hold a
    /// Session, and every test here sends the moment it is paired, so one that
    /// arrived before the dial won would fail on `noPeerConnected` — about the
    /// weather rather than about the conversation.
    Future<(TestDevice, TestDevice)> paired() async {
      final alice = await startDevice(hub.a, 'Alice');
      final bob = await startDevice(hub.b, 'Bob', messageStore: kept);
      await pairUp(alice, bob);
      await connect(alice, bob);
      return (alice, bob);
    }

    /// The conversation as a restart would read it, once [done] holds.
    ///
    /// Polled rather than awaited, because archiving happens inside the
    /// callback that ends a Transfer and nothing hands out a future for it:
    /// what a test can wait for is the file, and this waits for the file.
    Future<List<MessageRecord>> remembered(
      bool Function(List<MessageRecord> messages) done, {
      String description = 'the conversation to be written out',
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var messages = await loadMessages(kept);
      while (!done(messages) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        messages = await loadMessages(kept);
      }
      expect(done(messages), isTrue, reason: '$description: $messages');
      return messages;
    }

    test('a message that settled is still there after a restart', () async {
      final (alice, bob) = await paired();

      final sent = await alice.controller.sendText('see you at six');
      await until(
        () => sent.state.isSettled && bob.controller.transfers.length == 1,
        description: 'the text to settle on both sides',
      );
      expect(
        (await remembered((messages) => messages.isNotEmpty)).single.text,
        'see you at six',
      );

      // The restart. The old Device is stopped first so that two Devices are
      // not announcing themselves on one transport at the same time.
      await bob.controller.close();
      final restarted = await startDevice(hub.b, 'Bob', messageStore: kept);

      final restored = restarted.controller.transfers.single;
      expect(restored.text, 'see you at six');
      expect(restored.kind, PayloadKind.text);
      expect(restored.direction, TransferDirection.incoming);
      expect(restored.state, TransferState.completed);
      expect(restored.peer, alice.fingerprint);
      expect(restored.at, isNotNull);
      expect(
        restored.settledAt,
        isNotNull,
        reason: 'a message that ended says when, or a duration is unprintable',
      );
      expect(
        restored.offer,
        isNull,
        reason: 'nothing about a remembered message is still a question',
      );
      expect(restored.send, isNull);
      expect(restored.localPath, isNull, reason: 'a text has no file');
    });

    test(
      'deleting a message takes it off the screen and off the disk',
      () async {
        final (alice, bob) = await paired();
        final sent = await alice.controller.sendText('forget me');
        await until(
          () => sent.state.isSettled && bob.controller.transfers.length == 1,
          description: 'the text to settle',
        );
        await remembered((messages) => messages.isNotEmpty);

        await bob.controller.deleteMessage(bob.controller.transfers.single);

        expect(bob.controller.transfers, isEmpty);
        expect(
          await loadMessages(kept),
          isEmpty,
          reason: 'a message that came back after a restart was not deleted',
        );
        // And the peer is told nothing: deleting is about this Device's record.
        expect(
          alice.controller.transfers.single.state,
          TransferState.completed,
        );
      },
    );

    test('deleting one message leaves the rest of the conversation', () async {
      final (alice, bob) = await paired();
      final first = await alice.controller.sendText('the first one');
      await until(
        () => first.state.isSettled,
        description: 'the first text to settle',
      );
      final second = await alice.controller.sendText('the second one');
      await until(
        () => second.state.isSettled && bob.controller.transfers.length == 2,
        description: 'the second text to settle',
      );
      await remembered((messages) => messages.length == 2);

      // Newest first, which is how a conversation is drawn.
      expect(bob.controller.transfers.first.text, 'the second one');
      await bob.controller.deleteMessage(bob.controller.transfers.first);

      final left = bob.controller.transfers.single;
      expect(left.text, 'the first one');
      expect(
        [for (final message in await loadMessages(kept)) message.text],
        ['the first one'],
      );
    });

    test('a question nobody answered is not remembered', () async {
      // An ending is what makes a message history. An offer still waiting is a
      // connection's state, and the connection does not outlive the process —
      // so restoring one would put a question on screen that nobody, on either
      // end, is waiting for an answer to.
      final (alice, bob) = await paired();
      final home = tempDirectory('local-transfer-history-out-');
      final source = File('${home.path}${Platform.pathSeparator}payload.bin')
        ..writeAsBytesSync(List<int>.filled(1024, 7));

      final sending = alice.controller.sendFile(source);
      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );

      expect(bob.controller.transfers.single.needsDecision, isTrue);
      expect(await loadMessages(kept), isEmpty);

      // Answered, and the sender waited out to its own ending: an unanswered
      // Transfer holds its source file open, and the teardown that deletes the
      // directory it lives in cannot run while it does.
      await bob.controller.reject(bob.offers.single);
      await (await sending).outcome;

      // A refusal is an ending too, so this one *is* remembered — which is the
      // other half of the rule: what is not remembered is a question still
      // waiting for an answer, not every Transfer that went wrong.
      expect(await loadMessages(kept), isNotEmpty);
    });

    test('a message deleted while it was still moving stays deleted', () async {
      final (alice, bob) = await paired();
      final home = tempDirectory('local-transfer-history-out-');
      final source = File('${home.path}${Platform.pathSeparator}payload.bin')
        ..writeAsBytesSync(List<int>.filled(1024, 9));

      final sending = alice.controller.sendFile(source);
      await until(
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );

      // Deleted before it was answered. The Transfer keeps running — stopping
      // it is the cancel action, not this one — so its ending arrives after
      // the delete, and the ending must not put the message back.
      await bob.controller.deleteMessage(bob.controller.transfers.single);
      expect(bob.controller.transfers, isEmpty);

      await bob.controller.reject(bob.offers.single);
      // Waited out to the sender's own ending, so the source file it holds
      // open is released before the test tears its directory down.
      await (await sending).outcome;
      await until(
        () => bob.offers.single.isSettled,
        description: 'the rejected Transfer to have ended',
      );
      // The ending is handled in a callback of its own, so give it the moment
      // it needs before asking what it did.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        bob.controller.transfers,
        isEmpty,
        reason: 'the ending of a deleted message must not restore it',
      );
      expect(await loadMessages(kept), isEmpty);
    });

    test('the record is bounded, and drops the oldest first', () async {
      // Pre-loaded, because filling it honestly would mean sending a thousand
      // messages, and what is under test is the ceiling rather than the send.
      final base = DateTime.utc(2026, 10, 10);
      await saveMessages([
        for (var index = 0; index < maxRememberedMessages + 5; index++)
          MessageRecord(
            peer: fingerprintOf('Peer $index'),
            id: 'm$index',
            direction: TransferDirection.incoming,
            kind: PayloadKind.text,
            at: base.add(Duration(seconds: index)),
            settledAt: base.add(Duration(seconds: index + 1)),
            state: TransferState.completed,
            names: const ['text'],
            totalBytes: 1,
            text: 'message $index',
          ),
      ], kept);
      expect((await loadMessages(kept)).length, maxRememberedMessages + 5);

      final (alice, bob) = await paired();
      final sent = await alice.controller.sendText('the newest one');
      await until(
        () => sent.state.isSettled,
        description: 'the text to settle',
      );
      // Archiving happens in the callback that ends the Transfer and trims to
      // the ceiling on the way through, so "the file holds exactly the ceiling
      // and its newest message is the one just sent" is what says it has run.
      final messages = await remembered(
        (messages) =>
            messages.length == maxRememberedMessages &&
            messages.last.text == 'the newest one',
        description: 'the record to be trimmed to its ceiling',
      );

      expect(messages.length, maxRememberedMessages);
      expect(messages.last.text, 'the newest one');
      // Six, not five: the pre-loaded list is already five over the ceiling, and
      // the message just sent is the sixth thing that has to go somewhere. The
      // ones that go are the ones that were already oldest, which is the end a
      // person has scrolled away from.
      expect(
        messages.first.text,
        'message 6',
        reason: 'the six that go are the six that were already oldest',
      );
      expect(bob.controller.transfers, isNotEmpty);
    });
  });
}

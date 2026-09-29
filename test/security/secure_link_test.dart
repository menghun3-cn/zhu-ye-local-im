import 'dart:io';
import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

PairingSecret _secret([int fill = 7]) =>
    PairingSecret.fromBytes(List.filled(32, fill));

final _deviceA = testDevice('device-a', listenPort: 51001);
final _deviceB = testDevice(
  'device-b',
  platform: DevicePlatform.android,
  listenPort: 51002,
);

void main() {
  group('handshake', () {
    test('both sides complete and learn each other', () async {
      final pair = MemoryTransportPair();
      final secret = _secret();
      final links = await Future.wait([
        SecureLink.establish(
          transport: pair.a,
          role: LinkRole.initiator,
          local: _deviceA,
          secret: secret,
        ),
        SecureLink.establish(
          transport: pair.b,
          role: LinkRole.responder,
          local: _deviceB,
          secret: secret,
        ),
      ]);
      final initiator = links[0];
      final responder = links[1];

      expect(initiator.role, LinkRole.initiator);
      expect(responder.role, LinkRole.responder);
      expect(initiator.peer.fingerprint, _deviceB.fingerprint);
      expect(responder.peer.fingerprint, _deviceA.fingerprint);
      expect(initiator.peer.alias, 'device-b');
      expect(initiator.peer.platform, DevicePlatform.android);
      expect(initiator.peer.listenPort, 51002);

      await initiator.close();
      await responder.close();
    });

    test('both sides derive the same short authentication string', () async {
      final links = await _connectedPair();
      expect(
        links.a.shortAuthenticationString,
        links.b.shortAuthenticationString,
      );
      expect(links.a.shortAuthenticationString, hasLength(6));
      expect(
        int.parse(links.a.shortAuthenticationString),
        inInclusiveRange(0, 999999),
      );
      await links.close();
    });

    test(
      'a different pairing secret derives a different short string',
      () async {
        final links = await _connectedPair(
          aSecret: _secret(1),
          bSecret: _secret(2),
        );
        expect(
          links.a.shortAuthenticationString,
          isNot(links.b.shortAuthenticationString),
        );
        await links.close();
      },
    );

    test('refuses a peer that claims this Device\'s own fingerprint', () async {
      final pair = MemoryTransportPair();
      final secret = _secret();
      const short = Duration(milliseconds: 300);
      final results = await Future.wait([
        SecureLink.establish(
          transport: pair.a,
          role: LinkRole.initiator,
          local: _deviceA,
          secret: secret,
          timeout: short,
        ).then<Object?>((link) => link).catchError((Object error) => error),
        SecureLink.establish(
          transport: pair.b,
          role: LinkRole.responder,
          local: _deviceA,
          secret: secret,
          timeout: short,
        ).then<Object?>((link) => link).catchError((Object error) => error),
      ]);
      // A Device that finds its own fingerprint on the other end is talking to
      // itself; no Session may be established in either direction.
      expect(results.whereType<SecureLink>(), isEmpty);
      expect(results.whereType<HandshakeException>(), isNotEmpty);
    });

    test('refuses an incompatible protocol version', () async {
      final pair = MemoryTransportPair();

      // A responder that answers correctly except for its protocol version.
      final incompatible = PeerHandshake(
        device: _deviceB,
        ephemeralPublicKey: Uint8List(32),
        nonce: Uint8List(32),
        protocolVersion: wireProtocolVersion + 1,
      );
      pair.b.incoming.listen((_) {
        pair.b.add(
          encodeFrame(ControlFrame(HelloAckMessage(incompatible).encode())),
        );
      });

      await expectLater(
        SecureLink.establish(
          transport: pair.a,
          role: LinkRole.initiator,
          local: _deviceA,
          secret: _secret(),
          timeout: const Duration(seconds: 2),
        ),
        throwsA(
          isA<HandshakeException>().having(
            (error) => error.message,
            'message',
            contains('protocol'),
          ),
        ),
      );
    });

    test('times out when the peer never answers', () async {
      final transport = MemoryTransportPair().a;
      await expectLater(
        SecureLink.establish(
          transport: transport,
          role: LinkRole.initiator,
          local: _deviceA,
          secret: _secret(),
          timeout: const Duration(milliseconds: 150),
        ),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('fails when the peer closes before answering', () async {
      final pair = MemoryTransportPair();
      final pending = SecureLink.establish(
        transport: pair.a,
        role: LinkRole.initiator,
        local: _deviceA,
        secret: _secret(),
      );
      await pair.b.close();
      await expectLater(pending, throwsA(isA<HandshakeException>()));
    });
  });

  group('secure session', () {
    test('carries a control message in both directions', () async {
      final links = await _connectedPair();
      final atB = MessageLog(links.b);
      final atA = MessageLog(links.a);

      await links.a.send(
        const OfferMessage(
          transferId: 't-1',
          kind: PayloadKind.text,
          items: [],
          text: 'hello from A',
        ),
      );
      await until(() => atB.messages.isNotEmpty, description: 'B收到 offer');
      final offer = atB.firstOf<OfferMessage>()!;
      expect(offer.text, 'hello from A');
      expect(offer.kind, PayloadKind.text);

      await links.b.send(
        const AcceptMessage(transferId: 't-1', acceptedItemIds: []),
      );
      await until(() => atA.messages.isNotEmpty, description: 'A收到 accept');
      expect(atA.firstOf<AcceptMessage>()!.transferId, 't-1');

      await links.close();
    });

    test('carries a chunk with binary bytes intact', () async {
      final links = await _connectedPair();
      final atB = MessageLog(links.b, listenToChunks: true);
      final payload = Uint8List.fromList(
        List<int>.generate(3000, (i) => (i * 31 + 7) % 256),
      );

      await links.a.sendChunk(
        transferId: 't-2',
        itemId: 'i-1',
        offset: 0,
        data: payload,
      );
      await until(() => atB.chunks.isNotEmpty, description: 'B收到 chunk');
      expect(atB.chunks.first.transferId, 't-2');
      expect(atB.chunks.first.itemId, 'i-1');
      expect(atB.chunks.first.offset, 0);
      expect(atB.chunks.first.data, payload);

      await links.close();
    });

    test('a payload larger than one TCP read still arrives whole', () async {
      final links = await _connectedPair();
      final atB = MessageLog(links.b, listenToChunks: true);
      final payload = Uint8List.fromList(
        List<int>.generate(256 * 1024, (i) => (i * 131 + 17) % 256),
      );

      await links.a.sendChunk(
        transferId: 't-3',
        itemId: 'i-1',
        offset: 0,
        data: payload,
      );
      await until(
        () => atB.chunks.isNotEmpty,
        description: 'B收到 256 KiB chunk',
      );
      expect(atB.chunks.first.data, payload);

      await links.close();
    });

    test('refuses to send after the link is closed', () async {
      final links = await _connectedPair();
      await links.a.close();
      await expectLater(
        links.a.send(
          const CancelMessage(
            transferId: 't',
            reason: RejectionReason.declined,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await links.b.close();
    });
  });

  group('authentication', () {
    test(
      'a peer that does not know the pairing secret cannot be understood',
      () async {
        final links = await _connectedPair(
          aSecret: _secret(1),
          bSecret: _secret(2),
        );
        final atB = MessageLog(links.b);

        await links.a.send(
          const OfferMessage(
            transferId: 't',
            kind: PayloadKind.text,
            items: [],
            text: 'should not be readable',
          ),
        );

        await until(() => atB.errors.isNotEmpty, description: 'B报告认证失败');
        expect(atB.errors.first, isA<ProtocolException>());
        expect(atB.messages, isEmpty);

        await links.close();
      },
    );

    test('a tampered record is rejected instead of delivered', () async {
      final pair = MemoryTransportPair();
      final tampered = _TamperingTransport(pair.a);
      final secret = _secret();

      final links = await Future.wait([
        SecureLink.establish(
          transport: tampered,
          role: LinkRole.initiator,
          local: _deviceA,
          secret: secret,
        ),
        SecureLink.establish(
          transport: pair.b,
          role: LinkRole.responder,
          local: _deviceB,
          secret: secret,
        ),
      ]);
      final atB = MessageLog(links[1]);

      tampered.arm();
      await links[0].send(
        const OfferMessage(
          transferId: 't',
          kind: PayloadKind.text,
          items: [],
          text: 'tamper me',
        ),
      );

      await until(() => atB.errors.isNotEmpty, description: 'B拒绝被篡改的记录');
      expect(atB.messages, isEmpty);

      await links[0].close();
      await links[1].close();
    });

    test('an unsealed frame after the handshake is refused', () async {
      final pair = MemoryTransportPair();
      final secret = _secret();
      final links = await Future.wait([
        SecureLink.establish(
          transport: pair.a,
          role: LinkRole.initiator,
          local: _deviceA,
          secret: secret,
        ),
        SecureLink.establish(
          transport: pair.b,
          role: LinkRole.responder,
          local: _deviceB,
          secret: secret,
        ),
      ]);
      final atB = MessageLog(links[1]);

      // Speak the framing layer directly, as an attacker would, skipping the
      // record layer the session requires.
      pair.a.add(
        encodeFrame(
          ControlFrame({'t': 'offer', 'tid': 'x', 'kind': 'text', 'items': []}),
        ),
      );

      await until(() => atB.errors.isNotEmpty, description: 'B拒收未加密帧');
      expect(atB.messages, isEmpty);

      await links[0].close();
      await links[1].close();
    });
  });

  group('over a real socket', () {
    late ServerSocket server;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      await server.close();
    });

    test('handshake, control message and bulk bytes all arrive', () async {
      final secret = _secret();

      final responderFuture = server.first.then(
        (socket) => SecureLink.establish(
          transport: SocketByteTransport.fromSocket(socket),
          role: LinkRole.responder,
          local: _deviceB,
          secret: secret,
        ),
      );

      final initiator = await SecureLink.establish(
        transport: await SocketByteTransport.connect('127.0.0.1', server.port),
        role: LinkRole.initiator,
        local: _deviceA,
        secret: secret,
      );
      final responder = await responderFuture;

      expect(initiator.peer.fingerprint, _deviceB.fingerprint);
      expect(responder.peer.fingerprint, _deviceA.fingerprint);
      expect(
        initiator.shortAuthenticationString,
        responder.shortAuthenticationString,
      );

      final atResponder = MessageLog(responder, listenToChunks: true);
      final atInitiator = MessageLog(initiator);

      await initiator.send(
        const OfferMessage(
          transferId: 'tcp-1',
          kind: PayloadKind.file,
          items: [PayloadItem(id: 'i1', name: 'photo.jpg', size: 4)],
        ),
      );
      await until(
        () => atResponder.firstOf<OfferMessage>() != null,
        description: '对端收到 offer',
      );
      expect(
        atResponder.firstOf<OfferMessage>()!.items.single.name,
        'photo.jpg',
      );

      // 1 MiB in two slices, to exercise framing over many socket reads.
      final half = Uint8List.fromList(
        List<int>.generate(512 * 1024, (i) => (i * 97 + 3) % 256),
      );
      await initiator.sendChunk(
        transferId: 'tcp-1',
        itemId: 'i1',
        offset: 0,
        data: half,
      );
      await initiator.sendChunk(
        transferId: 'tcp-1',
        itemId: 'i1',
        offset: half.length,
        data: half,
      );
      await until(() => atResponder.chunks.length == 2, description: '对端收到两片');
      final reassembled = <int>[
        ...atResponder.chunks[0].data,
        ...atResponder.chunks[1].data,
      ];
      expect(reassembled, hasLength(1024 * 1024));
      expect(reassembled.sublist(0, 1024), half.sublist(0, 1024));
      expect(atResponder.chunks[1].offset, half.length);

      await responder.send(const CompleteMessage(transferId: 'tcp-1'));
      await until(
        () => atInitiator.firstOf<CompleteMessage>() != null,
        description: '发送方收到完成确认',
      );

      await initiator.close();
      await responder.close();
    });

    test('a wrong pairing secret fails over a real socket too', () async {
      final responderFuture = server.first.then(
        (socket) => SecureLink.establish(
          transport: SocketByteTransport.fromSocket(socket),
          role: LinkRole.responder,
          local: _deviceB,
          secret: _secret(9),
        ),
      );

      final initiator = await SecureLink.establish(
        transport: await SocketByteTransport.connect('127.0.0.1', server.port),
        role: LinkRole.initiator,
        local: _deviceA,
        secret: _secret(3),
      );
      final responder = await responderFuture;
      final atResponder = MessageLog(responder);

      await initiator.send(
        const OfferMessage(
          transferId: 't',
          kind: PayloadKind.text,
          items: [],
          text: 'secret',
        ),
      );

      await until(() => atResponder.errors.isNotEmpty, description: '认证失败');
      expect(atResponder.messages, isEmpty);

      await initiator.close();
      await responder.close();
    });
  });
}

/// A connected pair over the in-memory transport.
final class _ConnectedPair {
  _ConnectedPair(this.a, this.b);

  final SecureLink a;
  final SecureLink b;

  Future<void> close() async {
    await a.close();
    await b.close();
  }
}

Future<_ConnectedPair> _connectedPair({
  PairingSecret? aSecret,
  PairingSecret? bSecret,
}) async {
  final pair = MemoryTransportPair();
  final links = await Future.wait([
    SecureLink.establish(
      transport: pair.a,
      role: LinkRole.initiator,
      local: _deviceA,
      secret: aSecret ?? _secret(),
    ),
    SecureLink.establish(
      transport: pair.b,
      role: LinkRole.responder,
      local: _deviceB,
      secret: bSecret ?? _secret(),
    ),
  ]);
  return _ConnectedPair(links[0], links[1]);
}

/// Flips one bit of the next outbound write, to model a man in the middle.
final class _TamperingTransport implements ByteTransport {
  _TamperingTransport(this._inner);

  final ByteTransport _inner;
  bool _armed = false;

  void arm() => _armed = true;

  @override
  Stream<List<int>> get incoming => _inner.incoming;

  @override
  void add(List<int> bytes) {
    if (_armed && bytes.length > 20) {
      _armed = false;
      final copy = Uint8List.fromList(bytes);
      copy[copy.length - 1] ^= 0x01;
      _inner.add(copy);
      return;
    }
    _inner.add(bytes);
  }

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> close() => _inner.close();
}

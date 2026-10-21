import 'dart:async';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// A pair of transports that can be black-holed after the handshake.
///
/// The pair carries the handshake normally and can then be black-holed, which
/// is what a black-holed connection looks like from the Session layer: the
/// socket is open, nothing is ever closed, and nothing ever arrives. A real
/// network that has lost its route behaves this way — the operating system
/// accepts what is written to it and the peer never answers — which is why a
/// Session cannot wait for the socket to report the loss.
final class BlackHoleTransportPair {
  BlackHoleTransportPair() {
    final aOut = StreamController<List<int>>();
    final bOut = StreamController<List<int>>();
    a = _BlackHoleByteTransport(bOut.stream, aOut);
    b = _BlackHoleByteTransport(aOut.stream, bOut);
  }

  /// The side the test reads from.
  late final ByteTransport a;

  /// The side the test writes to.
  late final ByteTransport b;

  /// Makes every side drop what it is given and answer nothing.
  void blackHole() {
    for (final transport in [a, b]) {
      (transport as _BlackHoleByteTransport).blackHole();
    }
  }
}

final class _BlackHoleByteTransport implements ByteTransport {
  _BlackHoleByteTransport(this._peerEnd, this._outgoing);

  final Stream<List<int>> _peerEnd;
  final StreamController<List<int>> _outgoing;
  final Completer<void> _closed = Completer<void>();
  bool _dropped = false;

  /// Starts dropping what is written and answering nothing.
  void blackHole() => _dropped = true;

  @override
  Stream<List<int>> get incoming => _peerEnd;

  @override
  void add(List<int> bytes) {
    if (_dropped) return;
    _outgoing.add(bytes);
  }

  @override
  Future<void> get done => _closed.future;

  @override
  Future<void> close() async {
    if (!_closed.isCompleted) _closed.complete();
  }
}

void main() {
  group('the liveness probe', () {
    test('a peer that answers is left alone', () async {
      final sent = <WireMessage>[];
      final keepAlive = KeepAlive(
        send: (message) async => sent.add(message),
        onTimeout: () => fail('the peer answered, so this must not time out'),
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 5),
      );
      addTearDown(keepAlive.close);
      keepAlive.start();

      await until(
        () => sent.whereType<PingMessage>().isNotEmpty,
        description: 'a probe to go out',
      );

      // The peer answers, and the answer is what keeps the Session alive.
      keepAlive.onMessage(const PongMessage('1-1'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(keepAlive.isClosed, isFalse);
    });

    test('a peer that stops answering loses the Session', () async {
      var timedOut = false;
      final keepAlive = KeepAlive(
        send: (message) async {},
        onTimeout: () => timedOut = true,
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(milliseconds: 60),
      );
      addTearDown(keepAlive.close);
      keepAlive.start();

      await until(() => timedOut, description: 'the Session to be given up on');
    });

    test('a closed probe is silent', () async {
      final sent = <WireMessage>[];
      final keepAlive = KeepAlive(
        send: (message) async => sent.add(message),
        onTimeout: () {},
        interval: const Duration(milliseconds: 20),
      );
      keepAlive.start();
      await keepAlive.close();

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sent, isEmpty);
    });
  });

  group('a Session that cannot reach its peer', () {
    test('is closed rather than left looking connected', () async {
      // The shape of a black-holed connection: the bytes go nowhere and
      // nothing is ever closed, so the socket reports nothing at all and the
      // peer never answers a probe.
      final pair = BlackHoleTransportPair();
      final secret = PairingSecret.fromBytes(List.filled(32, 7));
      final links = await Future.wait([
        SecureLink.establish(
          transport: pair.a,
          role: LinkRole.initiator,
          local: testDevice('alice', listenPort: 51001),
          secret: secret,
          keepAlive: true,
        ),
        SecureLink.establish(
          transport: pair.b,
          role: LinkRole.responder,
          local: testDevice('bob', listenPort: 51002),
          secret: secret,
          keepAlive: true,
        ),
      ]);
      final alice = SessionHub(
        links[0],
        keepAliveInterval: const Duration(milliseconds: 20),
        keepAliveTimeout: const Duration(milliseconds: 120),
      );
      final bob = SessionHub(
        links[1],
        keepAliveInterval: const Duration(milliseconds: 20),
        keepAliveTimeout: const Duration(milliseconds: 120),
      );
      addTearDown(alice.close);
      addTearDown(bob.close);

      // The network loses its route to the peer: nothing is closed and
      // nothing ever arrives again, so the socket reports no loss at all.
      pair.blackHole();

      alice.startKeepAlive();

      // Bob never answers, and the transport never reports anything, so the
      // only thing that can end this Session is the probe finding no answer.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(alice.isClosed, isFalse);
      expect(bob.isClosed, isFalse);

      await until(
        () => alice.isClosed,
        description: 'the Session to notice the peer is gone',
      );
    });

    test('is not probed at all when the peer does not speak it', () async {
      // A peer on a build without the probe must never be sent one: it would
      // meet a message it does not understand.
      final pair = MemoryTransportPair();
      final secret = PairingSecret.fromBytes(List.filled(32, 7));
      final links = await Future.wait([
        SecureLink.establish(
          transport: pair.a,
          role: LinkRole.initiator,
          local: testDevice('alice', listenPort: 51001),
          secret: secret,
          keepAlive: true,
        ),
        SecureLink.establish(
          transport: pair.b,
          role: LinkRole.responder,
          local: testDevice('bob', listenPort: 51002),
          secret: secret,
          // The older build: it never says it speaks the probe.
        ),
      ]);
      final alice = SessionHub(
        links[0],
        keepAliveInterval: const Duration(milliseconds: 20),
      );
      addTearDown(alice.close);
      addTearDown(links[1].close);

      // Bob has no hub, so this test is the only reader of his stream — which
      // is what lets it see what Alice sent him.
      final seen = <WireMessage>[];
      links[1].messages.listen(seen.add);

      alice.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(seen.whereType<PingMessage>(), isEmpty);
      expect(
        alice.isClosed,
        isFalse,
        reason: 'a peer that cannot be probed is not given up on',
      );
    });
  });

  group('a peer that probes us', () {
    test('is answered, whether or not we probe in return', () async {
      // The peer asks the same question of this Device. Answering it is what
      // keeps the probe symmetrical: a peer that waits for an answer it never
      // gets would decide we are gone and close its own Session.
      final pair = MemoryTransportPair();
      final secret = PairingSecret.fromBytes(List.filled(32, 7));
      final links = await Future.wait([
        SecureLink.establish(
          transport: pair.a,
          role: LinkRole.initiator,
          local: testDevice('alice', listenPort: 51001),
          secret: secret,
          keepAlive: true,
        ),
        SecureLink.establish(
          transport: pair.b,
          role: LinkRole.responder,
          local: testDevice('bob', listenPort: 51002),
          secret: secret,
          keepAlive: true,
        ),
      ]);
      // Only Bob has a hub: Alice's link is left free so that this test is
      // its only reader, which is what lets it see what Bob answered.
      final bob = SessionHub(
        links[1],
        keepAliveInterval: const Duration(milliseconds: 20),
      );
      addTearDown(bob.close);

      // Alice asks, and Bob answers without ever having started a probe of
      // his own, so the answer has to come from the hub rather than from the
      // keep-alive.
      final answered = <PongMessage>[];
      links[0].messages.listen((message) {
        if (message is PongMessage) answered.add(message);
      });

      await links[0].send(const PingMessage('from-bob'));

      await until(
        () => answered.isNotEmpty,
        description: 'the peer probe to be answered',
      );
      expect(
        answered.single.id,
        'from-bob',
        reason: 'the answer has to name the probe it answers',
      );
    });
  });
}

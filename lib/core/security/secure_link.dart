import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';
import '../identity/pairing_secret.dart';
import '../protocol/frame.dart';
import '../protocol/messages.dart';
import '../security/hkdf.dart';
import '../transport/byte_transport.dart';

/// Raised when a Session cannot be established or is torn down by the peer.
final class HandshakeException implements Exception {
  const HandshakeException(this.message);

  /// What went wrong, for logs rather than the UI.
  final String message;

  @override
  String toString() => 'HandshakeException: $message';
}

/// An encrypted, framed Session with one peer.
///
/// ## What the peer can and cannot claim
///
/// Completing the handshake proves only that the peer knows the Pairing Secret.
/// That is a real guarantee — it is what stops a random host on the LAN from
/// speaking to this Device — but it is not proof of *which* Device is on the
/// other end: any Device holding the same secret authenticates identically. The
/// [peer] descriptor is whatever that Device chose to announce, so the
/// [Fingerprint] in it is a claim to be checked against a pinned value before
/// it is trusted, never a fact this class establishes.
final class SecureLink {
  SecureLink._(
    this._channel,
    this._iterator,
    this._sendKey,
    this._receiveKey, {
    required this.peer,
    required this.role,
    required this.shortAuthenticationString,
  }) {
    _messages = StreamController<WireMessage>(onListen: _startPump);
    _chunks = StreamController<ChunkFrame>(onListen: _startPump);
  }

  /// A domain-separation label, mixed into every derivation.
  ///
  /// Changing the protocol in a way that alters key derivation means changing
  /// this string, so an old build and a new one derive different keys instead
  /// of silently interoperating with different meanings.
  static const String infoLabel = 'local-transfer/v1';

  /// The label bound into every AEAD record as associated data.
  static final Uint8List _aad = Uint8List.fromList(
    utf8.encode('$infoLabel record'),
  );

  /// The descriptor the peer announced.
  final PeerHandshake peer;

  /// Which side of the connection this Device is.
  final LinkRole role;

  /// Six digits both Devices can derive from the same key material.
  ///
  /// Users compare these out of band to detect a peer that knows the Pairing
  /// Secret but is not the Device it claims to be — the case the secret alone
  /// cannot rule out.
  final String shortAuthenticationString;

  final _FrameChannel _channel;
  final StreamIterator<Frame> _iterator;
  final SecretKey _sendKey;
  final SecretKey _receiveKey;

  late final StreamController<WireMessage> _messages;
  late final StreamController<ChunkFrame> _chunks;
  Future<void>? _pump;
  bool _closed = false;

  /// Control messages from the peer, decrypted.
  Stream<WireMessage> get messages => _messages.stream;

  /// Bulk payload slices from the peer, decrypted.
  ///
  /// A consumer that expects file data must listen to this stream; frames are
  /// delivered to whichever of [messages] and [chunks] is listening, so a
  /// consumer interested in both subscribes to both.
  Stream<ChunkFrame> get chunks => _chunks.stream;

  /// True once this link is closed, from either side.
  bool get isClosed => _closed;

  /// Runs the handshake over [transport] and returns the established link.
  ///
  /// [secret] must be the same Pairing Secret on both Devices; there is no
  /// negotiation of it, by design — negotiating a shared secret over the
  /// channel it is meant to protect is the failure mode this avoids.
  ///
  /// Every way the handshake can fail is reported as a [HandshakeException] —
  /// a timeout, a peer that hung up, a transport that died mid-exchange. A
  /// caller decides "no Session was established" on one error type rather than
  /// having to tell a socket error from a protocol error.
  static Future<SecureLink> establish({
    required ByteTransport transport,
    required LinkRole role,
    required DeviceDescriptor local,
    required PairingSecret secret,
    Duration timeout = const Duration(seconds: 15),
    Random? random,
  }) async {
    try {
      return await _establish(
        transport: transport,
        role: role,
        local: local,
        secret: secret,
        timeout: timeout,
        random: random,
      );
    } on HandshakeException {
      rethrow;
    } on Object catch (error) {
      throw HandshakeException('the handshake could not complete: $error');
    }
  }

  static Future<SecureLink> _establish({
    required ByteTransport transport,
    required LinkRole role,
    required DeviceDescriptor local,
    required PairingSecret secret,
    required Duration timeout,
    Random? random,
  }) async {
    final channel = _FrameChannel(transport);
    final iterator = StreamIterator<Frame>(channel.frames);

    final x25519 = X25519();
    final myKeys = await x25519.newKeyPair();
    final myPublicKey = await myKeys.extractPublicKey();
    final myNonce = randomBytes(32, random: random);
    final myHandshake = PeerHandshake(
      device: local,
      ephemeralPublicKey: Uint8List.fromList(myPublicKey.bytes),
      nonce: myNonce,
    );

    final PeerHandshake theirs;
    if (role == LinkRole.initiator) {
      channel.send(ControlFrame(HelloMessage(myHandshake).encode()));
      final json = await _awaitControl(iterator, timeout, 'helloAck');
      theirs = HelloAckMessage.fromJson(json).peer;
    } else {
      final json = await _awaitControl(iterator, timeout, 'hello');
      theirs = HelloMessage.fromJson(json).peer;
      channel.send(ControlFrame(HelloAckMessage(myHandshake).encode()));
    }

    if (theirs.fingerprint == local.fingerprint) {
      throw const HandshakeException(
        'the peer claims this Device\'s own fingerprint',
      );
    }

    final SecretKey shared;
    try {
      shared = await x25519.sharedSecretKey(
        keyPair: myKeys,
        remotePublicKey: SimplePublicKey(
          theirs.ephemeralPublicKey,
          type: KeyPairType.x25519,
        ),
      );
    } on Object catch (error) {
      throw HandshakeException('the key exchange failed: $error');
    }
    final sharedBytes = await shared.extractBytes();

    // The nonces are ordered by role, not by arrival, so both sides build the
    // same salt regardless of who spoke first.
    final initiatorNonce = role == LinkRole.initiator ? myNonce : theirs.nonce;
    final responderNonce = role == LinkRole.initiator ? theirs.nonce : myNonce;
    final salt = Uint8List(initiatorNonce.length + responderNonce.length);
    salt.setRange(0, initiatorNonce.length, initiatorNonce);
    salt.setRange(initiatorNonce.length, salt.length, responderNonce);

    // Mixing the Pairing Secret into the IKM is what makes the session
    // authenticated: without it, an attacker who completes an X25519 exchange
    // with both sides would sit in the middle undetected.
    final psk = secret.bytes;
    final ikm = Uint8List(sharedBytes.length + psk.length);
    ikm.setRange(0, sharedBytes.length, sharedBytes);
    ikm.setRange(sharedBytes.length, ikm.length, psk);

    final prk = HkdfSha256.extract(salt: salt, ikm: ikm);
    final initiatorToResponder = HkdfSha256.expand(
      prk: prk,
      info: utf8.encode('$infoLabel i2r'),
      length: 32,
    );
    final responderToInitiator = HkdfSha256.expand(
      prk: prk,
      info: utf8.encode('$infoLabel r2i'),
      length: 32,
    );

    final sendBytes = role == LinkRole.initiator
        ? initiatorToResponder
        : responderToInitiator;
    final receiveBytes = role == LinkRole.initiator
        ? responderToInitiator
        : initiatorToResponder;

    final link = SecureLink._(
      channel,
      iterator,
      SecretKey(sendBytes),
      SecretKey(receiveBytes),
      peer: theirs,
      role: role,
      shortAuthenticationString: _shortAuthenticationString(prk),
    );
    // Nothing above may see a Session that has not been shown to work: the
    // confirmation is what turns "the keys were derived" into "the peer holds
    // the same Pairing Secret".
    try {
      await link._confirm(iterator, timeout, role);
    } on HandshakeException {
      // Tear the transport down rather than leaving it open: a peer whose keys
      // do not match ours has no reason to keep waiting, and a half-dead
      // socket that nobody will ever read is worse than a closed one.
      await link.close();
      rethrow;
    }
    return link;
  }

  /// Proves both sides hold the same Pairing Secret before the link is handed
  /// out.
  ///
  /// Each side sends one record sealed with the keys the handshake derived and
  /// requires the peer's in return. A peer that derived different keys — a
  /// different Pairing Secret, or a handshake that was tampered with — cannot
  /// produce a record that authenticates, so the exchange fails here rather
  /// than at the first Transfer, which is what a caller has to be able to
  /// rely on: an established link either works or was never established.
  ///
  /// Both records are read through the same iterator the pump will later use;
  /// the pump only starts when somebody subscribes, which cannot happen until
  /// [establish] has returned.
  Future<void> _confirm(
    StreamIterator<Frame> iterator,
    Duration timeout,
    LinkRole role,
  ) async {
    if (role == LinkRole.initiator) {
      await send(const SessionConfirmMessage());
    }
    await _awaitConfirm(iterator, timeout);
    if (role == LinkRole.responder) {
      await send(const SessionConfirmMessage());
    }
  }

  Future<void> _awaitConfirm(
    StreamIterator<Frame> iterator,
    Duration timeout,
  ) async {
    final bool hasNext;
    try {
      hasNext = await iterator.moveNext().timeout(timeout);
    } on TimeoutException {
      throw HandshakeException(
        'the peer never confirmed the Session within ${timeout.inSeconds}s',
      );
    }
    if (!hasNext) {
      throw HandshakeException(
        'the peer closed the connection before confirming the Session',
      );
    }
    final Frame frame;
    try {
      frame = await _open(iterator.current);
    } on ProtocolException catch (error) {
      // Decryption failing here is the whole point of the step: it means the
      // peer's keys differ from ours, which means its Pairing Secret does.
      throw HandshakeException(
        'the peer does not hold the same Pairing Secret (${error.message})',
      );
    }
    if (frame is! ControlFrame) {
      throw const HandshakeException(
        'the peer confirmed the Session with something other than a control '
        'message',
      );
    }
    final WireMessage message;
    try {
      message = WireMessage.decode(frame.json);
    } on FormatException catch (error) {
      throw HandshakeException(
        'the Session confirmation did not decode: ${error.message}',
      );
    }
    if (message is! SessionConfirmMessage) {
      throw HandshakeException(
        'expected a Session confirmation, got "${message.type}"',
      );
    }
  }

  /// Sends a control message to the peer.
  Future<void> send(WireMessage message) =>
      _seal(ControlFrame(message.encode()));

  /// Sends a slice of bulk payload to the peer.
  Future<void> sendChunk({
    required String transferId,
    required String itemId,
    required int offset,
    required List<int> data,
  }) => _seal(
    ChunkFrame(
      transferId: transferId,
      itemId: itemId,
      offset: offset,
      data: Uint8List.fromList(data),
    ),
  );

  /// Closes the link in both directions.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Deliberately not awaited: a StreamController's close() future only
    // completes once its done event has been delivered, which never happens
    // for a stream nobody listened to. Awaiting it here would deadlock every
    // caller that closes a link before subscribing to it.
    _closeControllers();
    await _channel.close();
  }

  void _closeControllers() {
    unawaited(_messages.close());
    unawaited(_chunks.close());
  }

  Future<void> _seal(Frame inner) async {
    if (_closed) {
      throw StateError('cannot send on a closed link');
    }
    final plain = encodeFrame(inner);
    final box = await _cipher.encrypt(plain, secretKey: _sendKey, aad: _aad);
    final tag = box.mac.bytes;
    final cipherText = Uint8List(box.cipherText.length + tag.length);
    cipherText.setRange(0, box.cipherText.length, box.cipherText);
    cipherText.setRange(box.cipherText.length, cipherText.length, tag);
    _channel.send(
      SealedFrame(nonce: Uint8List.fromList(box.nonce), cipherText: cipherText),
    );
  }

  void _startPump() {
    _pump ??= _runPump();
  }

  Future<void> _runPump() async {
    try {
      while (await _iterator.moveNext()) {
        // A link closed underneath this loop has nothing left to deliver to:
        // close() tears the transport down and finishes both streams at once,
        // and frames already queued behind the teardown belong to a Session
        // nobody is listening to any more.
        if (_closed) return;
        final frame = await _open(_iterator.current);
        // Checked again after the await: close() can land while a record is
        // being decrypted, and adding to a finished controller is a crash
        // rather than a lost message.
        if (_closed) return;
        switch (frame) {
          case ControlFrame():
            _messages.add(WireMessage.decode(frame.json));
          case ChunkFrame():
            _chunks.add(frame);
          case SealedFrame():
            throw const ProtocolException(
              'a sealed record must not contain another sealed record',
            );
        }
      }
      _closeControllers();
    } on Object catch (error, stack) {
      // Whatever went wrong, reporting it needs live streams. A closed link has
      // none, and the failure is then the teardown itself rather than news.
      if (_closed) {
        _closeControllers();
        return;
      }
      _messages.addError(error, stack);
      _chunks.addError(error, stack);
      _closeControllers();
      await close();
    }
  }

  /// Decrypts a record and returns the single frame inside it.
  Future<Frame> _open(Frame frame) async {
    if (frame is! SealedFrame) {
      throw ProtocolException(
        'the peer sent an unsealed ${frame.runtimeType} after the handshake',
      );
    }
    final cipherText = frame.cipherText;
    if (cipherText.length <= sealedTagBytes) {
      throw ProtocolException(
        'a sealed record of ${cipherText.length} bytes carries no payload',
      );
    }
    final bodyLength = cipherText.length - sealedTagBytes;
    final List<int> plain;
    try {
      plain = await _cipher.decrypt(
        SecretBox(
          Uint8List.sublistView(cipherText, 0, bodyLength),
          nonce: frame.nonce,
          mac: Mac(Uint8List.sublistView(cipherText, bodyLength)),
        ),
        secretKey: _receiveKey,
        // The same associated data the sender bound; omitting it here would
        // fail every record's tag check.
        aad: _aad,
      );
    } on SecretBoxAuthenticationError {
      // Either the Pairing Secret differs, or the record was tampered with.
      // The two are indistinguishable by design, and both mean "stop".
      throw const ProtocolException(
        'a record failed authentication; the Pairing Secret may differ',
      );
    }
    final decoder = FrameDecoder()..add(plain);
    final inner = decoder.next();
    if (inner == null) {
      throw const ProtocolException(
        'a sealed record did not contain a complete frame',
      );
    }
    // A record carrying anything beyond one frame would let a peer smuggle
    // data past the layer that inspects frames.
    decoder.expectDrained();
    return inner;
  }

  static String _shortAuthenticationString(Uint8List prk) {
    final digest = HkdfSha256.expand(
      prk: prk,
      info: utf8.encode('$infoLabel sas'),
      length: 4,
    );
    final value = ByteData.sublistView(digest).getUint32(0, Endian.big);
    return (value % 1000000).toString().padLeft(6, '0');
  }

  static Future<Map<String, Object?>> _awaitControl(
    StreamIterator<Frame> iterator,
    Duration timeout,
    String expectedType,
  ) async {
    final bool hasNext;
    try {
      hasNext = await iterator.moveNext().timeout(timeout);
    } on TimeoutException {
      throw HandshakeException(
        'timed out after ${timeout.inSeconds}s waiting for "$expectedType"',
      );
    }
    if (!hasNext) {
      throw HandshakeException(
        'the peer closed the connection while "$expectedType" was expected',
      );
    }
    final frame = iterator.current;
    if (frame is! ControlFrame) {
      throw HandshakeException(
        'expected a "$expectedType" control message, got $frame',
      );
    }
    final WireMessage message;
    try {
      message = WireMessage.decode(frame.json);
    } on FormatException catch (error) {
      throw HandshakeException(
        'the handshake did not decode: ${error.message}',
      );
    }
    if (message.type != expectedType) {
      throw HandshakeException(
        'expected "$expectedType", got "${message.type}"',
      );
    }
    if (message case final HelloMessage hello) {
      _checkVersion(hello.peer);
    } else if (message case final HelloAckMessage ack) {
      _checkVersion(ack.peer);
    }
    return frame.json;
  }

  static void _checkVersion(PeerHandshake handshake) {
    if (handshake.protocolVersion != wireProtocolVersion) {
      throw HandshakeException(
        'the peer speaks protocol ${handshake.protocolVersion}, '
        'this build speaks $wireProtocolVersion',
      );
    }
  }

  static final Cipher _cipher = Chacha20.poly1305Aead();
}

/// A framing layer over a [ByteTransport].
final class _FrameChannel {
  _FrameChannel(this._transport) {
    frames = decodeFrames(_transport.incoming);
  }

  final ByteTransport _transport;

  /// Frames arriving from the peer. Single-subscription.
  late final Stream<Frame> frames;

  void send(Frame frame) => _transport.add(encodeFrame(frame));

  Future<void> close() => _transport.close();
}

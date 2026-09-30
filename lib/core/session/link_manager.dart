import 'dart:async';
import 'dart:io';

import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';
import '../identity/pairing_secret.dart';
import '../protocol/messages.dart';
import '../security/secure_link.dart';
import '../transport/byte_transport.dart';
import 'session_hub.dart';

/// The TCP port a Device listens on for Sessions by default.
///
/// Fixed for the same reason the discovery port is: a peer that has only a
/// beacon to go on must be able to dial without configuration. Distinct from
/// the discovery port so the UDP listener and the TCP listener never compete,
/// and inside the IANA dynamic range.
const int defaultSessionPort = 47655;

/// What happened to the set of Sessions a [LinkManager] holds.
///
/// Deliberately a stream of events rather than callbacks: an app layer
/// rebuilding a device list and a clipboard mirror switching itself on both
/// watch the same events, and neither owns the manager.
sealed class LinkEvent {
  const LinkEvent();
}

/// A Session was established, locally or remotely initiated.
final class SessionEstablished extends LinkEvent {
  const SessionEstablished(this.session);

  /// The Session that came up.
  final ManagedSession session;
}

/// An incoming connection did not become a Session.
///
/// Not fatal, and not silent: the address is named so a log can say where the
/// attempt came from, but a peer that failed the handshake is not named,
/// because before it completes there is nobody trustworthy to name.
final class SessionRefused extends LinkEvent {
  const SessionRefused({required this.address, required this.reason});

  /// Where the connection came from.
  final InternetAddress? address;

  /// Why it was refused, for logs.
  final Object reason;
}

/// A Session went away, from either side.
final class SessionLost extends LinkEvent {
  const SessionLost({required this.peer, this.reason});

  /// The Device the Session was with.
  final Fingerprint peer;

  /// What ended it, when it was not a clean shutdown.
  final Object? reason;
}

/// One live Session, as the manager holds it.
///
/// The Session is a [SessionHub], not a bare [SecureLink]: a Session carries
/// the transfer conversation and the clipboard conversation at once, and the
/// hub is the one object allowed to read the link's single-subscription
/// stream.
final class ManagedSession {
  ManagedSession({
    required this.hub,
    required this.role,
    required this.address,
    required ByteTransport transport,
    // A named parameter cannot be private, so `this._transport` is not legal
    // here; the field is assigned from a public parameter instead.
    // ignore: prefer_initializing_formals
  }) : _transport = transport;

  /// The routed Session.
  final SessionHub hub;

  /// Which side of the connection opened it.
  final LinkRole role;

  /// The peer's address, as reported by the socket.
  final InternetAddress? address;

  final ByteTransport _transport;

  /// The Device on the other end.
  Fingerprint get peer => hub.peer;

  /// What the peer announced about itself — a claim, not a proof.
  PeerHandshake get handshake => hub.link.peer;

  /// Whether this Session is still usable.
  bool get isOpen => !hub.isClosed;

  /// Completes when the underlying connection ends, from either side.
  Future<void> get done => _transport.done;

  /// Ends the Session and releases the socket.
  Future<void> close() => hub.close();

  @override
  String toString() =>
      'ManagedSession(${peer.short()}, ${role.wireName}, '
      '${address?.address ?? "unknown"})';
}

/// The Sessions this Device has open, and the listener that accepts new ones.
///
/// This is the seam between "a socket exists" and "a Transfer can happen":
/// discovery finds a Device and gives an address, [connect] turns that into a
/// [ManagedSession], [serve] turns an incoming connection into one, and
/// everything above — transfers, clipboard mirroring — works with the Session
/// it returns rather than with a socket.
///
/// Two rules are worth stating because they are policy, not plumbing:
///
/// * **One Session per peer.** A second connection to a peer already held is
///   closed rather than replacing the first. Replacing would tear down
///   in-flight transfers whenever a peer reconnected, and would let any peer
///   holding the Pairing Secret displace a Session at will.
/// * **A Device never talks to itself.** A Session whose peer claims this
///   Device's own Fingerprint is refused. That happens in practice when a
///   loopback connection is read back, and accepting it would let a Device
///   send itself Transfers that look like a peer's.
///
/// The manager does not decide *whether* a peer is trusted. Holding the
/// [PairingSecret] is the whole admission test here; membership of an Owner
/// Group, Favorites and per-Transfer confirmation all live above this seam.
final class LinkManager {
  /// A manager for [local], authenticating Sessions with [sessionSecret].
  LinkManager({
    required DeviceDescriptor local,
    required PairingSecret sessionSecret,
    this.handshakeTimeout = const Duration(seconds: 15),
  }) : // Named parameters cannot be private fields, so each is assigned here.
       // ignore: prefer_initializing_formals
       _local = local,
       // ignore: prefer_initializing_formals
       _sessionSecret = sessionSecret;

  /// Returns [local] with its listening port replaced, or unchanged when it
  /// already matches.
  ///
  /// A descriptor is immutable because the port is part of what a peer pins,
  /// so a Device that starts listening rebuilds it rather than editing it.
  static DeviceDescriptor withListenPort(DeviceDescriptor local, int? port) {
    if (local.listenPort == port) return local;
    return DeviceDescriptor(
      fingerprint: local.fingerprint,
      alias: local.alias,
      platform: local.platform,
      capability: local.capability,
      listenPort: port,
    );
  }

  final DeviceDescriptor _local;
  final PairingSecret _sessionSecret;

  /// How long a handshake may take before the Session is abandoned.
  final Duration handshakeTimeout;

  final Map<String, ManagedSession> _sessions = {};
  final StreamController<LinkEvent> _events =
      StreamController<LinkEvent>.broadcast();

  ServerSocket? _server;
  bool _closed = false;

  /// What this Device announces, including the port it is serving on.
  ///
  /// Read this rather than the descriptor the manager was constructed with:
  /// before [serve] the port is null, and a beacon carrying a null port tells
  /// peers this Device accepts no Sessions.
  DeviceDescriptor get advertised =>
      LinkManager.withListenPort(_local, _server?.port ?? _local.listenPort);

  /// Whether the listener is up.
  bool get isServing => _server != null;

  /// The port Sessions are accepted on, or null when not serving.
  int? get listenPort => _server?.port ?? _local.listenPort;

  /// Session events, broadcast so several consumers can watch.
  Stream<LinkEvent> get events => _events.stream;

  /// The Sessions currently held, most recently established first.
  List<ManagedSession> get sessions =>
      _sessions.values.toList().reversed.toList(growable: false);

  /// The Session held with [peer], or null.
  ManagedSession? session(Fingerprint peer) => _sessions[peer.hex];

  /// Whether a Session is held with [peer].
  bool isConnectedTo(Fingerprint peer) => _sessions.containsKey(peer.hex);

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Starts accepting Sessions on [port].
  ///
  /// Port 0 binds an arbitrary free port, which is what a test wants; the
  /// chosen port is readable through [listenPort], and [advertised] carries it
  /// from then on.
  Future<void> serve({int port = defaultSessionPort}) async {
    if (_closed) {
      throw StateError('this LinkManager is closed');
    }
    if (_server != null) {
      throw StateError('already serving on ${_server!.port}');
    }
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(
      (socket) => unawaited(_onConnection(socket)),
      onError: (Object error) =>
          _emit(SessionRefused(address: null, reason: error)),
      onDone: () => _server = null,
    );
  }

  /// Opens a Session to a peer.
  ///
  /// [expectedFingerprint] is what a caller that has already decided who it is
  /// dialling should pass: the handshake proves a peer holds the Pairing
  /// Secret, never that it is a particular Device, so a caller who cares —
  /// redialing a Known Device, or a peer in the Owner Group — pins it here and
  /// gets a refusal instead of a stranger's Session.
  ///
  /// Throws [HandshakeException] on every failure to establish: a refused
  /// dial, a dead host, a timeout, or a peer whose claim does not match
  /// [expectedFingerprint]. A caller therefore handles one error type.
  Future<ManagedSession> connect(
    String host,
    int port, {
    Fingerprint? expectedFingerprint,
    PairingSecret? secret,
  }) async {
    if (_closed) {
      throw StateError('this LinkManager is closed');
    }
    final SocketByteTransport transport;
    try {
      transport = await SocketByteTransport.connect(host, port);
    } on SocketException catch (error) {
      throw HandshakeException('cannot reach $host:$port: ${error.message}');
    }
    return _establish(
      transport: transport,
      role: LinkRole.initiator,
      secret: secret ?? _sessionSecret,
      expectedFingerprint: expectedFingerprint,
      address: transport.remoteAddress,
    );
  }

  /// Ends every Session and stops listening.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final server = _server;
    _server = null;
    if (server != null) await server.close();
    final open = _sessions.values.toList();
    _sessions.clear();
    for (final session in open) {
      await session.close();
    }
    if (!_events.isClosed) await _events.close();
  }

  Future<void> _onConnection(Socket socket) async {
    // Read the address before anything can close the socket: after a failed
    // handshake the peer is often already gone, and asking a destroyed socket
    // for its remote address throws instead of reporting where it came from.
    InternetAddress? from;
    try {
      from = socket.remoteAddress;
    } on SocketException {
      from = null;
    }
    if (_closed) {
      socket.destroy();
      return;
    }
    final transport = SocketByteTransport.fromSocket(socket);
    var adopted = false;
    try {
      await _establish(
        transport: transport,
        role: LinkRole.responder,
        secret: _sessionSecret,
        address: from,
      );
      adopted = true;
    } on HandshakeException catch (error) {
      _emit(SessionRefused(address: from, reason: error));
    } on Object catch (error) {
      // A hostile or half-open connection must not take the listener down with
      // it: the accept loop is the one thing that has to keep working.
      _emit(SessionRefused(address: from, reason: error));
    } finally {
      // Only a connection that did *not* become a Session is closed here; an
      // adopted one is owned by its Session from now on.
      if (!adopted) await transport.close();
    }
  }

  Future<ManagedSession> _establish({
    required ByteTransport transport,
    required LinkRole role,
    required PairingSecret secret,
    Fingerprint? expectedFingerprint,
    InternetAddress? address,
  }) async {
    final SecureLink link;
    try {
      link = await SecureLink.establish(
        transport: transport,
        role: role,
        local: advertised,
        secret: secret,
        timeout: handshakeTimeout,
      );
    } on HandshakeException {
      await transport.close();
      rethrow;
    }

    final peer = link.peer.fingerprint;

    if (peer == _local.fingerprint) {
      await link.close();
      throw const HandshakeException('refusing a Session with this Device');
    }
    if (expectedFingerprint != null && peer != expectedFingerprint) {
      // Close before anybody above can see it: the point of pinning is that no
      // Session with the wrong Device ever exists, not that it is discarded.
      await link.close();
      throw HandshakeException(
        'expected ${expectedFingerprint.short()} but reached ${peer.short()}',
      );
    }
    if (_sessions.containsKey(peer.hex)) {
      await link.close();
      throw HandshakeException(
        'already holding a Session with ${peer.short()}',
      );
    }

    final session = ManagedSession(
      hub: SessionHub(link),
      role: role,
      address: address,
      transport: transport,
    );
    _sessions[peer.hex] = session;
    unawaited(
      session.done.then(
        (_) => _forget(session, null),
        onError: (Object error) => _forget(session, error),
      ),
    );
    _emit(SessionEstablished(session));
    return session;
  }

  void _forget(ManagedSession session, Object? reason) {
    final peer = session.peer;
    if (_sessions[peer.hex] != session) return;
    _sessions.remove(peer.hex);
    _emit(SessionLost(peer: peer, reason: reason));
  }

  void _emit(LinkEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }
}

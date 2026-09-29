import 'dart:async';
import 'dart:io';

/// A duplex stream of raw bytes, and the only thing the layers above know
/// about the network.
///
/// Keeping the socket behind this interface lets the protocol, handshake and
/// transfer logic be exercised over a real TCP socket and over an in-memory
/// pair with no code path differences.
abstract interface class ByteTransport {
  /// Bytes arriving from the peer. Single-subscription.
  Stream<List<int>> get incoming;

  /// Queues bytes for the peer. Never blocks; backpressure is the transport's
  /// own concern.
  void add(List<int> bytes);

  /// Completes when the connection is torn down, from either side.
  Future<void> get done;

  /// Closes the transport in both directions.
  Future<void> close();
}

/// A [ByteTransport] over a TCP [Socket].
final class SocketByteTransport implements ByteTransport {
  SocketByteTransport.fromSocket(this._socket) {
    _socket.done.then(
      (_) => _closed.complete(),
      onError: (Object _) => _closed.complete(),
    );
  }

  /// Dials [host]:[port].
  static Future<SocketByteTransport> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return SocketByteTransport.fromSocket(socket);
  }

  final Socket _socket;
  final Completer<void> _closed = Completer<void>();

  /// The peer's address, as reported by the socket.
  InternetAddress? get remoteAddress => _socket.remoteAddress;

  @override
  Stream<List<int>> get incoming => _socket;

  @override
  void add(List<int> bytes) {
    _socket.add(bytes);
  }

  @override
  Future<void> get done => _closed.future;

  @override
  Future<void> close() async {
    // destroy rather than close: an abandoned Session must not wait for a
    // graceful FIN that the peer may never send.
    _socket.destroy();
    await done;
  }
}

/// A pair of [ByteTransport]s joined to each other, for tests.
///
/// Bytes written to one side arrive on the other's [incoming] stream, and
/// either side closing tears down both — the same observable behaviour a TCP
/// socket pair presents to this layer.
final class MemoryTransportPair {
  MemoryTransportPair() {
    final aOut = StreamController<List<int>>();
    final bOut = StreamController<List<int>>();
    final closed = Completer<void>();
    a = _MemoryByteTransport(bOut.stream, aOut, bOut, closed);
    b = _MemoryByteTransport(aOut.stream, bOut, aOut, closed);
  }

  /// The side that plays the initiator in tests.
  late final ByteTransport a;

  /// The side that plays the responder in tests.
  late final ByteTransport b;
}

final class _MemoryByteTransport implements ByteTransport {
  _MemoryByteTransport(
    this.incoming,
    this._outgoing,
    this._peerEnd,
    this._closed,
  );

  @override
  final Stream<List<int>> incoming;

  final StreamController<List<int>> _outgoing;
  final StreamController<List<int>> _peerEnd;
  final Completer<void> _closed;

  @override
  void add(List<int> bytes) {
    if (_outgoing.isClosed) {
      throw StateError('cannot write to a closed transport');
    }
    _outgoing.add(bytes);
  }

  @override
  Future<void> get done => _closed.future;

  @override
  Future<void> close() async {
    // Deliberately not awaited. A StreamController's close() future only
    // completes once its done event has been delivered to the listener, and a
    // listener that is not currently reading — an idle StreamIterator, say —
    // buffers that event indefinitely. Awaiting here would deadlock every
    // close() on a transport whose peer side is not being pumped, which is
    // exactly the state a link sits in when nobody has subscribed to it yet.
    if (!_outgoing.isClosed) unawaited(_outgoing.close());
    // Closing our outgoing end ends the peer's incoming end, which is what a
    // TCP FIN looks like from the other side.
    if (!_peerEnd.isClosed) unawaited(_peerEnd.close());
    if (!_closed.isCompleted) _closed.complete();
  }
}

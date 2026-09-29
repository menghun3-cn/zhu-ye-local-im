import 'dart:async';
import 'dart:io';

import '../protocol/frame.dart';
import 'beacon.dart';
import 'beacon_transport.dart';

/// The limited broadcast address, which reaches the local link without a
/// netmask being known.
final InternetAddress limitedBroadcastAddress = InternetAddress(
  '255.255.255.255',
);

/// The directed broadcast address of every IPv4 subnet this host is on.
///
/// `InterfaceAddress.broadcast` is what makes this possible without asking the
/// user for a netmask (see `docs/dart-networking-capabilities.md`). Loopback
/// and link-local entries are dropped by default: a `169.254.0.0/16` broadcast
/// reaches nobody this product wants to talk to.
Future<List<InternetAddress>> subnetBroadcastAddresses({
  bool includeLoopback = false,
}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: includeLoopback,
    includeLinkLocal: false,
  );
  final seen = <String>{};
  final targets = <InternetAddress>[];
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      final broadcast = address.broadcast;
      if (broadcast == null) continue;
      if (seen.add(broadcast.address)) targets.add(broadcast);
    }
  }
  return targets;
}

/// What an announce is sent to on a real network.
///
/// The limited broadcast address is tried *as well as* the directed ones: some
/// access points forward one and not the other, and the duplicate costs one
/// small datagram per announce. This is policy, so it lives in the default
/// target provider rather than inside [UdpBeaconTransport] — a transport sends
/// to exactly the targets it was given, which is what keeps it testable without
/// putting a packet on a real LAN.
Future<List<InternetAddress>> defaultBroadcastTargets() async => [
  limitedBroadcastAddress,
  ...await subnetBroadcastAddresses(),
];

/// Discovery over UDP broadcast, using only `dart:io`.
///
/// **Broadcast, not multicast.** Receiving multicast on Android needs a
/// `WifiManager.MulticastLock` plus the `CHANGE_WIFI_MULTICAST_STATE`
/// permission, which is a platform API this project cannot reach while it ships
/// no plugins (see `docs/android-background-constraints.md`); a broadcast read
/// back off the same link needs nothing extra. Multicast would also mean
/// choosing and maintaining a group address, for a reachability win that only
/// matters once discovery crosses subnets — a later, harder problem than this
/// layer solves.
final class UdpBeaconTransport implements BeaconTransport {
  UdpBeaconTransport._(
    this._socket,
    this._broadcastPort,
    this._targets,
    this._targetRefreshInterval,
  );

  /// Binds the discovery socket and starts receiving.
  ///
  /// [port] is where this Device listens; the app uses [discoveryPort], and
  /// tests use an ephemeral one. [broadcastPort] is the port peers are
  /// addressed on when broadcasting, and defaults to [port] — the two differ
  /// only when a Device listens somewhere other than the well-known port, which
  /// is what would let two Devices share one host.
  static Future<UdpBeaconTransport> bind({
    int port = discoveryPort,
    int? broadcastPort,
    InternetAddress? address,
    Future<List<InternetAddress>> Function()? targets,
    Duration targetRefreshInterval = const Duration(seconds: 10),
  }) async {
    final socket = await RawDatagramSocket.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    socket.broadcastEnabled = true;
    final transport = UdpBeaconTransport._(
      socket,
      broadcastPort ?? port,
      targets ?? defaultBroadcastTargets,
      targetRefreshInterval,
    );
    transport._subscription = socket.listen(transport._onEvent);
    unawaited(transport._refreshTargets());
    return transport;
  }

  final RawDatagramSocket _socket;
  final int _broadcastPort;
  final Future<List<InternetAddress>> Function() _targets;
  final Duration _targetRefreshInterval;
  final StreamController<BeaconDatagram> _received =
      StreamController<BeaconDatagram>();

  late final StreamSubscription<RawSocketEvent> _subscription;
  List<InternetAddress> _cachedTargets = const [];
  DateTime? _lastRefresh;
  bool _closed = false;

  /// The local port the socket is bound to.
  int get port => _socket.port;

  /// The broadcast addresses most recently resolved.
  ///
  /// Exposed so a caller can show what discovery is actually addressing, and so
  /// a test can assert the target provider was consulted.
  List<InternetAddress> get broadcastTargets =>
      List.unmodifiable(_cachedTargets);

  /// The port a broadcast is addressed to.
  int get broadcastPort => _broadcastPort;

  @override
  Stream<BeaconDatagram> get received => _received.stream;

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket.receive();
    if (datagram == null) return;
    final Beacon beacon;
    try {
      beacon = Beacon.decode(datagram.data);
    } on ProtocolException {
      // See BeaconTransport: one bad packet from a stranger must not take the
      // receive loop down.
      return;
    }
    if (_received.isClosed) return;
    _received.add(
      BeaconDatagram(
        beacon: beacon,
        address: datagram.address,
        port: datagram.port,
      ),
    );
  }

  @override
  void send(
    List<int> datagram, {
    required InternetAddress address,
    required int port,
  }) {
    if (_closed) return;
    _socket.send(datagram, address, port);
  }

  @override
  void broadcast(List<int> datagram) {
    if (_closed) return;
    for (final target in _cachedTargets) {
      _socket.send(datagram, target, _broadcastPort);
    }
    // Keep the subnet list warm so a Device that joins a new network is reached
    // on the next announce without the caller having to schedule a refresh.
    unawaited(_refreshTargets());
  }

  Future<void> _refreshTargets() async {
    final now = DateTime.now();
    final last = _lastRefresh;
    if (last != null && now.difference(last) < _targetRefreshInterval) return;
    _lastRefresh = now;
    try {
      _cachedTargets = await _targets();
    } on Object {
      // An interface that vanished mid-enumeration is not worth failing an
      // announce over; whatever was cached stays in use.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    _socket.close();
    if (!_received.isClosed) unawaited(_received.close());
  }
}

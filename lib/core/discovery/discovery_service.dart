import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../identity/device_descriptor.dart';
import '../security/hkdf.dart';
import 'beacon.dart';
import 'beacon_transport.dart';
import 'peer_registry.dart';

/// Finds the other Devices on the local link — and on the private networks
/// that link is joined to — and keeps finding them.
///
/// The policy is small on purpose: announce on a schedule so others find this
/// Device, probe once at start so this Device finds others without waiting out
/// an announce period, answer a probe directly so the prober does not have to,
/// and drop a peer that stops announcing. Broadcast stops at the routing
/// boundary, so a second, unicast probe goes to every address a provider names
/// — remembered peers, a tailnet directory — for the Devices broadcast cannot
/// reach. Everything else — the socket, the clock, the peer table — is behind
/// a seam.
final class DiscoveryService {
  DiscoveryService({
    required this.transport,
    required this.local,
    String? nonce,
    this.announceInterval = const Duration(seconds: 3),
    this.sweepInterval = const Duration(seconds: 1),
    Duration peerTtl = const Duration(seconds: 10),
    this.unicastTargets,
    this.unicastProbeInterval = const Duration(seconds: 5),
    this.maxUnicastTargets = 64,
    DateTime Function()? clock,
    Random? random,
  }) : _nonce = nonce ?? randomNonce(random),
       _registry = PeerRegistry(
         localFingerprint: local.fingerprint,
         ttl: peerTtl,
         clock: clock,
       );

  /// The datagram plumbing this service drives.
  ///
  /// Held rather than created: the same transport is shared with whatever else
  /// needs the socket, and a test substitutes an in-memory one. Send through
  /// the service's own methods so the "am I running" rule is applied.
  final BeaconTransport transport;

  /// What this Device announces about itself.
  ///
  /// Settable because the ports this Device listens on are not all known
  /// when the service starts: the Pairing listener comes up after the
  /// Session layer, and its port has to be announced too. A second service
  /// over the same transport is not an option — a transport's receive stream
  /// is single-subscription, and a single-subscription stream cannot be
  /// listened to a second time even after the first subscription is gone.
  DeviceDescriptor local;

  /// How often this Device tells the link it is here.
  final Duration announceInterval;

  /// How often peers that stopped announcing are dropped.
  final Duration sweepInterval;

  /// The addresses worth probing directly, because broadcast cannot reach
  /// them: remembered peers, tailnet members, anything a provider can name.
  ///
  /// Called once per [unicastProbeInterval]; the probe it returns is sent
  /// to each address unicast, and an answer is recorded exactly like a
  /// broadcast one — the peer's own announce names where it can be reached.
  /// Null disables unicast probing entirely.
  final Future<List<InternetAddress>> Function()? unicastTargets;

  /// How often the unicast targets are probed.
  ///
  /// Deliberately shorter than the peer TTL: a peer heard only through these
  /// probes would expire between rounds if the interval were longer, and the
  /// datagrams are small enough that a five-second cadence costs nothing.
  final Duration unicastProbeInterval;

  /// The most unicast targets probed per round, so a very large directory
  /// cannot turn discovery into a flood.
  final int maxUnicastTargets;

  final String _nonce;
  final PeerRegistry _registry;

  StreamSubscription<BeaconDatagram>? _subscription;
  Timer? _announceTimer;
  Timer? _sweepTimer;
  Timer? _unicastTimer;
  bool _running = false;

  /// The beacon bytes, re-encoded when the descriptor behind them changes.
  late Uint8List _announceBytes = _encode(BeaconKind.announce);
  late Uint8List _probeBytes = _encode(BeaconKind.probe);

  Uint8List _encode(BeaconKind kind) =>
      Beacon(kind: kind, device: local, nonce: _nonce).encode();

  /// Changes what this Device announces, without rebuilding the service.
  ///
  /// The ports this Device listens on become known one after another: the
  /// Session layer binds first, the Pairing listener after it. Each of them
  /// has to be announced, and a second service over the same transport is not
  /// possible — a transport's receive stream is single-subscription.
  ///
  /// So the descriptor is swapped in place and the beacon bytes are
  /// re-encoded. The next announce carries the new one; peers learn it on
  /// that cycle.
  void updateLocal(DeviceDescriptor descriptor) {
    if (descriptor == local) return;
    local = descriptor;
    _announceBytes = _encode(BeaconKind.announce);
    _probeBytes = _encode(BeaconKind.probe);
    // Say so now rather than at the next tick: a peer that is waiting to be
    // told where to dial should not wait out a whole announce period.
    announce();
  }

  /// Whether the service is currently announcing and listening.
  bool get isRunning => _running;

  /// Emits the peer list whenever it changes.
  ///
  /// A broadcast stream, so several consumers can watch it; a consumer that
  /// needs the current list synchronously reads [currentPeers] instead.
  Stream<List<DiscoveredPeer>> get peers => _registry.changes;

  /// The peer list as of now.
  List<DiscoveredPeer> get currentPeers => _registry.peers;

  /// Starts announcing and listening. Idempotent.
  void start() {
    if (_running) return;
    _running = true;
    _subscription = transport.received.listen(_onDatagram);
    probe();
    _announceTimer = Timer.periodic(announceInterval, (_) => announce());
    _sweepTimer = Timer.periodic(sweepInterval, (_) => _registry.expire());
    if (unicastTargets != null) {
      unawaited(_probeUnicastTargets());
      _unicastTimer = Timer.periodic(
        unicastProbeInterval,
        (_) => unawaited(_probeUnicastTargets()),
      );
    }
  }

  /// Tells the link this Device is here, now.
  void announce() {
    if (!_running) return;
    transport.broadcast(_announceBytes);
  }

  /// Asks the link who is here, now. Exposed for a user-invoked refresh.
  void probe() {
    if (!_running) return;
    transport.broadcast(_probeBytes);
  }

  /// Asks one address who is there, and waits for its announce.
  ///
  /// Discovery normally broadcasts the probe; a user who typed an address has
  /// already answered "where", so the probe is unicast and the answer is the
  /// first announce that arrives from that address. The announce is recorded
  /// like any other sighting, so the peer joins [currentPeers] whether or not
  /// this call is still waiting.
  Future<DiscoveredPeer?> probeHost(
    InternetAddress address, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!_running) return null;
    for (final peer in _registry.peers) {
      if (_heardAt(peer, address)) return peer;
    }
    transport.send(_probeBytes, address: address, port: discoveryPort);
    final deadline = DateTime.now().add(timeout);
    while (true) {
      for (final peer in _registry.peers) {
        if (_heardAt(peer, address)) return peer;
      }
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Stops announcing and listening, leaving the peer list as it stands.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _announceTimer?.cancel();
    _sweepTimer?.cancel();
    _unicastTimer?.cancel();
    _announceTimer = null;
    _sweepTimer = null;
    _unicastTimer = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Stops and releases the peer stream.
  Future<void> close() async {
    await stop();
    await _registry.close();
  }

  /// Sends the probe to every unicast target the provider names, once.
  ///
  /// A provider that fails is not a discovery failure: the broadcast path
  /// carries on regardless, and the next round asks again. Targets are
  /// deduplicated and capped so a large directory cannot turn one round
  /// into a flood.
  Future<void> _probeUnicastTargets() async {
    final provider = unicastTargets;
    if (!_running || provider == null) return;
    final List<InternetAddress> targets;
    try {
      targets = await provider();
    } on Object {
      return;
    }
    final seen = <String>{};
    var sent = 0;
    for (final target in targets) {
      if (sent >= maxUnicastTargets) break;
      if (!seen.add(target.address)) continue;
      transport.send(_probeBytes, address: target, port: discoveryPort);
      sent++;
    }
  }

  /// Whether [peer] has ever been heard at [address].
  static bool _heardAt(DiscoveredPeer peer, InternetAddress address) => peer
      .addresses
      .any((sighting) => sighting.address.address == address.address);

  void _onDatagram(BeaconDatagram datagram) {
    final beacon = datagram.beacon;
    // A datagram of ours read back off the interface, or another host claiming
    // this Device's Fingerprint. Not a peer either way.
    if (beacon.nonce == _nonce) return;
    if (beacon.device.fingerprint == local.fingerprint) return;
    _registry.observe(device: beacon.device, address: datagram.address);
    if (beacon.kind == BeaconKind.probe) {
      // Answer directly so the prober learns this Device in one round trip
      // rather than waiting out an announce period.
      transport.send(
        _announceBytes,
        address: datagram.address,
        port: datagram.port,
      );
    }
  }
}

/// A fresh, unpredictable Nonce for the beacon payload.
String randomNonce(Random? random) {
  final bytes = randomBytes(16, random: random);
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

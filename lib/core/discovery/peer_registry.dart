import 'dart:async';
import 'dart:io';

import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';

/// A Device seen on the local link, and where to reach it.
final class DiscoveredPeer {
  DiscoveredPeer({
    required this.device,
    required this.address,
    required this.lastSeen,
  });

  /// What the peer announced about itself.
  ///
  /// Unverified: it is whatever that Device chose to say, exactly like the
  /// descriptor in a handshake. An Alias is presentation, never identity.
  final DeviceDescriptor device;

  /// The address the beacon arrived from.
  ///
  /// Taken from the datagram's source rather than from its payload, so it is
  /// where a Session can actually be opened. A peer's claim about its own
  /// address would be trivially forgeable and often simply wrong behind NAT or
  /// on a multi-homed host.
  final InternetAddress address;

  /// When this peer was last heard from.
  final DateTime lastSeen;

  /// The peer's stable identity.
  Fingerprint get fingerprint => device.fingerprint;

  /// The TCP port to open a Session to, or null if the peer accepts none.
  int? get sessionPort => device.listenPort;

  /// Whether a Session can be opened to this peer at all.
  bool get isReachable => device.listenPort != null;

  @override
  String toString() =>
      'DiscoveredPeer(${device.fingerprint.short()}, ${address.address}, '
      'lastSeen: ${lastSeen.toIso8601String()})';
}

/// The set of Devices currently visible on the local link.
///
/// Peers are keyed by [Fingerprint], never by address: two Devices can share an
/// address behind NAT, and one Device can appear at several addresses. The
/// registry keeps the most recent sighting of each and drops one that stops
/// announcing, which is how a Device that was switched off or roamed away
/// leaves the list.
final class PeerRegistry {
  PeerRegistry({
    required this.localFingerprint,
    this.ttl = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// This Device's own Fingerprint, which is never a peer.
  final Fingerprint localFingerprint;

  /// How long a peer stays listed after its last sighting.
  final Duration ttl;

  final DateTime Function() _clock;
  final Map<String, DiscoveredPeer> _peers = {};
  final StreamController<List<DiscoveredPeer>> _changes =
      StreamController<List<DiscoveredPeer>>.broadcast();

  /// Emits the full peer list whenever it changes.
  ///
  /// Broadcast, so several consumers can watch it; a consumer that needs the
  /// current list without waiting for the next change reads [peers].
  ///
  /// Only a change a user could see is emitted — a peer appearing, an Alias
  /// changing, a Device moving address, or a peer expiring. A peer merely
  /// re-announcing does not, or a Device with a three-second announce period
  /// would push a rebuild every three seconds for no reason.
  Stream<List<DiscoveredPeer>> get changes => _changes.stream;

  /// The current peer list, most recently seen first.
  List<DiscoveredPeer> get peers {
    final list = _peers.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return List.unmodifiable(list);
  }

  /// Records that [device] is at [address] right now.
  ///
  /// Returns true if this changed the visible list. A beacon from this Device's
  /// own Fingerprint is ignored: it is either a datagram of ours read back off
  /// the interface, or a host claiming an identity that is already taken, and
  /// either way it is not a peer.
  bool observe({
    required DeviceDescriptor device,
    required InternetAddress address,
  }) {
    if (device.fingerprint == localFingerprint) return false;
    final key = device.fingerprint.hex;
    final previous = _peers[key];
    final isNew = previous == null;
    final changed =
        previous != null &&
        (previous.address.address != address.address ||
            previous.device.alias != device.alias ||
            previous.device.listenPort != device.listenPort ||
            previous.device.platform != device.platform);
    _peers[key] = DiscoveredPeer(
      device: device,
      address: address,
      lastSeen: _clock(),
    );
    if (isNew || changed) {
      _emit();
      return true;
    }
    return false;
  }

  /// Drops every peer whose last sighting is older than [ttl].
  ///
  /// Returns the Fingerprints that were dropped.
  List<Fingerprint> expire() {
    final now = _clock();
    final dropped = <DiscoveredPeer>[];
    _peers.removeWhere((_, peer) {
      final silent = now.difference(peer.lastSeen) > ttl;
      if (silent) dropped.add(peer);
      return silent;
    });
    if (dropped.isNotEmpty) _emit();
    return List.unmodifiable(dropped.map((peer) => peer.fingerprint));
  }

  /// Forgets every peer, emitting an empty list.
  void clear() {
    if (_peers.isEmpty) return;
    _peers.clear();
    _emit();
  }

  Future<void> close() async {
    if (!_changes.isClosed) unawaited(_changes.close());
  }

  void _emit() {
    if (_changes.isClosed) return;
    _changes.add(peers);
  }
}

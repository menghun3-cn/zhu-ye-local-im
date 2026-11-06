import 'dart:async';
import 'dart:io';

import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';

/// One address a peer was heard at, and when it was last heard there.
final class PeerAddress {
  const PeerAddress({required this.address, required this.lastSeen});

  /// The address the beacon arrived from.
  ///
  /// Taken from the datagram's source rather than from its payload, so it is
  /// where a Session can actually be opened. A peer's claim about its own
  /// address would be trivially forgeable and often simply wrong behind NAT or
  /// on a multi-homed host.
  final InternetAddress address;

  /// When a beacon last arrived from [address].
  final DateTime lastSeen;
}

/// A Device seen on the local link, and where to reach it.
final class DiscoveredPeer {
  DiscoveredPeer({
    required this.device,
    required List<PeerAddress> addresses,
    required this.lastSeen,
  }) : addresses = List.unmodifiable(addresses);

  /// What the peer announced about itself.
  ///
  /// Unverified: it is whatever that Device chose to say, exactly like the
  /// descriptor in a handshake. An Alias is presentation, never identity.
  final DeviceDescriptor device;

  /// Every address the peer was heard at, freshest first.
  ///
  /// A Device reachable over both a LAN and a VPN is heard on each, and each
  /// sighting ages out on its own: the list shrinks to the addresses that
  /// still answer rather than flipping between them on every announce.
  final List<PeerAddress> addresses;

  /// The freshest address the peer was heard at.
  InternetAddress get address => addresses.first.address;

  /// When this peer was last heard from, on any address.
  final DateTime lastSeen;

  /// The peer's stable identity.
  Fingerprint get fingerprint => device.fingerprint;

  /// The TCP port to open a Session to, or null if the peer accepts none.
  int? get sessionPort => device.listenPort;

  /// The TCP port to send a Pairing request to, or null if it announced none.
  int? get pairingPort => device.pairingPort;

  /// Whether a Session can be opened to this peer at all.
  bool get isReachable => device.listenPort != null;

  @override
  String toString() =>
      'DiscoveredPeer(${device.fingerprint.short()}, ${address.address}, '
      'lastSeen: ${lastSeen.toIso8601String()})';
}

/// The set of Devices currently visible, on any link they can be reached over.
///
/// Peers are keyed by [Fingerprint], never by address: two Devices can share an
/// address behind NAT, and one Device can appear at several addresses — a LAN
/// address and a VPN one at the same time. Each address is a sighting with its
/// own age, so a peer stays listed while any of them is fresh and shrinks back
/// to the reachable ones when the rest go quiet.
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
  ///
  /// The sighting at [address] is refreshed and every other sighting keeps
  /// its own age. What counts as a visible change is the peer appearing, its
  /// announced facts changing, or the *set* of addresses changing — a peer
  /// merely heard again at an address it already had, or heard at a second
  /// address while the first still answers, is not an event a user could see.
  bool observe({
    required DeviceDescriptor device,
    required InternetAddress address,
  }) {
    if (device.fingerprint == localFingerprint) return false;
    final key = device.fingerprint.hex;
    final previous = _peers[key];
    final now = _clock();
    final sightings = <String, PeerAddress>{
      for (final sighting in previous?.addresses ?? const <PeerAddress>[])
        sighting.address.address: sighting,
      address.address: PeerAddress(address: address, lastSeen: now),
    };
    final peer = _assemble(
      device: device,
      sightings: sightings.values,
      lastSeen: now,
      freshest: address,
    );
    final changed = previous == null || !_sameVisible(previous, peer);
    _peers[key] = peer;
    if (changed) {
      _emit();
      return true;
    }
    return false;
  }

  /// Drops every sighting older than [ttl], and the peer when none remain.
  ///
  /// A peer heard on two links loses them one at a time: the address that
  /// stopped answering expires first, and the peer itself only once the last
  /// sighting is gone.
  ///
  /// Returns the Fingerprints that were dropped.
  List<Fingerprint> expire() {
    final now = _clock();
    final dropped = <DiscoveredPeer>[];
    var changed = false;
    for (final key in _peers.keys.toList()) {
      final peer = _peers[key]!;
      final fresh = [
        for (final sighting in peer.addresses)
          if (now.difference(sighting.lastSeen) <= ttl) sighting,
      ];
      if (fresh.isEmpty) {
        _peers.remove(key);
        dropped.add(peer);
        changed = true;
        continue;
      }
      if (fresh.length != peer.addresses.length) {
        _peers[key] = _assemble(
          device: peer.device,
          sightings: fresh,
          lastSeen: _latest(fresh),
        );
        changed = true;
      }
    }
    if (changed) _emit();
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

  /// Builds the peer a set of sightings describes, freshest address first.
  ///
  /// The ordering is part of the value: [DiscoveredPeer.address] is the first
  /// sighting. Clocks tick coarsely enough that two announces can share a
  /// timestamp, so ties are broken twice — first for [freshest], the address
  /// just heard, then by the address itself, so the order never depends on
  /// iteration luck.
  static DiscoveredPeer _assemble({
    required DeviceDescriptor device,
    required Iterable<PeerAddress> sightings,
    required DateTime lastSeen,
    InternetAddress? freshest,
  }) {
    final ordered = sightings.toList()
      ..sort((a, b) {
        final byTime = b.lastSeen.compareTo(a.lastSeen);
        if (byTime != 0) return byTime;
        if (freshest != null) {
          final aFresh = a.address.address == freshest.address;
          final bFresh = b.address.address == freshest.address;
          if (aFresh != bFresh) return aFresh ? -1 : 1;
        }
        return a.address.address.compareTo(b.address.address);
      });
    return DiscoveredPeer(
      device: device,
      addresses: ordered,
      lastSeen: lastSeen,
    );
  }

  /// The most recent sighting time in [sightings].
  static DateTime _latest(Iterable<PeerAddress> sightings) {
    var latest = sightings.first.lastSeen;
    for (final sighting in sightings) {
      if (sighting.lastSeen.isAfter(latest)) latest = sighting.lastSeen;
    }
    return latest;
  }

  /// Whether two snapshots differ in anything a user could see.
  ///
  /// Deliberately blind to *when* a sighting was refreshed and to which of
  /// several addresses is freshest: both move on every announce for a peer
  /// reachable over two links, and neither is a change worth an event.
  static bool _sameVisible(DiscoveredPeer a, DiscoveredPeer b) {
    final before = a.device;
    final after = b.device;
    if (before.alias != after.alias ||
        before.listenPort != after.listenPort ||
        before.pairingPort != after.pairingPort ||
        before.platform != after.platform) {
      return false;
    }
    if (a.addresses.length != b.addresses.length) return false;
    final heard = {
      for (final sighting in a.addresses) sighting.address.address,
    };
    return b.addresses.every(
      (sighting) => heard.contains(sighting.address.address),
    );
  }
}

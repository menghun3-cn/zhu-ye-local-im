import 'dart:async';
import 'dart:io';

import '../protocol/frame.dart';
import 'beacon.dart';

/// A beacon and where it came from.
final class BeaconDatagram {
  const BeaconDatagram({
    required this.beacon,
    required this.address,
    required this.port,
  });

  /// The decoded beacon.
  final Beacon beacon;

  /// The sender's address, as the socket reported it.
  final InternetAddress address;

  /// The sender's UDP source port, which is what an answer is addressed to.
  ///
  /// It is an ephemeral port rather than [discoveryPort]: a socket bound to
  /// [discoveryPort] still sends from whatever port the stack assigns, so a
  /// reply has to go back to the source, not to the well-known port. The reply
  /// still arrives at the well-known port, because that is where the sender's
  /// socket is bound.
  final int port;

  @override
  String toString() => 'BeaconDatagram(${address.address}:$port, $beacon)';
}

/// Datagram plumbing for discovery.
///
/// The same seam as `ByteTransport`, for the same reason: the discovery policy
/// — when to announce, when to answer, when to drop a peer — is exercised over
/// a real socket and purely in memory with no code path difference.
///
/// Implementations decode the datagram before delivering it and **drop a
/// datagram that does not decode**. A stranger on the link can send a malformed
/// packet at any time; taking the receive loop down over one would turn a
/// nuisance into a denial of discovery, and there is nothing the layer above
/// could do about it anyway. [Beacon.decode] is where malformed input is
/// rejected, and it is tested directly.
abstract interface class BeaconTransport {
  /// Beacons arriving from the link, decoded. Single-subscription.
  Stream<BeaconDatagram> get received;

  /// Sends [datagram] to one Device directly, to answer its probe.
  ///
  /// Delivery is asynchronous, and an implementation is expected to *deliver*.
  /// A socket can refuse a datagram outright, and a dropped one is not a
  /// failure any caller could notice — it just looks like a Device that did not
  /// answer. An implementation that hands the datagram to a socket must
  /// therefore deal with refusal rather than ignore it.
  void send(
    List<int> datagram, {
    required InternetAddress address,
    required int port,
  });

  /// Sends [datagram] to every Device on the local link.
  ///
  /// One send per target, and every one of them is expected to arrive:
  /// "every Device" is not satisfied by the target that happened to go first.
  void broadcast(List<int> datagram);

  /// Releases the socket. Idempotent.
  Future<void> close();
}

/// A set of in-memory [BeaconTransport]s joined to each other, for tests.
///
/// [broadcast] reaches every member except the sender — including the sender's
/// own datagrams being visible to itself is behaviour a real socket may or may
/// not exhibit, so the hub deliberately does not model it. The self-beacon case
/// is covered directly by the nonce check and its own test.
final class MemoryBeaconHub {
  MemoryBeaconHub() {
    a = _add();
    b = _add();
  }

  /// The first member of the pair.
  late final BeaconTransport a;

  /// The second member of the pair.
  late final BeaconTransport b;

  final List<_MemoryBeaconTransport> _members = [];
  int _nextPort = 41000;

  /// Adds another member, for a three-or-more-Device test.
  BeaconTransport join() => _add();

  BeaconTransport _add() {
    final transport = _MemoryBeaconTransport(this, _nextPort);
    _nextPort += 1;
    _members.add(transport);
    return transport;
  }

  void _broadcastFrom(_MemoryBeaconTransport from, List<int> datagram) {
    for (final member in List.of(_members)) {
      if (identical(member, from) || member.isClosed) continue;
      member.deliver(datagram, from.port);
    }
  }

  void _sendTo(_MemoryBeaconTransport from, List<int> datagram, int port) {
    for (final member in List.of(_members)) {
      if (member.port == port && !member.isClosed) {
        member.deliver(datagram, from.port);
        return;
      }
    }
  }
}

final class _MemoryBeaconTransport implements BeaconTransport {
  _MemoryBeaconTransport(this._hub, this.port);

  final MemoryBeaconHub _hub;
  final int port;

  /// Broadcast, so a datagram delivered while nobody is listening is **dropped**
  /// rather than buffered.
  ///
  /// A Device that has not [DiscoveryService.start]ed is not on the link yet,
  /// and a test that asks "did this Device hear that?" needs a precise answer.
  /// Buffering would deliver, on subscribe, datagrams the service never had a
  /// chance to see — turning a test's ordering into an accident.
  final StreamController<BeaconDatagram> _received =
      StreamController<BeaconDatagram>.broadcast();

  bool isClosed = false;

  @override
  Stream<BeaconDatagram> get received => _received.stream;

  /// Hands [datagram] to this member, as a real socket would.
  void deliver(List<int> datagram, int fromPort) {
    if (isClosed) return;
    final Beacon beacon;
    try {
      beacon = Beacon.decode(datagram);
    } on ProtocolException {
      return;
    }
    _received.add(
      BeaconDatagram(
        beacon: beacon,
        address: InternetAddress.loopbackIPv4,
        port: fromPort,
      ),
    );
  }

  @override
  void send(
    List<int> datagram, {
    required InternetAddress address,
    required int port,
  }) => _hub._sendTo(this, datagram, port);

  @override
  void broadcast(List<int> datagram) => _hub._broadcastFrom(this, datagram);

  @override
  Future<void> close() async {
    isClosed = true;
    if (!_received.isClosed) unawaited(_received.close());
  }
}

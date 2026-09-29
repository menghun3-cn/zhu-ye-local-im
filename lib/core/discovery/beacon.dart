import 'dart:convert';
import 'dart:typed_data';

import '../identity/device_descriptor.dart';
import '../protocol/frame.dart';

/// The wire version of the beacon payload.
///
/// Bumping this is how a future discovery protocol avoids silently
/// interoperating with this one: a beacon of an unknown version is rejected
/// outright rather than half-understood.
const int beaconVersion = 1;

/// The UDP port every Device announces on.
///
/// Fixed so a Device is discoverable with no configuration: a probe has to
/// reach a port the peer chose in advance, and there is no rendezvous service
/// to ask. Chosen from the IANA dynamic range and not known to collide with a
/// common service.
const int discoveryPort = 47654;

/// The largest beacon datagram this implementation will accept, in bytes.
///
/// Comfortably inside a 1500-byte Ethernet MTU so a beacon is never fragmented,
/// and small enough that a hostile sender cannot make a reader allocate much.
const int maxBeaconBytes = 1024;

/// The shortest Nonce this implementation accepts, in characters.
const int minNonceLength = 8;

/// What a beacon is asking for.
enum BeaconKind {
  /// "I am here — answer if you are too." Sent when a Device starts, so
  /// discovery takes one round trip instead of waiting out an announce period.
  probe('probe'),

  /// "I am here." Sent on a schedule, and in answer to a [probe].
  announce('announce');

  const BeaconKind(this.wireName);

  /// The value used on the wire.
  final String wireName;

  /// Resolves a wire value, or throws [ProtocolException] if unknown.
  static BeaconKind fromWireName(String value) {
    for (final kind in BeaconKind.values) {
      if (kind.wireName == value) return kind;
    }
    throw ProtocolException('unknown beacon kind "$value"');
  }
}

/// One Device's presence, as announced over UDP.
///
/// A beacon is deliberately **unauthenticated**: anyone on the same link can
/// send one and anyone can read one. It therefore carries only what a stranger
/// could already work out by watching the link — that some Device exists, what
/// it calls itself, and where to open a TCP Session — and never the Pairing
/// Secret or anything derived from it. Knowing a Device is present is not
/// knowing it is trusted; that decision is the handshake's, not discovery's.
final class Beacon {
  const Beacon({required this.kind, required this.device, required this.nonce});

  /// Whether this beacon is asking for an answer or simply stating presence.
  final BeaconKind kind;

  /// What the sending Device announced about itself.
  final DeviceDescriptor device;

  /// A per-Device random value, constant for the life of the process.
  ///
  /// It exists so a Device can recognise and discard its own datagrams: a
  /// broadcast read back off the interface is byte-identical to a peer's, and
  /// without a nonce its own beacon would be indistinguishable from a peer that
  /// happened to share its address.
  final String nonce;

  /// Encodes this beacon into a datagram.
  Uint8List encode() {
    final bytes = utf8.encode(
      jsonEncode({
        'v': beaconVersion,
        'k': kind.wireName,
        'n': nonce,
        'device': device.toJson(),
      }),
    );
    if (bytes.length > maxBeaconBytes) {
      throw ProtocolException(
        'beacon of ${bytes.length} bytes exceeds the $maxBeaconBytes byte '
        'ceiling',
      );
    }
    return Uint8List.fromList(bytes);
  }

  /// Decodes a datagram, or throws [ProtocolException] if it is not a beacon
  /// this build understands.
  ///
  /// Every failure is a [ProtocolException] rather than the [FormatException]
  /// the JSON layer raises, because a caller handling datagrams from strangers
  /// wants one error type meaning "this was not a usable beacon".
  static Beacon decode(List<int> datagram) {
    if (datagram.length > maxBeaconBytes) {
      throw ProtocolException(
        'beacon of ${datagram.length} bytes exceeds the $maxBeaconBytes byte '
        'ceiling',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(datagram));
    } on FormatException catch (error) {
      throw ProtocolException('beacon is not UTF-8 JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ProtocolException('beacon payload must be a JSON object');
    }
    final version = decoded['v'];
    if (version != beaconVersion) {
      throw ProtocolException(
        'beacon speaks version $version, this build speaks $beaconVersion',
      );
    }
    final kind = decoded['k'];
    if (kind is! String) {
      throw const ProtocolException('beacon "k" must be a string');
    }
    final nonce = decoded['n'];
    if (nonce is! String || nonce.length < minNonceLength) {
      throw ProtocolException(
        'beacon "n" must be a string of at least $minNonceLength characters',
      );
    }
    final device = decoded['device'];
    if (device is! Map) {
      throw const ProtocolException('beacon "device" must be an object');
    }
    final DeviceDescriptor descriptor;
    try {
      descriptor = DeviceDescriptor.fromJson(device.cast<String, Object?>());
    } on FormatException catch (error) {
      throw ProtocolException('beacon device is malformed: ${error.message}');
    }
    return Beacon(
      kind: BeaconKind.fromWireName(kind),
      device: descriptor,
      nonce: nonce,
    );
  }

  @override
  String toString() => 'Beacon(${kind.wireName}, $device)';
}

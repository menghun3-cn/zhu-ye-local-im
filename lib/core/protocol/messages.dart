import 'dart:typed_data';

import '../clipboard/clipboard_capability.dart';
import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';

/// The wire protocol version implemented by this build.
///
/// Bumped only for changes a previous build would misread rather than merely
/// not understand.
const int wireProtocolVersion = 1;

/// The kind of Payload a Transfer carries.
enum PayloadKind {
  /// A single block of text or a link.
  text('text'),

  /// One or more files.
  file('file'),

  /// Clipboard content captured by Mirroring.
  clipboard('clipboard');

  const PayloadKind(this.wireName);

  /// The value used on the wire.
  final String wireName;

  /// Resolves a wire value, or throws [FormatException] if unknown.
  static PayloadKind fromWireName(String value) {
    for (final kind in PayloadKind.values) {
      if (kind.wireName == value) return kind;
    }
    throw FormatException('unknown payload kind "$value"');
  }
}

/// Why a Transfer was refused or abandoned.
enum RejectionReason {
  /// The receiving user declined.
  declined('declined'),

  /// The receiver has no room, or the size is unacceptable.
  refused('refused'),

  /// The sender and receiver speak incompatible protocol versions.
  incompatible('incompatible'),

  /// A digest did not match the bytes received.
  corrupt('corrupt'),

  /// The receiving side encountered an I/O error writing the payload.
  ioError('ioError');

  const RejectionReason(this.wireName);

  /// The value used on the wire.
  final String wireName;

  /// Resolves a wire value, or throws [FormatException] if unknown.
  static RejectionReason fromWireName(String value) {
    for (final reason in RejectionReason.values) {
      if (reason.wireName == value) return reason;
    }
    throw FormatException('unknown rejection reason "$value"');
  }
}

/// One addressable item inside an Offer.
final class PayloadItem {
  const PayloadItem({
    required this.id,
    required this.name,
    required this.size,
    this.digest,
  });

  /// Identifies the item within its Transfer.
  final String id;

  /// The sender's name for the item. Untrusted: sanitise before use.
  final String name;

  /// Declared size in bytes.
  final int size;

  /// SHA-256 of the item's bytes as lowercase hex.
  ///
  /// Null only for a kind that has no byte stream of its own.
  final String? digest;

  /// Whether [digest] is present and well-formed.
  bool get hasDigest => digest != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    if (digest != null) 'digest': digest,
  };

  static PayloadItem fromJson(Map<String, Object?> json) => PayloadItem(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    size: _int(json, 'size'),
    digest: _optionalString(json, 'digest'),
  );

  @override
  String toString() => 'PayloadItem($id, "$name", $size bytes)';
}

/// The identity and capabilities a Device announces in a handshake.
///
/// A [DeviceDescriptor] plus the per-connection key material. Splitting the two
/// keeps the stable part of a Device's identity usable on its own — for a known
/// Device list, a favourites list — without carrying a dead ephemeral key.
final class PeerHandshake {
  const PeerHandshake({
    required this.device,
    required this.ephemeralPublicKey,
    required this.nonce,
    this.protocolVersion = wireProtocolVersion,
  });

  /// The announcing Device's stable identity.
  final DeviceDescriptor device;

  /// A per-connection X25519 public key, used once and discarded.
  final Uint8List ephemeralPublicKey;

  /// Random bytes mixed into key derivation so a replayed handshake cannot
  /// reproduce an earlier session key.
  final Uint8List nonce;

  /// The wire protocol version the peer implements.
  ///
  /// Carried on every handshake rather than assumed: a version mismatch must
  /// stop the Session before any payload is interpreted, not surface later as
  /// a mysterious decode failure.
  final int protocolVersion;

  /// The announcing Device's stable identity.
  Fingerprint get fingerprint => device.fingerprint;

  /// The human-readable name the Device shows to others.
  String get alias => device.alias;

  /// The platform the Device runs on.
  DevicePlatform get platform => device.platform;

  /// What the Device can do with its clipboard.
  ClipboardCapability get capability => device.capability;

  /// The port the Device listens on, if it is accepting connections.
  int? get listenPort => device.listenPort;

  Map<String, Object?> toJson() => {
    ...device.toJson(),
    'pv': protocolVersion,
    'eph': toBase64Url(ephemeralPublicKey),
    'nonce': toBase64Url(nonce),
  };

  static PeerHandshake fromJson(Map<String, Object?> json) => PeerHandshake(
    device: DeviceDescriptor.fromJson(json),
    ephemeralPublicKey: fromBase64Url(_string(json, 'eph')),
    nonce: fromBase64Url(_string(json, 'nonce')),
    protocolVersion: _int(json, 'pv'),
  );

  @override
  String toString() =>
      'PeerHandshake(${fingerprint.short()}, "$alias", ${platform.wireName})';
}

/// A decoded wire message.
sealed class WireMessage {
  const WireMessage();

  /// The value of the `t` discriminator.
  String get type;

  /// The message body, excluding the discriminator.
  Map<String, Object?> toJson();

  /// The full body, discriminator included.
  Map<String, Object?> encode() => {'t': type, ...toJson()};

  /// Decodes [json], or throws [FormatException] if it is not a message this
  /// build understands.
  static WireMessage decode(Map<String, Object?> json) {
    final type = _string(json, 't');
    return switch (type) {
      'hello' => HelloMessage.fromJson(json),
      'helloAck' => HelloAckMessage.fromJson(json),
      'offer' => OfferMessage.fromJson(json),
      'accept' => AcceptMessage.fromJson(json),
      'reject' => RejectMessage.fromJson(json),
      'complete' => CompleteMessage.fromJson(json),
      'verified' => VerifiedMessage.fromJson(json),
      'failed' => FailedMessage.fromJson(json),
      'cancel' => CancelMessage.fromJson(json),
      'clipboard' => ClipboardMessage.fromJson(json),
      'confirm' => SessionConfirmMessage.fromJson(json),
      'pairAdmit' => PairAdmitMessage.fromJson(json),
      'pairConfirmed' => PairConfirmedMessage.fromJson(json),
      'error' => ErrorMessage.fromJson(json),
      _ => throw FormatException('unknown message type "$type"'),
    };
  }
}

/// Opens a Session: the initiator's identity and ephemeral key.
final class HelloMessage extends WireMessage {
  const HelloMessage(this.peer);

  /// The initiator's handshake payload.
  final PeerHandshake peer;

  @override
  String get type => 'hello';

  @override
  Map<String, Object?> toJson() => peer.toJson();

  static HelloMessage fromJson(Map<String, Object?> json) =>
      HelloMessage(PeerHandshake.fromJson(json));
}

/// Answers a [HelloMessage] with the responder's own payload.
final class HelloAckMessage extends WireMessage {
  const HelloAckMessage(this.peer);

  /// The responder's handshake payload.
  final PeerHandshake peer;

  @override
  String get type => 'helloAck';

  @override
  Map<String, Object?> toJson() => peer.toJson();

  static HelloAckMessage fromJson(Map<String, Object?> json) =>
      HelloAckMessage(PeerHandshake.fromJson(json));
}

/// Proposes a Transfer, before any bytes move.
final class OfferMessage extends WireMessage {
  const OfferMessage({
    required this.transferId,
    required this.kind,
    required this.items,
    this.text,
  });

  /// Identifies this Transfer for its whole life.
  final String transferId;

  /// What kind of Payload is on offer.
  final PayloadKind kind;

  /// The items the sender wants to deliver.
  final List<PayloadItem> items;

  /// The body, for [PayloadKind.text] and [PayloadKind.clipboard].
  ///
  /// Text travels inside the Offer rather than as a chunk stream: it is small
  /// enough that a second round trip would cost more than it saves.
  final String? text;

  /// Total declared bytes across [items].
  int get totalBytes => items.fold(0, (sum, item) => sum + item.size);

  @override
  String get type => 'offer';

  @override
  Map<String, Object?> toJson() => {
    'tid': transferId,
    'kind': kind.wireName,
    'items': items.map((item) => item.toJson()).toList(),
    if (text != null) 'text': text,
  };

  static OfferMessage fromJson(Map<String, Object?> json) => OfferMessage(
    transferId: _string(json, 'tid'),
    kind: PayloadKind.fromWireName(_string(json, 'kind')),
    items: _list(json, 'items')
        .map((item) => PayloadItem.fromJson(_asObject(item, 'items[]')))
        .toList(growable: false),
    text: _optionalString(json, 'text'),
  );
}

/// Accepts an Offer, naming which items to send and what is already held.
final class AcceptMessage extends WireMessage {
  const AcceptMessage({
    required this.transferId,
    required this.acceptedItemIds,
    this.resumeOffsets = const {},
  });

  /// The Transfer being accepted.
  final String transferId;

  /// Items the receiver will take. Anything omitted is refused.
  final List<String> acceptedItemIds;

  /// Per-item byte counts the receiver already holds, so the sender can skip
  /// them. This is what makes an interrupted Transfer resumable.
  final Map<String, int> resumeOffsets;

  @override
  String get type => 'accept';

  @override
  Map<String, Object?> toJson() => {
    'tid': transferId,
    'items': acceptedItemIds,
    if (resumeOffsets.isNotEmpty) 'resume': resumeOffsets,
  };

  static AcceptMessage fromJson(Map<String, Object?> json) => AcceptMessage(
    transferId: _string(json, 'tid'),
    acceptedItemIds: _list(
      json,
      'items',
    ).map((item) => _asString(item, 'items[]')).toList(growable: false),
    resumeOffsets: _optionalIntMap(json, 'resume'),
  );
}

/// Declines an Offer.
final class RejectMessage extends WireMessage {
  const RejectMessage({required this.transferId, required this.reason});

  /// The Transfer being declined.
  final String transferId;

  /// Why it was declined.
  final RejectionReason reason;

  @override
  String get type => 'reject';

  @override
  Map<String, Object?> toJson() => {
    'tid': transferId,
    'reason': reason.wireName,
  };

  static RejectMessage fromJson(Map<String, Object?> json) => RejectMessage(
    transferId: _string(json, 'tid'),
    reason: RejectionReason.fromWireName(_string(json, 'reason')),
  );
}

/// Sent by the sender once every byte of every accepted item is on the wire.
final class CompleteMessage extends WireMessage {
  const CompleteMessage({required this.transferId});

  /// The Transfer that finished sending.
  final String transferId;

  @override
  String get type => 'complete';

  @override
  Map<String, Object?> toJson() => {'tid': transferId};

  static CompleteMessage fromJson(Map<String, Object?> json) =>
      CompleteMessage(transferId: _string(json, 'tid'));
}

/// Sent by the receiver once it has verified every accepted item.
final class VerifiedMessage extends WireMessage {
  const VerifiedMessage({required this.transferId, required this.digests});

  /// The Transfer that was verified.
  final String transferId;

  /// Item id to SHA-256 of the received bytes, as lowercase hex.
  final Map<String, String> digests;

  @override
  String get type => 'verified';

  @override
  Map<String, Object?> toJson() => {'tid': transferId, 'digests': digests};

  static VerifiedMessage fromJson(Map<String, Object?> json) => VerifiedMessage(
    transferId: _string(json, 'tid'),
    digests: _optionalStringMap(json, 'digests'),
  );
}

/// Sent by the receiver when an item's bytes do not match its digest.
final class FailedMessage extends WireMessage {
  const FailedMessage({
    required this.transferId,
    required this.reason,
    this.itemId,
  });

  /// The Transfer that failed.
  final String transferId;

  /// Why it failed.
  final RejectionReason reason;

  /// The offending item, when the failure is item-scoped.
  final String? itemId;

  @override
  String get type => 'failed';

  @override
  Map<String, Object?> toJson() => {
    'tid': transferId,
    'reason': reason.wireName,
    if (itemId != null) 'item': itemId,
  };

  static FailedMessage fromJson(Map<String, Object?> json) => FailedMessage(
    transferId: _string(json, 'tid'),
    reason: RejectionReason.fromWireName(_string(json, 'reason')),
    itemId: _optionalString(json, 'item'),
  );
}

/// Abandons a Transfer, from either side.
final class CancelMessage extends WireMessage {
  const CancelMessage({required this.transferId, required this.reason});

  /// The Transfer being abandoned.
  final String transferId;

  /// Why it was abandoned.
  final RejectionReason reason;

  @override
  String get type => 'cancel';

  @override
  Map<String, Object?> toJson() => {
    'tid': transferId,
    'reason': reason.wireName,
  };

  static CancelMessage fromJson(Map<String, Object?> json) => CancelMessage(
    transferId: _string(json, 'tid'),
    reason: RejectionReason.fromWireName(_string(json, 'reason')),
  );
}

/// Carries a ClipboardEntry to a peer inside the same Owner Group.
final class ClipboardMessage extends WireMessage {
  const ClipboardMessage({
    required this.entryId,
    required this.originFingerprint,
    required this.text,
    required this.capturedAt,
  });

  /// Identifies the entry, so a Device can recognise its own content coming
  /// back and refuse to re-mirror it.
  final String entryId;

  /// The Device the content was copied on.
  final Fingerprint originFingerprint;

  /// The clipboard text.
  final String text;

  /// When the copy was observed, in UTC.
  final DateTime capturedAt;

  @override
  String get type => 'clipboard';

  @override
  Map<String, Object?> toJson() => {
    'entry': entryId,
    'origin': originFingerprint.hex,
    'text': text,
    'at': capturedAt.toUtc().toIso8601String(),
  };

  static ClipboardMessage fromJson(Map<String, Object?> json) =>
      ClipboardMessage(
        entryId: _string(json, 'entry'),
        originFingerprint: Fingerprint(_string(json, 'origin')),
        text: _string(json, 'text'),
        capturedAt: _dateTime(json, 'at'),
      );
}

/// Confirms that a Session's keys are shared, before the Session exists.
///
/// Sent once by each side at the end of the handshake, encrypted with the
/// keys the handshake derived. Both Devices derive those keys from the
/// Pairing Secret, so a peer holding a different secret cannot produce a
/// record that decrypts: this message is how "we both hold the same secret"
/// stops being an assumption and becomes something the handshake checked.
///
/// It carries nothing. Its authentication tag is the whole payload.
final class SessionConfirmMessage extends WireMessage {
  const SessionConfirmMessage();

  @override
  String get type => 'confirm';

  @override
  Map<String, Object?> toJson() => const {};

  static SessionConfirmMessage fromJson(Map<String, Object?> json) =>
      const SessionConfirmMessage();
}

/// Carries a Device's Owner public key into a Pairing, signed, along with the
/// group secret and roster when the sender already belongs to a group.
///
/// This is what turns the Fingerprint in a handshake from a claim into a fact:
/// the receiver hashes [publicKey] and requires it to equal the Fingerprint the
/// peer announced, then verifies [signature] over the Pairing context — which
/// only a Device holding that private key, inside *this* Pairing session, could
/// have produced.
final class PairAdmitMessage extends WireMessage {
  const PairAdmitMessage({
    required this.publicKey,
    required this.alias,
    required this.signature,
    this.groupSecret,
    this.members = const [],
  });

  /// The sender's Ed25519 public key, raw bytes.
  final Uint8List publicKey;

  /// The Alias the sender wants to be known by. Untrusted: sanitise on use.
  final String alias;

  /// Ed25519 signature over the Pairing context.
  final Uint8List signature;

  /// The session secret of the group the sender belongs to, when it has one.
  ///
  /// Null for the Device that is forming a group: two Devices pairing for the
  /// first time each derive the same secret from the Pairing code, so nothing
  /// has to travel. A Device *joining* an existing group adopts whatever the
  /// group's owner sends here — sealed by the handshake, so it never crosses
  /// the network in the clear.
  final Uint8List? groupSecret;

  /// The Devices the sender's Owner Group contains, apart from the sender.
  ///
  /// Sent so a Device joining an established group learns the whole group and
  /// not only the Device it paired with. Without this, the third Device in a
  /// group would refuse Mirror entries from the second, because the gate that
  /// decides who may mirror reads the group and the group would name only the
  /// Device it paired with.
  ///
  /// A claim like everything else here, but not a *deciding* one: the sender
  /// signs it, and the group secret is the same either way — this only decides
  /// who the receiver knows about, not who can reach it.
  final List<Fingerprint> members;

  /// The Fingerprint this message's key must hash to.
  Fingerprint get fingerprint => Fingerprint.ofPublicKey(publicKey);

  @override
  String get type => 'pairAdmit';

  @override
  Map<String, Object?> toJson() => {
    'key': toBase64Url(publicKey),
    'alias': alias,
    'sig': toBase64Url(signature),
    if (groupSecret != null) 'group': toBase64Url(groupSecret!),
    if (members.isNotEmpty)
      'members': [for (final member in members) member.hex],
  };

  static PairAdmitMessage fromJson(Map<String, Object?> json) {
    final rawSecret = _optionalString(json, 'group');
    return PairAdmitMessage(
      publicKey: fromBase64Url(_string(json, 'key')),
      alias: _string(json, 'alias'),
      signature: fromBase64Url(_string(json, 'sig')),
      groupSecret: rawSecret == null ? null : fromBase64Url(rawSecret),
      members: _optionalFingerprints(json, 'members'),
    );
  }

  @override
  String toString() =>
      'PairAdmitMessage(${fingerprint.short()}, "$alias", '
      'group: ${groupSecret != null}, ${members.length} members)';
}

/// Confirms that a Pairing's short authentication string was accepted.
///
/// Sent once by each side, only after its user confirmed that the six digits
/// on the two screens match. Nothing is written to either profile until this
/// has been both sent and received, so a user who confirms on one Device and
/// then cancels on the other leaves no half-paired state behind.
///
/// It carries nothing, and does not need to: the record is sealed with keys
/// derived from the Pairing Secret, so receiving one proves the peer completed
/// the same handshake this Device did.
final class PairConfirmedMessage extends WireMessage {
  const PairConfirmedMessage();

  @override
  String get type => 'pairConfirmed';

  @override
  Map<String, Object?> toJson() => const {};

  static PairConfirmedMessage fromJson(Map<String, Object?> json) =>
      const PairConfirmedMessage();
}

/// Reports a protocol-level problem that has no more specific message.
final class ErrorMessage extends WireMessage {
  const ErrorMessage({required this.code, required this.message});

  /// A short machine-readable code, such as `unsupportedVersion`.
  final String code;

  /// A human-readable explanation, for logs rather than the UI.
  final String message;

  @override
  String get type => 'error';

  @override
  Map<String, Object?> toJson() => {'code': code, 'msg': message};

  static ErrorMessage fromJson(Map<String, Object?> json) =>
      ErrorMessage(code: _string(json, 'code'), message: _string(json, 'msg'));
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('"$key" must be a string, got ${value.runtimeType}');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException(
      '"$key" must be a string when present, got ${value.runtimeType}',
    );
  }
  return value;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('"$key" must be an int, got ${value.runtimeType}');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('"$key" must be a list, got ${value.runtimeType}');
  }
  return value;
}

Map<String, Object?> _asObject(Object? value, String where) {
  if (value is! Map) {
    throw FormatException('$where must be an object, got ${value.runtimeType}');
  }
  return value.cast<String, Object?>();
}

String _asString(Object? value, String where) {
  if (value is! String) {
    throw FormatException('$where must be a string, got ${value.runtimeType}');
  }
  return value;
}

Map<String, int> _optionalIntMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const {};
  final object = _asObject(value, key);
  return object.map((name, count) {
    if (count is! int) {
      throw FormatException('"$key.$name" must be an int');
    }
    return MapEntry(name, count);
  });
}

Map<String, String> _optionalStringMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const {};
  final object = _asObject(value, key);
  return object.map((name, digest) {
    if (digest is! String) {
      throw FormatException('"$key.$name" must be a string');
    }
    return MapEntry(name, digest);
  });
}

/// Decodes a list of Fingerprints, or an empty list when absent.
List<Fingerprint> _optionalFingerprints(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException(
      '"$key" must be a list when present, got ${value.runtimeType}',
    );
  }
  return [for (final entry in value) Fingerprint(_asString(entry, '$key[]'))];
}

DateTime _dateTime(Map<String, Object?> json, String key) {
  final raw = _string(json, key);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('"$key" is not an ISO-8601 timestamp: "$raw"');
  }
  return parsed;
}

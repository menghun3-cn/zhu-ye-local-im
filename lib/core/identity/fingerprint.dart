import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The stable identity of a [Device], used to tell peers apart and to
/// recognise one again after a restart.
///
/// A fingerprint is the SHA-256 of a Device's public key, rendered as 64
/// lowercase hex characters. Deriving it from the key rather than storing a
/// random id means a Device cannot claim a fingerprint it cannot prove, and
/// means the fingerprint is stable across reinstallations that preserve the
/// key.
final class Fingerprint implements Comparable<Fingerprint> {
  /// Wraps an already-computed [hex], which must be 64 lowercase hex chars.
  Fingerprint(String hex) : _hex = _validate(hex);

  /// Derives the fingerprint of a raw public key.
  factory Fingerprint.ofPublicKey(List<int> publicKeyBytes) {
    return Fingerprint(sha256.convert(publicKeyBytes).toString());
  }

  final String _hex;

  /// The fingerprint in lowercase hex.
  String get hex => _hex;

  /// The first [length] characters, for display where the whole value would
  /// not fit.
  String short([int length = 8]) =>
      _hex.substring(0, length.clamp(1, _hex.length));

  @override
  int compareTo(Fingerprint other) => _hex.compareTo(other._hex);

  @override
  bool operator ==(Object other) => other is Fingerprint && other._hex == _hex;

  @override
  int get hashCode => _hex.hashCode;

  @override
  String toString() => _hex;

  static String _validate(String hex) {
    if (hex.length != 64) {
      throw FormatException(
        'a fingerprint is 64 hex characters, got ${hex.length}',
      );
    }
    final normalised = hex.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalised)) {
      throw const FormatException('a fingerprint contains only 0-9 and a-f');
    }
    return normalised;
  }
}

/// Which side of a connection a Device is on.
///
/// The product is peer-to-peer, so this says nothing about trust or ownership;
/// it only decides which side runs the listening socket for a given Session.
enum LinkRole {
  /// The Device that opened the connection.
  initiator('initiator'),

  /// The Device that accepted the connection.
  responder('responder');

  const LinkRole(this.wireName);

  /// The value used on the wire.
  final String wireName;
}

/// Renders bytes as lowercase hex.
String toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

/// Parses lowercase or uppercase hex into bytes.
///
/// Throws [FormatException] on odd length or non-hex characters, so malformed
/// key material fails loudly at the boundary instead of producing a short key.
Uint8List fromHex(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('hex string has odd length ${hex.length}');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) {
      throw FormatException(
        'invalid hex at offset ${i * 2}: "${hex.substring(i * 2, i * 2 + 2)}"',
      );
    }
    out[i] = byte;
  }
  return out;
}

/// Base64 encoding without padding, which is safe in JSON and URLs.
String toBase64Url(List<int> bytes) => base64Url.encode(bytes);

/// Decodes [toBase64Url] output, throwing [FormatException] on bad input.
Uint8List fromBase64Url(String value) {
  try {
    return base64Url.decode(value);
  } on FormatException catch (error) {
    throw FormatException('invalid base64url value: ${error.message}');
  }
}

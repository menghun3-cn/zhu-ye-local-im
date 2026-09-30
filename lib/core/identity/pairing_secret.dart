import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../security/hkdf.dart';
import '../util/crockford_base32.dart';

/// The shared secret that makes a Pairing unguessable.
///
/// There are two ways to establish one, and they are deliberately different in
/// strength:
///
/// * [random] produces 256 bits of entropy. This is what a QR code carries,
///   because a QR code can transport arbitrary bytes.
/// * [fromCode] derives the secret from a short human-typed code. The code is
///   50 bits, so it is a fallback for when a camera is unavailable, not the
///   preferred path: an attacker who records a handshake can test code guesses
///   offline against the authentication tag. The short-authentication-string
///   step in the UI does not raise that ceiling — a peer that knows the code
///   derives the same digits — it is there so both users confirm, with the
///   peer's identity in front of them, that this is the exchange they meant.
final class PairingSecret {
  PairingSecret._(this._bytes, this.entropyBits);

  /// Wraps raw key material. Requires at least [minimumBytes].
  factory PairingSecret.fromBytes(List<int> bytes) {
    if (bytes.length < minimumBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'a pairing secret needs at least $minimumBytes bytes',
      );
    }
    return PairingSecret._(Uint8List.fromList(bytes), bytes.length * 8);
  }

  /// Generates a full-strength secret, for the QR path.
  factory PairingSecret.random({Random? random}) =>
      PairingSecret._(randomBytes(keyBytes, random: random), keyBytes * 8);

  /// Derives the secret both Devices compute when one shows a code and the
  /// other types it.
  ///
  /// Deterministic by construction: the same code always yields the same
  /// secret, on any Device.
  factory PairingSecret.fromCode(String code) {
    final normalised = normaliseCode(code);
    if (normalised.length != codeSymbols) {
      throw FormatException(
        'a pairing code is $codeSymbols symbols, got ${normalised.length}',
      );
    }
    // Validates the alphabet, and throws on a symbol no code could contain.
    CrockfordBase32.decode(normalised);
    return PairingSecret._(
      HkdfSha256.deriveKey(
        ikm: utf8.encode(normalised),
        salt: utf8.encode('local-transfer pairing v1'),
        info: utf8.encode('pairing secret'),
        length: keyBytes,
      ),
      // The derived key is 256 bits, but its strength is capped by the code
      // that produced it. Reporting the source's entropy rather than the
      // derived length is what keeps the UI honest about this path.
      codeSymbols * 5,
    );
  }

  /// The secret the no-typing Pairing path runs on.
  ///
  /// There is nothing user-chosen to derive here: both Devices run the
  /// handshake over the same well-known constant, and what makes the Pairing
  /// safe is everything layered on top — the handshake authenticates the two
  /// sides to each other, and the six digits the users compare are what rules
  /// out a third Device standing in the middle. That is a weaker guarantee
  /// than a typed code gives — any Device on the link can *start* an open
  /// Pairing — which is exactly why admission stays a human decision on both
  /// screens.
  ///
  /// What this constant deliberately does *not* produce is the group secret a
  /// fresh Pairing agrees on: the receiving Device mints a fresh one and
  /// hands it over inside the sealed link, so two unrelated Pairings never
  /// share key material. This constant protects the handshake alone.
  factory PairingSecret.openPairing() => _openPairing ??= PairingSecret._(
    HkdfSha256.deriveKey(
      ikm: utf8.encode('local-transfer open pairing'),
      salt: utf8.encode('local-transfer pairing v1'),
      info: utf8.encode('open pairing secret'),
      length: keyBytes,
    ),
    // Public by construction: the honest entropy figure for a constant.
    0,
  );

  static PairingSecret? _openPairing;

  /// Decodes a secret carried by a QR code or another byte channel.
  factory PairingSecret.fromTransportString(String value) {
    final decoded = base64Url.decode(value);
    return PairingSecret.fromBytes(decoded);
  }

  /// The number of symbols in a typed pairing code: 50 bits.
  static const int codeSymbols = 10;

  /// The size of a full-strength secret in bytes.
  static const int keyBytes = 32;

  /// The smallest secret this type will hold.
  static const int minimumBytes = 16;

  final Uint8List _bytes;

  /// The raw key material, for key derivation.
  List<int> get bytes => Uint8List.fromList(_bytes);

  /// How much entropy this secret is expected to hold, for display.
  ///
  /// For the typed-code path this is the code's 50 bits, not the 256 bits the
  /// derived key happens to be long.
  final int entropyBits;

  /// Renders the secret for a QR code or any channel that carries bytes.
  String toTransportString() => base64Url.encode(_bytes);

  /// True when [other] holds the same secret, compared in constant time.
  bool matches(PairingSecret other) => constantTimeEquals(_bytes, other._bytes);

  /// Produces a fresh code for the typed-pairing flow.
  ///
  /// The other Device must call [PairingSecret.fromCode] with the same code;
  /// the displaying Device does not need to keep the code, only to know that
  /// its peer derived a secret from it.
  static String generateCode({Random? random}) {
    final source = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < codeSymbols; i++) {
      buffer.write(CrockfordBase32.alphabet[source.nextInt(32)]);
    }
    return buffer.toString();
  }

  /// Never reveals the secret; safe to put in a log line.
  @override
  String toString() => 'PairingSecret(${_bytes.length} bytes, redacted)';
}

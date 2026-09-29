import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// HKDF-SHA256 as specified by RFC 5869.
///
/// Implemented here rather than taken from a dependency so that the exact
/// derivation the protocol depends on is pinned by this repository's own tests
/// against the RFC's published vectors. Key derivation is the one place where
/// a silent change would not fail loudly — it would simply produce keys the
/// other side cannot match — so it is worth owning outright.
class HkdfSha256 {
  const HkdfSha256._();

  /// The maximum output length this implementation will produce, in bytes.
  ///
  /// RFC 5869 caps HKDF-Expand at 255 * HashLen; the cap is enforced so a bad
  /// caller cannot ask for an unbounded buffer.
  static const int maxOutputLength = 255 * 32;

  /// RFC 5869 §2.2: `HKDF-Extract(salt, IKM) -> PRK`.
  ///
  /// An empty [salt] is treated as HashLen zero bytes, which is what the RFC
  /// specifies and what HMAC already does for an empty key.
  static Uint8List extract({required List<int> salt, required List<int> ikm}) {
    return Uint8List.fromList(
      Hmac(sha256, Uint8List.fromList(salt)).convert(ikm).bytes,
    );
  }

  /// RFC 5869 §2.3: `HKDF-Expand(PRK, info, L) -> OKM`.
  static Uint8List expand({
    required List<int> prk,
    required List<int> info,
    required int length,
  }) {
    if (length < 0) {
      throw RangeError.value(length, 'length', 'must not be negative');
    }
    if (length > maxOutputLength) {
      throw RangeError.value(
        length,
        'length',
        'HKDF-SHA256 expands to at most $maxOutputLength bytes',
      );
    }
    final hmac = Hmac(sha256, Uint8List.fromList(prk));
    final out = Uint8List(length);
    var produced = 0;
    var counter = 1;
    var previous = const <int>[];
    while (produced < length) {
      if (counter > 255) {
        throw StateError('HKDF-Expand exhausted its counter');
      }
      final input = Uint8List(previous.length + info.length + 1)
        ..setRange(0, previous.length, previous)
        ..setRange(previous.length, previous.length + info.length, info)
        ..[previous.length + info.length] = counter;
      previous = hmac.convert(input).bytes;
      final take = min(previous.length, length - produced);
      out.setRange(produced, produced + take, previous);
      produced += take;
      counter++;
    }
    return out;
  }

  /// `extract` then `expand`, the way the protocol uses it.
  static Uint8List deriveKey({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    return expand(
      prk: extract(salt: salt, ikm: ikm),
      info: info,
      length: length,
    );
  }
}

/// Fills a new buffer of [length] bytes from [random].
Uint8List randomBytes(int length, {Random? random}) {
  final source = random ?? Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = source.nextInt(256);
  }
  return out;
}

/// Compares two byte sequences without leaking where they first differ.
///
/// Used for secrets such as pairing tokens and short authentication strings,
/// where an early-exit comparison would let an attacker recover the value one
/// byte at a time.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A SHA-256 fed as bytes go past and asked for its value once, at the end.
///
/// Both ends of a Transfer hash bytes they are already streaming rather than
/// reading them again afterwards: a receiver must hash what it wrote, and a
/// sender must hash an item once to put a digest in its Offer. A running hash
/// avoids a second pass over bytes that may be gigabytes, which is the
/// difference between verifying a large file and reading it twice.
final class RunningDigest {
  RunningDigest() {
    _input = sha256.startChunkedConversion(_collector);
  }

  final _DigestCollector _collector = _DigestCollector();
  late final ByteConversionSink _input;
  String? _value;

  /// Adds [bytes] to the hash.
  ///
  /// Throws [StateError] once [finish] has been called, because a digest that
  /// keeps absorbing bytes after being read is a digest of nothing in
  /// particular.
  void add(List<int> bytes) {
    if (_value != null) {
      throw StateError('bytes cannot be added after the digest is taken');
    }
    _input.add(bytes);
  }

  /// Finalises the hash and returns it as 64 lowercase hex characters.
  ///
  /// May be called more than once; only the first call finalises.
  String finish() {
    final already = _value;
    if (already != null) return already;
    _input.close();
    final digest = _collector.value;
    if (digest == null) {
      throw StateError('the hash produced no digest');
    }
    return _value = digest.toString();
  }
}

/// Receives the one [Digest] a chunked hash conversion emits at the end.
final class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

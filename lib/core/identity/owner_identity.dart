import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'fingerprint.dart';

/// The Owner's key pair, held by exactly one Device and never transmitted.
///
/// Everything else a Device claims about itself — the descriptor it
/// announces, the [Fingerprint] in it — is chosen by whoever runs the Device.
/// The key pair is the one part that cannot be chosen after the fact: the
/// Fingerprint is derived from the public half, so a Device that proves it
/// holds the private half proves it is the Device a peer met before, no
/// matter what alias it now displays.
///
/// The key is Ed25519. It is used for signing challenges, not for key
/// agreement — session keys come from the ephemeral X25519 exchange in
/// [SecureLink] and are mixed with the Pairing Secret there — so compromising
/// this key reveals nothing about past or future session traffic. What it
/// protects is *identity continuity*: which Device is which.
///
/// The private half lives in the Device's profile store on local disk and
/// nowhere else. It is not in any backup the user did not choose to make, it
/// is not on the wire, and it is not derivable from anything a peer sees.
final class OwnerIdentity {
  OwnerIdentity._(this._keyPair, this._fingerprint);

  static final Ed25519 _algorithm = Ed25519();

  /// The exact number of bytes in a stored seed.
  static const int seedBytes = 32;

  final SimpleKeyPair _keyPair;
  final Fingerprint _fingerprint;

  /// Generates a fresh identity.
  static Future<OwnerIdentity> generate() async {
    final keyPair = await _algorithm.newKeyPair();
    return _wrap(keyPair);
  }

  /// Restores the identity a seed was saved for.
  ///
  /// The same seed always reproduces the same key pair and therefore the same
  /// Fingerprint — that determinism is what makes a Device recognisable
  /// across restarts.
  ///
  /// Throws [ArgumentError] when [seed] is not exactly [seedBytes] long, so a
  /// truncated store cannot silently mint a different Device.
  static Future<OwnerIdentity> fromSeed(List<int> seed) async {
    if (seed.length != seedBytes) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'an Owner seed is exactly $seedBytes bytes',
      );
    }
    return _wrap(await _algorithm.newKeyPairFromSeed(seed));
  }

  static Future<OwnerIdentity> _wrap(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return OwnerIdentity._(keyPair, Fingerprint.ofPublicKey(publicKey.bytes));
  }

  /// The Device's stable identity.
  Fingerprint get fingerprint => _fingerprint;

  /// The public half, raw bytes.
  Future<Uint8List> publicKey() async =>
      Uint8List.fromList((await _keyPair.extractPublicKey()).bytes);

  /// Signs [message] with the private half.
  Future<Uint8List> sign(List<int> message) async {
    final signature = await _algorithm.sign(message, keyPair: _keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Checks [signature] against [publicKey] and [message].
  ///
  /// Static rather than an instance method: verifying is what a *peer* does
  /// with a claimed identity, and the verifier never holds the private half.
  static Future<bool> verify(
    List<int> publicKey,
    List<int> message,
    List<int> signature,
  ) async {
    try {
      return await _algorithm.verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on ArgumentError {
      // Malformed key or signature material is a failed verification, not a
      // crash: a hostile peer supplies both.
      return false;
    } on StateError {
      // A signature of the wrong length is rejected by the algorithm as a
      // bad state rather than a bad argument; either way it is not valid.
      return false;
    }
  }

  /// The seed that reproduces this key pair, for the profile store.
  ///
  /// The seed *is* the private key in usable form. Callers persist it only
  /// where the private half is allowed to live: this Device's local disk.
  ///
  /// The first [seedBytes] bytes are taken deliberately: an Ed25519 private
  /// key is stored as either the 32-byte seed or the seed followed by the
  /// public half, and the seed is the leading half in both layouts.
  Future<Uint8List> exportSeed() async {
    final bytes = await _keyPair.extractPrivateKeyBytes();
    return Uint8List.fromList(bytes.sublist(0, seedBytes));
  }

  /// Names no key material: the seed must not leak into a log line.
  @override
  String toString() => 'OwnerIdentity(${_fingerprint.short()})';
}

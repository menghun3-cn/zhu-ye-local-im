import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

/// Seals the secrets `providers.json` carries — today that is each provider's
/// API key — so the file on disk is not a plaintext list of credentials.
///
/// AES-256-GCM with a random key generated once per install and kept in a
/// sibling file. This is obfuscation-grade protection, not a vault: the key
/// sits next to the ciphertext on the same disk, which stops casual readers
/// (backups, sync folders, shoulder-surfing at the file) but not malware
/// running as the user. OS keystores — Windows DPAPI, Android Keystore — are
/// the real answer and are recorded as future work in the design note.
///
/// The sealed form is `v1:<base64(nonce ‖ ciphertext ‖ tag)>`. A value
/// without the prefix is read as plaintext and sealed on the next save, so
/// files written before encryption existed migrate themselves.
final class SecretBox {
  final crypto.SecretKey _key;

  static const _prefix = 'v1:';
  static const _nonceLength = 12;
  static const _keyLength = 32;

  /// Opens (or creates) the key file at [keyFilePath] and returns a box.
  ///
  /// The file holds the raw 32-byte key. A file of the wrong length is
  /// treated as damaged and replaced — a wrong-length key could never have
  /// sealed anything this box wrote, so nothing is lost by rotating it.
  static Future<SecretBox> open(String keyFilePath) async {
    final file = File(keyFilePath);
    List<int> keyBytes;
    if (await file.exists()) {
      keyBytes = await file.readAsBytes();
      if (keyBytes.length != _keyLength) {
        keyBytes = _generateKey();
        await _writeKey(file, keyBytes);
      }
    } else {
      keyBytes = _generateKey();
      await file.parent.create(recursive: true);
      await _writeKey(file, keyBytes);
    }
    return SecretBox.withKey(keyBytes);
  }

  /// A box over caller-supplied key bytes — for tests.
  SecretBox.withKey(List<int> keyBytes)
    : _key = crypto.SecretKey(Uint8List.fromList(keyBytes));

  static List<int> _generateKey() {
    final random = Random.secure();
    return List<int>.generate(_keyLength, (_) => random.nextInt(256));
  }

  static Future<void> _writeKey(File file, List<int> bytes) =>
      file.writeAsBytes(bytes, flush: true);

  /// Whether [stored] is in sealed form.
  static bool isSealed(String stored) => stored.startsWith(_prefix);

  /// Encrypts [plaintext] into the stored form.
  Future<String> seal(String plaintext) async {
    final aes = crypto.AesGcm.with256bits();
    final nonce = List<int>.generate(
      _nonceLength,
      (_) => Random.secure().nextInt(256),
    );
    final box = await aes.encrypt(
      utf8.encode(plaintext),
      secretKey: _key,
      nonce: nonce,
    );
    final packed = <int>[...nonce, ...box.cipherText, ...box.mac.bytes];
    return '$_prefix${base64Encode(packed)}';
  }

  /// Decrypts [stored]; plaintext values pass through untouched so a config
  /// written before sealing existed still reads.
  Future<String> unseal(String stored) async {
    if (!isSealed(stored)) return stored;
    final packed = base64Decode(stored.substring(_prefix.length));
    if (packed.length <= _nonceLength + 16) {
      throw const FormatException('sealed secret is too short');
    }
    final nonce = packed.sublist(0, _nonceLength);
    final tag = packed.sublist(packed.length - 16);
    final cipherText = packed.sublist(_nonceLength, packed.length - 16);
    final aes = crypto.AesGcm.with256bits();
    final clear = await aes.decrypt(
      crypto.SecretBox(cipherText, nonce: nonce, mac: crypto.Mac(tag)),
      secretKey: _key,
    );
    return utf8.decode(clear);
  }
}

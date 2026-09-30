import 'dart:convert';
import 'dart:io';

import '../clipboard/clipboard_capability.dart';
import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';
import '../identity/owner_identity.dart';
import 'device_profile.dart';

/// Raised when a persisted profile cannot be decoded.
///
/// The original file has been moved aside by the time this is thrown, so the
/// caller can offer the user a fresh start without losing the damaged data.
final class ProfileCorruptedException implements Exception {
  const ProfileCorruptedException(this.path, this.cause, this.backupPath);

  /// Where the profile was expected.
  final String path;

  /// What was wrong with it.
  final Object cause;

  /// Where the damaged file was moved, for the user to inspect or delete.
  final String backupPath;

  @override
  String toString() =>
      'ProfileCorruptedException: $path is unreadable ($cause); '
      'moved to $backupPath';
}

/// The [OwnerIdentity] and [DeviceProfile] of this Device, as one unit.
///
/// They travel together because they are persisted together and loaded
/// together: a profile without its identity cannot prove anything, and an
/// identity without a profile has no alias to announce.
final class LocalProfile {
  const LocalProfile({required this.identity, required this.profile});

  /// The Owner's key pair.
  final OwnerIdentity identity;

  /// The Device's self-knowledge and peer history.
  final DeviceProfile profile;
}

/// Where a [LocalProfile] lives.
///
/// The store moves JSON maps and knows nothing about their meaning; the
/// encoding rules live with [loadLocalProfile] and [saveLocalProfile], so a
/// change to the persisted shape cannot be made in one place and forgotten
/// in the other.
abstract interface class ProfileStore {
  /// The stored profile, or null when nothing has been saved yet.
  Future<Map<String, Object?>?> load();

  /// Replaces the stored profile.
  Future<void> save(Map<String, Object?> json);
}

/// A [ProfileStore] held in memory, for tests and for a Device that runs
/// without disk persistence.
final class MemoryProfileStore implements ProfileStore {
  Map<String, Object?>? _json;

  @override
  Future<Map<String, Object?>?> load() async => _json == null
      ? null
      : jsonDecode(jsonEncode(_json)) as Map<String, Object?>;

  @override
  Future<void> save(Map<String, Object?> incoming) async {
    // Round-trip through JSON so the caller's map cannot be mutated after the
    // fact into something the store no longer holds.
    _json = jsonDecode(jsonEncode(incoming)) as Map<String, Object?>;
  }
}

/// A [ProfileStore] backed by one JSON file on this Device's disk.
///
/// Writes are atomic-ish: the new content lands in a sibling temp file first
/// and only then replaces the profile. A crash mid-write therefore leaves the
/// previous profile intact rather than a truncated half-profile — the failure
/// that would otherwise strand a Device without its identity on restart.
final class FileProfileStore implements ProfileStore {
  /// A store over [path], created on first save.
  FileProfileStore(this.path);

  /// Where the profile lives.
  final String path;

  /// The temp file written before each replace.
  String get _tempPath => '$path.tmp';

  /// Where a damaged profile is moved instead of being deleted.
  String get _corruptPath => '$path.corrupt';

  @override
  Future<Map<String, Object?>?> load() async {
    final file = File(path);
    if (!await file.exists()) return null;
    String text;
    try {
      text = await file.readAsString();
    } on FileSystemException catch (error) {
      throw ProfileCorruptedException(path, error, _corruptPath);
    }
    Map<String, Object?> decoded;
    try {
      final value = jsonDecode(text);
      if (value is! Map<String, Object?>) {
        throw const FormatException('a profile is a JSON object');
      }
      decoded = value;
    } on FormatException catch (error) {
      // A profile that cannot be decoded must not be overwritten in place:
      // it is the only copy of this Device's identity. Moving it aside keeps
      // the user's options open — restore it, inspect it, or start over.
      await _moveAside(file);
      throw ProfileCorruptedException(path, error, _corruptPath);
    }
    return decoded;
  }

  @override
  Future<void> save(Map<String, Object?> json) async {
    final temp = File(_tempPath);
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    final target = File(path);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(path);
  }

  Future<void> _moveAside(File file) async {
    final backup = File(_corruptPath);
    if (await backup.exists()) {
      await backup.delete();
    }
    await file.rename(_corruptPath);
  }
}

/// Loads the [LocalProfile] a store holds, or generates one when none does.
///
/// First launch on a Device lands here: a fresh identity is minted, its seed
/// is immediately persisted, and the fingerprint the Device will carry for
/// the rest of its life is derived before anything announces it.
///
/// [platform] and [alias] describe the Device the caller is running on; they
/// are parameters rather than detected here because the platform is an app
/// layer's fact, and this file stays Flutter-free and shell-free.
Future<LocalProfile> loadOrGenerateLocalProfile(
  ProfileStore store, {
  required DevicePlatform platform,
  String? alias,
}) async {
  final stored = await loadLocalProfile(store);
  if (stored != null) return stored;
  final identity = await OwnerIdentity.generate();
  final profile = DeviceProfile(
    self: identity.fingerprint,
    alias: alias ?? DeviceDescriptor.fallbackAlias,
    platform: platform,
  );
  final local = LocalProfile(identity: identity, profile: profile);
  await saveLocalProfile(local, store);
  return local;
}

/// Decodes a [LocalProfile] from a store, or returns null when empty.
///
/// Throws [ProfileCorruptedException] when the store is unreadable, and
/// [FormatException] when it decodes but does not validate: a profile whose
/// [DeviceProfile.self] disagrees with the [OwnerIdentity]'s fingerprint is
/// not a Device, it is a contradiction, and the store must not paper over it.
Future<LocalProfile?> loadLocalProfile(ProfileStore store) async {
  final json = await store.load();
  if (json == null) return null;
  final OwnerIdentity identity;
  try {
    identity = await OwnerIdentity.fromSeed(_seedOf(json));
  } on ArgumentError catch (error) {
    throw ProfileCorruptedException('store', error, 'store');
  }
  final profile = DeviceProfile.fromJson(_profileOf(json));
  if (identity.fingerprint != profile.self) {
    throw FormatException(
      'profile self ${profile.self.short()} does not match '
      'identity ${identity.fingerprint.short()}',
    );
  }
  return LocalProfile(identity: identity, profile: profile);
}

/// Persists [local] — identity seed included — through [store].
///
/// The seed is the private half of the Owner key pair. It is stored because a
/// Device that forgot it after every restart would be a new Device every
/// time, which defeats the identity the key pair exists to provide. It stays
/// inside the store it was loaded from; nothing sends it over the wire.
Future<void> saveLocalProfile(LocalProfile local, ProfileStore store) async {
  await store.save({
    'version': 1,
    'identity': {
      'kind': 'ed25519-seed',
      'seed': toBase64Url(await local.identity.exportSeed()),
    },
    'profile': local.profile.toJson(),
  });
}

List<int> _seedOf(Map<String, Object?> json) {
  final identity = json['identity'];
  if (identity is! Map) {
    throw const FormatException('"identity" must be an object');
  }
  final kind = identity['kind'];
  if (kind != 'ed25519-seed') {
    throw FormatException('unsupported identity kind "$kind"');
  }
  final seed = identity['seed'];
  if (seed is! String) {
    throw const FormatException('"identity.seed" must be a string');
  }
  return fromBase64Url(seed);
}

Map<String, Object?> _profileOf(Map<String, Object?> json) {
  final profile = json['profile'];
  if (profile is! Map) {
    throw const FormatException('"profile" must be an object');
  }
  return profile.cast<String, Object?>();
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
///
/// Secrets live here rather than on [DeviceProfile]: a profile is state a UI
/// renders and a test builds by hand, and cryptographic material has no place
/// in either.
final class LocalProfile {
  const LocalProfile({
    required this.identity,
    required this.profile,
    this.groupSecret,
  });

  /// The Owner's key pair.
  final OwnerIdentity identity;

  /// The Device's self-knowledge and peer history.
  final DeviceProfile profile;

  /// The secret every Session inside this Device's Owner Group is
  /// authenticated with, or null when this Device belongs to no group yet.
  ///
  /// One secret per group rather than one per peer: a Session's responder has
  /// to authenticate before it knows who is dialling, so a per-peer secret
  /// could not be selected. Two Devices pairing for the first time derive the
  /// same value from the Pairing code; anything joining an existing group is
  /// handed this one, sealed by the Pairing session.
  final Uint8List? groupSecret;

  /// A copy with [profile] or [groupSecret] replaced.
  LocalProfile copyWith({DeviceProfile? profile, Uint8List? groupSecret}) =>
      LocalProfile(
        identity: identity,
        profile: profile ?? this.profile,
        groupSecret: groupSecret ?? this.groupSecret,
      );

  /// Whether this Device has been paired with anybody.
  bool get hasGroupSecret => groupSecret != null;

  @override
  String toString() =>
      'LocalProfile(${profile.self.short()}, "$profile.alias", '
      'group: ${profile.group.length}, secret: $hasGroupSecret)';
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

  /// The save in flight, or null once the last one has finished.
  ///
  /// Chained rather than left to overlap, for the same reason the message
  /// store chains its saves: every one writes the same temp file and renames
  /// it over the target, and two running at once race on that file — the
  /// rename that lands while the other save still holds it open is refused
  /// with `ERROR_SHARING_VIOLATION`, "another program is using this file"
  /// said about this program's own earlier save. The profile is rewritten
  /// rarely, but rarely is not never: a rename, a pairing and a settings
  /// change can each ask for one.
  Future<void>? _inFlight;

  @override
  Future<void> save(Map<String, Object?> json) {
    final previous = _inFlight;
    final started = previous == null
        ? _write(json)
        : previous.then((_) => _write(json));
    // Held as a future that cannot fail: one rejected save must not turn every
    // later one into the same failure without trying.
    final settled = started.then((_) {}, onError: (Object _) {});
    _inFlight = settled;
    settled.whenComplete(() {
      // Cleared only when the newest save is the one that just finished, so
      // the chain does not grow for the life of the process.
      if (identical(_inFlight, settled)) _inFlight = null;
    });
    return started;
  }

  /// The write itself, with no other save running beside it.
  Future<void> _write(Map<String, Object?> json) async {
    final temp = File(_tempPath);
    // `profile_location.dart` decides where a profile goes and says outright
    // that the store is what makes that place exist. On a first launch it
    // does not yet: `%APPDATA%/LocalTransfer` has never been created, and
    // neither has the directory a chosen incoming folder names. Without this
    // the very first save — the one that mints the Device's identity — is the
    // one that fails, and it fails before any window is drawn.
    await temp.parent.create(recursive: true);
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
  if (stored != null) {
    final hostname = alias == null
        ? DeviceDescriptor.fallbackAlias
        : DeviceDescriptor.sanitiseAlias(alias);
    // An identity minted before host names were read still carries the
    // placeholder. Migrate only that placeholder: a name the user typed is a
    // decision, and a later operating-system rename must not overwrite it.
    if (stored.profile.alias == DeviceDescriptor.fallbackAlias &&
        hostname != DeviceDescriptor.fallbackAlias) {
      stored.profile.alias = hostname;
      await saveLocalProfile(stored, store);
    }
    return stored;
  }
  final identity = await OwnerIdentity.generate();
  final chosenAlias = alias == null
      ? null
      : DeviceDescriptor.sanitiseAlias(alias);
  final profile = DeviceProfile(
    self: identity.fingerprint,
    alias: chosenAlias == DeviceDescriptor.fallbackAlias
        ? DeviceDescriptor.fallbackAlias
        : chosenAlias ?? DeviceDescriptor.fallbackAlias,
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
  return LocalProfile(
    identity: identity,
    profile: profile,
    groupSecret: _groupSecretOf(json),
  );
}

/// Persists [local] — identity seed and group secret included — through
/// [store].
///
/// The seed is the private half of the Owner key pair, and the group secret is
/// what authenticates every Session inside the Owner Group. Both are stored
/// because a Device that forgot either would have to be re-paired after every
/// restart. Both stay inside the store they were loaded from; nothing sends
/// them anywhere except a Pairing session, sealed by the handshake.
Future<void> saveLocalProfile(LocalProfile local, ProfileStore store) async {
  await store.save({
    'version': 1,
    'identity': {
      'kind': 'ed25519-seed',
      'seed': toBase64Url(await local.identity.exportSeed()),
    },
    'session': {
      if (local.groupSecret != null)
        'groupSecret': toBase64Url(local.groupSecret!),
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

Uint8List? _groupSecretOf(Map<String, Object?> json) {
  final session = json['session'];
  if (session == null) return null;
  if (session is! Map) {
    throw const FormatException('"session" must be an object when present');
  }
  final secret = session['groupSecret'];
  if (secret == null) return null;
  if (secret is! String) {
    throw const FormatException('"session.groupSecret" must be a string');
  }
  return fromBase64Url(secret);
}

Map<String, Object?> _profileOf(Map<String, Object?> json) {
  final profile = json['profile'];
  if (profile is! Map) {
    throw const FormatException('"profile" must be an object');
  }
  return profile.cast<String, Object?>();
}

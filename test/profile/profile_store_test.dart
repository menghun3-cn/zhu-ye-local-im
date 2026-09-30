import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:local_transfer/core/clipboard/clipboard_capability.dart';
import 'package:local_transfer/core/identity/fingerprint.dart';
import 'package:local_transfer/core/identity/owner_identity.dart';
import 'package:local_transfer/core/profile/device_profile.dart';
import 'package:local_transfer/core/profile/profile_store.dart';

Future<LocalProfile> _fresh() async {
  final identity = await OwnerIdentity.generate();
  return LocalProfile(
    identity: identity,
    profile: DeviceProfile(
      self: identity.fingerprint,
      alias: 'Desk',
      platform: DevicePlatform.windows,
    ),
  );
}

void main() {
  group('MemoryProfileStore', () {
    test('an empty store loads as null', () async {
      final store = MemoryProfileStore();
      expect(await store.load(), isNull);
    });

    test('a saved profile loads back as an equal JSON object', () async {
      final store = MemoryProfileStore();
      await store.save({
        'a': 1,
        'b': [true, 'x'],
      });
      expect(await store.load(), {
        'a': 1,
        'b': [true, 'x'],
      });
    });

    test('a caller mutating what it saved cannot corrupt the store', () async {
      final store = MemoryProfileStore();
      final json = <String, Object?>{'a': 1};
      await store.save(json);
      json['a'] = 999;
      expect((await store.load())!['a'], 1);
    });
  });

  group('FileProfileStore', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('profile-store-test');
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('a missing file loads as null', () async {
      final store = FileProfileStore(
        '${sandbox.path}${Platform.pathSeparator}profile.json',
      );
      expect(await store.load(), isNull);
    });

    test('a saved profile loads back unchanged', () async {
      final store = FileProfileStore(
        '${sandbox.path}${Platform.pathSeparator}profile.json',
      );
      await store.save({
        'profile': {'alias': 'Desk'},
      });
      expect(await store.load(), {
        'profile': {'alias': 'Desk'},
      });
    });

    test('saving over an existing profile replaces it wholesale', () async {
      final store = FileProfileStore(
        '${sandbox.path}${Platform.pathSeparator}profile.json',
      );
      await store.save({'v': 1});
      await store.save({'v': 2});
      expect((await store.load())!['v'], 2);
    });

    test('saving leaves no temp file behind', () async {
      final store = FileProfileStore(
        '${sandbox.path}${Platform.pathSeparator}profile.json',
      );
      await store.save({'v': 1});
      expect(
        await File('${store.path}.tmp').exists(),
        isFalse,
        reason: 'a leftover temp file means a rename failed silently',
      );
    });

    test(
      'a corrupt file is moved aside, not destroyed, and reported',
      () async {
        final path = '${sandbox.path}${Platform.pathSeparator}profile.json';
        await File(path).writeAsString('{ not json');
        final store = FileProfileStore(path);

        ProfileCorruptedException? raised;
        try {
          await store.load();
        } on ProfileCorruptedException catch (error) {
          raised = error;
        }

        expect(raised, isNotNull);
        expect(
          await File(raised!.backupPath).exists(),
          isTrue,
          reason: 'the damaged file is the only copy of an identity',
        );
        expect(await File(path).exists(), isFalse);
        // And the store recovers: the next load is a clean slate.
        expect(await store.load(), isNull);
      },
    );

    test('a first save makes the directory it writes into', () async {
      // `profile_location.dart` decides where a profile goes and says out
      // loud that the store is what makes that place exist. On a first
      // launch it is not there yet: neither `%APPDATA%/LocalTransfer` on
      // Windows nor Android's `.../incoming` is created by anybody else. A
      // store that cannot make its own directory cannot mint a first
      // identity, so this is the difference between an app that starts and
      // one that throws before its window is drawn.
      final nested = FileProfileStore(
        '${sandbox.path}${Platform.pathSeparator}LocalTransfer'
        '${Platform.pathSeparator}profile.json',
      );
      await nested.save({'v': 1});
      expect(await nested.load(), {'v': 1});
    });

    test('a first save creates every missing level, not just one', () async {
      final nested = FileProfileStore(
        '${sandbox.path}${Platform.pathSeparator}a'
        '${Platform.pathSeparator}b${Platform.pathSeparator}profile.json',
      );
      await nested.save({'v': 1});
      expect(await nested.load(), {'v': 1});
    });

    test('a JSON array where an object belongs is corruption too', () async {
      final path = '${sandbox.path}${Platform.pathSeparator}profile.json';
      await File(path).writeAsString('[1, 2, 3]');
      final store = FileProfileStore(path);
      expect(store.load, throwsA(isA<ProfileCorruptedException>()));
    });
  });

  group('LocalProfile persistence', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('profile-persist-test');
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    FileProfileStore storeIn(Directory dir) =>
        FileProfileStore('${dir.path}${Platform.pathSeparator}profile.json');

    test('save then load reproduces the same identity and profile', () async {
      final store = storeIn(sandbox);
      final local = await _fresh();
      await saveLocalProfile(local, store);
      final restored = await loadLocalProfile(store);
      expect(restored, isNotNull);
      expect(restored!.identity.fingerprint, local.identity.fingerprint);
      expect(restored.profile.self, local.profile.self);
      expect(restored.profile.alias, local.profile.alias);
      expect(restored.profile.platform, local.profile.platform);
      // The restored identity actually works: it can sign and its signature
      // verifies against its own public key.
      final signature = await restored.identity.sign('ping'.codeUnits);
      expect(
        await OwnerIdentity.verify(
          await restored.identity.publicKey(),
          'ping'.codeUnits,
          signature,
        ),
        isTrue,
      );
    });

    test('an empty store means first launch', () async {
      expect(await loadLocalProfile(storeIn(sandbox)), isNull);
    });

    test(
      'a profile whose self disagrees with its identity is rejected',
      () async {
        final store = storeIn(sandbox);
        final local = await _fresh();
        // Forge a profile that claims a different self than the key proves.
        final forged = json.decode(
          json.encode(local.profile.toJson()),
        ) as Map<String, Object?>;
        forged['self'] = 'f' * 64;
        await store.save({
          'version': 1,
          'identity': {
            'kind': 'ed25519-seed',
            'seed': toBase64Url(await local.identity.exportSeed()),
          },
          'profile': forged,
        });
        expect(loadLocalProfile(store), throwsFormatException);
      },
    );

    test('an unknown identity kind is rejected, not ignored', () async {
      final store = storeIn(sandbox);
      await store.save({
        'version': 1,
        'identity': {
          'kind': 'rsa-2048',
          'seed': toBase64Url(List.filled(32, 1)),
        },
        'profile': {'self': '0' * 64, 'alias': 'x', 'platform': 'windows'},
      });
      expect(loadLocalProfile(store), throwsFormatException);
    });

    test(
      'loadOrGenerate mints and persists on first call, restores on second',
      () async {
        final store = storeIn(sandbox);
        final first = await loadOrGenerateLocalProfile(
          store,
          platform: DevicePlatform.windows,
          alias: 'Desk',
        );
        expect(first.profile.alias, 'Desk');
        final second = await loadOrGenerateLocalProfile(
          store,
          platform: DevicePlatform.windows,
          alias: 'Ignored on restore',
        );
        expect(second.identity.fingerprint, first.identity.fingerprint);
        // The persisted alias wins on restore — the parameter only names a
        // brand-new Device.
        expect(second.profile.alias, 'Desk');
      },
    );
  });
}

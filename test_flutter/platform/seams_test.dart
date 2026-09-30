import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/seams.dart';

/// What `openPlatformSeams` decides, on a machine that is neither Android nor
/// in charge of the real `%APPDATA%`.
///
/// This is the other half of the Android story that `test/platform/` cannot
/// reach. Those tests read the Kotlin file and check the channel names agree;
/// these run the Dart side of that channel, with a stand-in for the Kotlin
/// handler, and check that what comes back is turned into the right store and
/// the right paths. Between them, Android's file story is pinned without an
/// emulator, an SDK, or a device.
///
/// The in-memory beacon is what makes this runnable at all: `openPlatformSeams`
/// otherwise binds the well-known discovery port, which one process per host
/// may hold, and a test that needs that port is a test that fails when the app
/// happens to be open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The answer `MainActivity.kt` gives: this app's private files directory.
  const androidFilesDir = '/data/user/0/cn.hnasct.local_transfer/files';

  /// A Windows environment, with the separators the host really uses.
  const windowsEnvironment = {
    'APPDATA': r'C:\Users\owner\AppData\Roaming',
    'LOCALAPPDATA': r'C:\Users\owner\AppData\Local',
    'USERPROFILE': r'C:\Users\owner',
  };

  late MemoryBeaconHub hub;

  /// Every method the Dart side asked the paths channel for.
  ///
  /// A list rather than a count, because "was it asked at all" and "was it
  /// asked the right thing" are different questions and both matter.
  late List<String> asked;

  setUp(() {
    hub = MemoryBeaconHub();
    asked = [];
  });

  tearDown(() async => hub.a.close());

  /// The channel as `MainActivity.kt` implements it: one method, one string,
  /// and `notImplemented` for anything else.
  void registerPathsChannel({String? answer, Object? failure}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(defaultPathsChannel.name), (
          call,
        ) async {
          asked.add(call.method);
          if (failure != null) throw failure;
          if (call.method != appDataDirectoryMethod) return null;
          return answer;
        });
  }

  /// The channel as a platform without it behaves: no handler registered, so
  /// the call throws [MissingPluginException].
  void registerNoPathsChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(defaultPathsChannel.name),
          null,
        );
  }

  Future<PlatformSeams> openAndroid() => openPlatformSeams(
    platform: DevicePlatform.android,
    environment: const {},
    beacon: hub.a,
  );

  group('a Device running on Android', () {
    test('asks its own channel for a directory, and keeps everything inside '
        'it', () async {
      registerPathsChannel(answer: androidFilesDir);

      final seams = await openAndroid();

      expect(asked, [appDataDirectoryMethod]);
      expect(seams.platform, DevicePlatform.android);
      expect(seams.profilePath, '$androidFilesDir/profile.json');
      expect(
        seams.store,
        isA<FileProfileStore>(),
        reason:
            'a directory the platform handed over is somewhere to write, '
            'so this Device keeps its identity across a restart',
      );
      expect((seams.store as FileProfileStore).path, seams.profilePath);
      expect(
        seams.defaultIncomingDirectory,
        '$androidFilesDir/incoming',
        reason:
            'Android has no Downloads folder this app may write without a '
            'permission, so its own directory is the default',
      );
    });

    test(
      'a channel that was never registered runs without persistence',
      () async {
        registerNoPathsChannel();

        final seams = await openAndroid();

        // The Kotlin side is the only thing that can answer this question on
        // Android, so a build that ships without it must still start.
        expect(seams.profilePath, isNull);
        expect(seams.defaultIncomingDirectory, isNull);
        expect(
          seams.store,
          isA<MemoryProfileStore>(),
          reason:
              'a Device with nowhere to write still pairs and transfers; it '
              'just has to be paired again after a restart',
        );
      },
    );

    test(
      'a channel that answers with an error is the same as a missing one',
      () async {
        // The two ways of not being answerable mean the same thing to the user:
        // nowhere durable to write. Neither may take the app down at startup.
        registerPathsChannel(
          failure: PlatformException(code: 'files_unavailable'),
        );

        final seams = await openAndroid();

        expect(seams.profilePath, isNull);
        expect(seams.store, isA<MemoryProfileStore>());
      },
    );

    test(
      'an empty answer is nowhere to write, not a directory named ""',
      () async {
        // An empty string joined with a filename would be `"/profile.json"` —
        // a request to write to the root of the filesystem.
        registerPathsChannel(answer: '');

        final seams = await openAndroid();

        expect(seams.profilePath, isNull);
        expect(seams.defaultIncomingDirectory, isNull);
        expect(seams.store, isA<MemoryProfileStore>());
      },
    );

    test(
      'the Device still knows it is an Android Device when it cannot write',
      () async {
        // Whether a Device can originate a copy is a fact about its platform,
        // not about its disk. Losing the directory must not quietly downgrade
        // what this Device claims to its peers.
        registerNoPathsChannel();

        final seams = await openAndroid();

        expect(seams.platform, DevicePlatform.android);
        expect(
          ClipboardCapability.forPlatform(seams.platform).canApply,
          isTrue,
          reason: 'Android can apply a Mirror in the background',
        );
        expect(
          ClipboardCapability.forPlatform(seams.platform).canOriginate,
          isFalse,
          reason: 'Android can only read its clipboard while its window is up',
        );
      },
    );
  });

  group('a Device running on Windows', () {
    test(
      'never asks the channel, because %APPDATA% already answered',
      () async {
        // Asking would throw MissingPluginException for a fact the environment
        // states. Registering a handler here is a way of noticing if the Dart
        // side ever starts asking on the wrong platform.
        registerPathsChannel(answer: androidFilesDir);

        final seams = await openPlatformSeams(
          platform: DevicePlatform.windows,
          environment: windowsEnvironment,
          beacon: hub.a,
        );

        expect(
          asked,
          isEmpty,
          reason: 'the Android-only question must not be asked on Windows',
        );
        expect(
          seams.profilePath,
          r'C:\Users\owner\AppData\Roaming/LocalTransfer/profile.json',
        );
        expect(seams.store, isA<FileProfileStore>());
        expect(
          seams.defaultIncomingDirectory,
          r'C:\Users\owner/Downloads/LocalTransfer',
        );
      },
    );

    test(
      'a host with no environment to read runs without persistence',
      () async {
        final seams = await openPlatformSeams(
          platform: DevicePlatform.windows,
          environment: const {},
          beacon: hub.a,
        );

        expect(seams.profilePath, isNull);
        expect(seams.store, isA<MemoryProfileStore>());
      },
    );
  });

  group('the seams a running app gets', () {
    test('carry the transport the caller supplied', () async {
      final seams = await openPlatformSeams(
        platform: DevicePlatform.windows,
        environment: windowsEnvironment,
        beacon: hub.a,
      );

      expect(identical(seams.beacon, hub.a), isTrue);
      expect(seams.clipboard, isA<FlutterSystemClipboard>());
    });

    test('let a first launch mint an identity and keep it', () async {
      // The whole chain, on a directory that does not exist yet — which is
      // exactly the state of `%APPDATA%/LocalTransfer` on a machine that has
      // never run this app. A store that cannot create the directory it was
      // given fails here, at the one moment it cannot afford to: before the
      // Device has a name to announce.
      final roaming = Directory.systemTemp.createTempSync('seams-first-run-');
      addTearDown(() {
        if (roaming.existsSync()) roaming.deleteSync(recursive: true);
      });
      expect(
        Directory('${roaming.path}${Platform.pathSeparator}LocalTransfer')
            .existsSync(),
        isFalse,
        reason: 'the test needs a directory that is genuinely not there yet',
      );

      final seams = await openPlatformSeams(
        platform: DevicePlatform.windows,
        environment: {'APPDATA': roaming.path, 'USERPROFILE': roaming.path},
        beacon: hub.a,
      );

      final first = await loadOrGenerateLocalProfile(
        seams.store,
        platform: seams.platform,
        alias: 'Desk',
      );
      expect(first.profile.alias, 'Desk');
      expect(
        File(seams.profilePath!).existsSync(),
        isTrue,
        reason:
            'the minted identity has to reach the disk, or the Device has '
            'to be paired again after every restart',
      );

      // And it is really there: a second Device opening the same seams is the
      // same Device.
      final reopened = await openPlatformSeams(
        platform: DevicePlatform.windows,
        environment: {'APPDATA': roaming.path, 'USERPROFILE': roaming.path},
        beacon: hub.b,
      );
      final second = await loadOrGenerateLocalProfile(
        reopened.store,
        platform: reopened.platform,
      );
      expect(second.identity.fingerprint, first.identity.fingerprint);
      expect(second.profile.alias, 'Desk');
    });
  });
}

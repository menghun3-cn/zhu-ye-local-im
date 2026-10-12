import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

/// The Windows environment as this host has it, with the separators the
/// platform actually uses in them.
const Map<String, String> windowsEnvironment = {
  'APPDATA': r'C:\Users\owner\AppData\Roaming',
  'LOCALAPPDATA': r'C:\Users\owner\AppData\Local',
  'USERPROFILE': r'C:\Users\owner',
};

void main() {
  group('profileFilePath', () {
    test('uses APPDATA on Windows', () {
      // The environment's separators are left exactly as given; only the join
      // this code does uses `/`.
      expect(
        profileFilePath(
          platform: DevicePlatform.windows,
          environment: windowsEnvironment,
        ),
        r'C:\Users\owner\AppData\Roaming/LocalTransfer/profile.json',
      );
    });

    test('falls back to the home directory when no app data root exists', () {
      expect(
        profileFilePath(
          platform: DevicePlatform.windows,
          environment: const {'USERPROFILE': r'C:\Users\owner'},
        ),
        r'C:\Users\owner/.local_transfer/profile.json',
      );
    });

    test('prefers a directory the platform handed over', () {
      // Android's private files directory, which the app asks its own channel
      // for: the process environment says nothing useful there.
      expect(
        profileFilePath(
          platform: DevicePlatform.android,
          environment: const {},
          appDataDirectory: '/data/user/0/cn.hnasct.local_transfer/files',
        ),
        '/data/user/0/cn.hnasct.local_transfer/files/profile.json',
      );
    });

    test('answers null rather than inventing somewhere to write', () {
      // The honest answer for a host that has nowhere durable: the app runs
      // without persistence instead of losing the group secret quietly.
      expect(
        profileFilePath(
          platform: DevicePlatform.android,
          environment: const {},
        ),
        isNull,
      );
      expect(
        profileFilePath(platform: DevicePlatform.other, environment: const {}),
        isNull,
      );
      expect(
        profileFilePath(
          platform: DevicePlatform.windows,
          environment: const {},
        ),
        isNull,
      );
    });

    test('ignores an empty directory rather than joining nothing', () {
      expect(
        profileFilePath(
          platform: DevicePlatform.windows,
          environment: windowsEnvironment,
          appDataDirectory: '',
        ),
        r'C:\Users\owner\AppData\Roaming/LocalTransfer/profile.json',
      );
    });
  });

  group('defaultIncomingDirectory', () {
    test('is a folder under Downloads on Windows', () {
      expect(
        defaultIncomingDirectory(
          platform: DevicePlatform.windows,
          environment: windowsEnvironment,
        ),
        r'C:\Users\owner/Downloads/LocalTransfer',
      );
    });

    test('is the app own directory on Android', () {
      expect(
        defaultIncomingDirectory(
          platform: DevicePlatform.android,
          environment: const {},
          appDataDirectory: '/data/user/0/cn.hnasct.local_transfer/files',
        ),
        '/data/user/0/cn.hnasct.local_transfer/files/incoming',
      );
    });

    test('answers null when the host has no such place', () {
      expect(
        defaultIncomingDirectory(
          platform: DevicePlatform.android,
          environment: const {},
        ),
        isNull,
      );
      expect(
        defaultIncomingDirectory(
          platform: DevicePlatform.other,
          environment: const {},
        ),
        isNull,
      );
    });
  });
}

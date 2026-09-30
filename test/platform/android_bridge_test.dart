import 'dart:io';

import 'package:test/test.dart';

/// The Android side of this application, checked without an Android device.
///
/// Two languages have to agree here and neither compiler knows about the
/// other: Dart asks a `MethodChannel` for a directory, and Kotlin answers it.
/// A rename on one side is a compile-clean, test-clean, silently broken app on
/// the other — Android would fall back to an in-memory identity and the user
/// would find out by having to pair again after every restart, which is
/// exactly the kind of failure no screen reports.
///
/// So these tests read both sources and hold them against each other. They need
/// no emulator, no SDK and no device: they are the part of the Android story
/// that can be pinned on a Windows machine, and the part that would otherwise
/// rot the moment somebody tidied a constant.
const String _seamsPath = 'lib/ui/seams.dart';
const String _kotlinPath =
    'android/app/src/main/kotlin/cn/hnasct/local_transfer/MainActivity.kt';
const String _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const String _gradlePath = 'android/app/build.gradle.kts';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

/// The one string in [source] captured by [pattern], failing loudly when the
/// shape it depends on has moved rather than reporting a confusing null.
String _capture(String source, RegExp pattern, String what) {
  final match = pattern.firstMatch(source);
  expect(
    match,
    isNotNull,
    reason:
        'could not find $what in the source it is expected to live in; '
        'this test reads the file as text and needs that one line to exist',
  );
  return match!.group(1)!;
}

void main() {
  group('the Android platform channel', () {
    late String channel;
    late String method;
    late String kotlin;

    setUpAll(() {
      final seams = _read(_seamsPath);
      // Read out of the Dart source rather than written down here, so renaming
      // the Dart constant and forgetting Kotlin is what the test catches.
      channel = _capture(
        seams,
        RegExp(r"MethodChannel\(\s*'([^']+)'"),
        'the channel Dart names',
      );
      method = _capture(
        seams,
        RegExp(r"appDataDirectoryMethod\s*=\s*'([^']+)'"),
        'the method Dart asks for',
      );
      kotlin = _read(_kotlinPath);
    });

    test('Dart asks for the channel Kotlin registers, by name', () {
      expect(
        kotlin,
        contains('"$channel"'),
        reason:
            'Dart asks "$channel" but Kotlin registers something else, '
            'so every call would arrive as a MissingPluginException',
      );
    });

    test('Dart asks for the method Kotlin handles, by name', () {
      expect(
        kotlin,
        contains('"$method"'),
        reason:
            'Kotlin would answer $method with notImplemented(), which '
            'Dart reads as "nowhere to write" — the app would run with its '
            'identity in memory and never say so',
      );
    });

    test('the channel is a door onto one string, and it opens', () {
      // The answer is a real absolute directory. An empty string would be
      // accepted by the Dart side as a directory and then fail to be one, so
      // the Kotlin handler must not be able to produce one by accident.
      expect(
        // `filesDir` is the app's private, always-writable directory — the one
        // place on Android this process may write without a permission.
        kotlin,
        contains('filesDir.absolutePath'),
        reason: 'the answer must be Android\'s own files directory',
      );
    });

    test('an unknown method is refused, not left unanswered', () {
      // Dart catches PlatformException and MissingPluginException to decide
      // there is nowhere durable to write. A handler that answered nothing
      // would leave the call pending forever and the app would never start.
      expect(
        kotlin,
        contains('result.notImplemented()'),
        reason:
            'a call this channel does not know must come back as an '
            'error Dart can catch, rather than never coming back',
      );
    });
  });

  group('the Android application shell', () {
    test('the Activity that registers the channel is the one the manifest '
        'launches', () {
      final manifest = _read(_manifestPath);
      final gradle = _read(_gradlePath);
      final kotlin = _read(_kotlinPath);

      // `.MainActivity` in the manifest is resolved against the Gradle
      // namespace, so those two agreeing is what makes the declared Activity
      // the class that exists.
      final namespace = _capture(
        gradle,
        RegExp(r'namespace\s*=\s*"([^"]+)"'),
        'the Gradle namespace',
      );
      final package = _capture(
        kotlin,
        RegExp(r'^package\s+(\S+)', multiLine: true),
        'the Kotlin package',
      );
      expect(
        package,
        namespace,
        reason:
            'the manifest resolves .MainActivity against the Gradle '
            'namespace, so a Kotlin class in another package would simply '
            'never be instantiated — and the app would launch with no channel '
            'at all',
      );

      // And the class really is where its package says it is.
      expect(
        _kotlinPath,
        'android/app/src/main/kotlin/${package.replaceAll('.', '/')}'
        '/MainActivity.kt',
      );
      expect(manifest, contains('android:name=".MainActivity"'));
      // ...and is the launcher entry point, which is what makes the channel
      // registered in practice rather than only in theory.
      expect(manifest, contains('android.intent.category.LAUNCHER'));
    });

    test('INTERNET is declared, because every feature is a socket', () {
      // Discovery is a UDP broadcast, a Session is TCP, Pairing listens on a
      // port. Android grants no socket without this, so its absence is not a
      // degraded app but a product that cannot do anything at all.
      expect(
        _read(_manifestPath),
        contains('android.permission.INTERNET'),
        reason: 'without INTERNET every socket throws on Android',
      );
    });
  });
}

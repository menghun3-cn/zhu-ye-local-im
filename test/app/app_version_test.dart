import 'dart:io';

import 'package:local_transfer/app/app.dart';
import 'package:test/test.dart';

/// The version this build claims, and the comparison the About page makes.
///
/// Plain Dart, and so in `test/` rather than `test_flutter/`: neither the
/// constant nor the comparison needs a widget tree, and the comparison is the
/// one piece of the upgrade path that can be wrong in a way nobody would notice
/// — an update that is offered when there is none, or missed when there is.
void main() {
  group('appVersion', () {
    test('is the version pubspec.yaml publishes', () {
      // Two places hold one fact. A mismatch is a build that tells its user the
      // wrong number, and that is the number they quote when reporting a
      // problem — so the pubspec is read here rather than trusted, which is
      // what makes them the same place in practice.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml still declares a version');
      expect(
        match!.group(1)!.split('+').first,
        appVersion,
        reason: 'bump both, or the About page lies about what is running',
      );
    });
  });

  group('isNewerVersion', () {
    test('compares the numbers rather than the strings', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
      // "1.10.0" is older than "1.9.0" read as text, and nobody means that.
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('1.9.0', '1.10.0'), isFalse);
    });

    test('is not fooled by the same version written twice', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0'), isFalse);
      expect(isNewerVersion('0.9.0', '1.0.0'), isFalse);
    });

    test('reads through the punctuation a tag is written with', () {
      expect(isNewerVersion('v1.2.0', '1.1.0'), isTrue);
      expect(isNewerVersion('1.2.0-rc1', '1.1.0'), isTrue);
      expect(isNewerVersion('1.2.0+7', '1.2.0'), isFalse);
      expect(isNewerVersion('release-1.2.0', '1.1.0'), isTrue);
    });

    test('treats a version it cannot parse as the oldest there is', () {
      expect(isNewerVersion('nightly', '1.0.0'), isFalse);
      expect(isNewerVersion('', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', 'nightly'), isTrue);
      expect(versionNumbers('nightly'), isEmpty);
      expect(versionNumbers('v1.2.3-rc1'), [1, 2, 3]);
    });
  });
}

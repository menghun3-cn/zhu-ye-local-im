import 'dart:io';

import 'package:test/test.dart';

void main() {
  // `lib/core` and `lib/app` both claim to be plain Dart, and the whole reason
  // the application can be accepted from `dart test` on a machine where no
  // widget test can run is that the claim is true. A claim nothing checks is a
  // comment; this is the check.
  group('the layers that claim to be plain Dart', () {
    final roots = ['lib/core', 'lib/app'];

    test('exist', () {
      for (final root in roots) {
        expect(
          Directory(root).existsSync(),
          isTrue,
          reason: 'expected $root to exist relative to ${Directory.current}',
        );
      }
    });

    test('import no Flutter', () {
      final flutterImport = RegExp(
        '^\\s*(import|export)\\s+[\'"]package:flutter[/\'"]',
      );
      final offenders = <String>[];
      var scanned = 0;
      for (final root in roots) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          scanned++;
          for (final line in entity.readAsLinesSync()) {
            if (flutterImport.hasMatch(line)) {
              offenders.add('${entity.path}: ${line.trim()}');
            }
          }
        }
      }
      // A glob that matched nothing would make this pass for the wrong reason.
      expect(scanned, greaterThan(20));
      expect(
        offenders,
        isEmpty,
        reason:
            'these files reach for Flutter, which would put them out of reach '
            'of `dart test`:\n${offenders.join('\n')}',
      );
    });
  });
}

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

  // The other half of the same boundary. Flutter lives in `lib/ui` and nowhere
  // else, so "would this file need a widget tree to test" is answered by its
  // path — which is the only answer available on a machine where no widget
  // test can run.
  group('the Flutter-facing layer', () {
    final flutterImport = RegExp(
      '^\\s*(import|export)\\s+[\'"]package:flutter[/\'"]',
    );

    test('exists and has the widgets in it', () {
      final directory = Directory('lib/ui');
      expect(directory.existsSync(), isTrue);
      final files = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(files.length, greaterThan(4));
    });

    test('is the only layer that imports Flutter', () {
      final offenders = <String>[];
      var scanned = 0;
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(Platform.pathSeparator, '/');
        if (path.startsWith('lib/ui/') || path == 'lib/main.dart') continue;
        scanned++;
        for (final line in entity.readAsLinesSync()) {
          if (flutterImport.hasMatch(line)) {
            offenders.add('$path: ${line.trim()}');
          }
        }
      }
      // A glob that matched nothing would make this pass for the wrong reason.
      expect(scanned, greaterThan(20));
      expect(
        offenders,
        isEmpty,
        reason:
            'Flutter is confined to lib/ui, so these files are in the wrong '
            'place:\n${offenders.join('\n')}',
      );
    });
  });
}

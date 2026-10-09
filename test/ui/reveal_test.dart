import 'dart:io';

import 'package:local_transfer/ui/reveal.dart';
import 'package:test/test.dart';

void main() {
  // "Show me where that file went" is answered by opening its folder, and the
  // folder is worked out here rather than by the shell. The one answer worth
  // pinning down is the *refusal*: a path with no directory part resolves to the
  // process's working directory, and opening that would be opening a folder
  // nobody asked about.
  group('folderOf', () {
    final sep = Platform.pathSeparator;

    test('names the folder a file sits in', () {
      expect(
        folderOf(['some', 'inbox', 'photo.png'].join(sep)),
        ['some', 'inbox'].join(sep),
      );
    });

    test('a bare file name names no folder', () {
      expect(
        folderOf('photo.png'),
        isNull,
        reason: 'its folder would be wherever the app was launched from',
      );
    });

    test('an empty path names no folder', () {
      expect(folderOf(''), isNull);
    });

    test('a file in a nested folder names the folder beside it', () {
      expect(folderOf(['a', 'b', 'c.png'].join(sep)), ['a', 'b'].join(sep));
    });
  });
}

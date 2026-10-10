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

  // `explorer` is the one consumer of a path that will not read it as a string:
  // it parses `/` as the start of a switch of its own, so the folder has to be
  // spelled its way before it goes out.
  group('explorerArgument', () {
    test('a slash-spelled folder becomes the one Explorer expects', () {
      expect(
        explorerArgument(r'C:\Users\me/Downloads/LocalTransfer'),
        r'C:\Users\me\Downloads\LocalTransfer',
      );
    });

    test('a folder already spelled for Windows is left alone', () {
      expect(explorerArgument(r'D:\inbox'), r'D:\inbox');
    });

    test('a whole path end to end: a received file resolves to its folder', () {
      // The shape the app actually builds for a received file: the folder comes
      // from `defaultIncomingDirectory` (joined with `/`) and the name from
      // `incomingPathFor` (joined with the host separator). Explorer given that
      // folder verbatim reads `C:` and two switches, and opens Documents.
      final received = [
        'C:/Users/me/Downloads/LocalTransfer',
        'report.bin',
      ].join(Platform.pathSeparator);
      final folder = folderOf(received);
      expect(folder, isNotNull);
      expect(explorerArgument(folder!), r'C:\Users\me\Downloads\LocalTransfer');
    });
  });
}

import 'dart:io';

import 'package:local_transfer/app/app.dart';
import 'package:test/test.dart';

void main() {
  // A folder send is a walk over the user's disk before it is an Offer, and
  // what the walk keeps — and what it refuses to keep — is the whole of what
  // the receiver will rebuild. These tests pin that shape.
  group('listFolderForSend', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('local-transfer-folder-');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// Writes [content] to [relative] under [root], making parents as needed.
    File plant(String relative, [String content = 'x']) {
      final file = File('${root.path}${Platform.pathSeparator}$relative');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      return file;
    }

    test('names every file by its place in the tree', () async {
      plant('notes.txt', 'flat');
      plant('sub/deep/photo.jpg', 'nested');
      plant('empty-dir-marker/.keep', '');

      final listing = await listFolderForSend(root);

      expect(listing.rootName, root.path.split(RegExp(r'[/\\]')).last);
      expect(
        {for (final entry in listing.entries) entry.relativePath},
        {'notes.txt', 'sub/deep/photo.jpg', 'empty-dir-marker/.keep'},
      );
    });

    test('sums the sizes it reports', () async {
      plant('a.txt', '12345');
      plant('sub/b.txt', '12');

      final listing = await listFolderForSend(root);

      expect(listing.totalBytes, 7);
    });

    test('an empty directory produces no entries', () async {
      Directory('${root.path}${Platform.pathSeparator}nothing').createSync();

      final listing = await listFolderForSend(root);

      expect(listing.entries, isEmpty);
      expect(listing.totalBytes, 0);
    });

    test('the walk completes around ordinary entries', () async {
      plant('here.txt');
      plant('sub/there.txt');

      final listing = await listFolderForSend(root);

      expect(listing.entries, hasLength(2));
      expect(listing.skipped, 0);
    });

    test('a path that is not a directory lists nothing', () async {
      final file = plant('just-a-file.txt');

      final listing = await listFolderForSend(Directory(file.path));

      expect(listing.entries, isEmpty);
    });

    test('a link is not followed out of the folder', () async {
      // Links are the one entry the walk refuses on purpose: following one
      // would send bytes outside the folder the user picked. Whether this
      // platform lets a test create one at all varies — unprivileged Windows
      // cannot — so the test asserts the invariant when it can set up, and
      // says nothing when it cannot.
      final outside = Directory.systemTemp.createTempSync('outside-');
      addTearDown(() {
        if (outside.existsSync()) outside.deleteSync(recursive: true);
      });
      File('${outside.path}${Platform.pathSeparator}secret.txt')
          .writeAsStringSync('not yours');

      final linkPath = '${root.path}${Platform.pathSeparator}linked';
      try {
        await Link(linkPath).create(outside.path);
      } on Object {
        return;
      }

      final listing = await listFolderForSend(root);

      expect(
        listing.entries.map((entry) => entry.relativePath),
        isNot(contains('linked/secret.txt')),
        reason: 'a link must not carry the outside folder into the send',
      );
      expect(listing.skipped, greaterThan(0));
    });
  });
}

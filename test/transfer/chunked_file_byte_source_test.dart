import 'dart:io';
import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // The source a folder send puts under every item: it holds no handle between
  // reads, which is what lets a send name thousands of files without locking
  // them all for as long as the Offer sits unanswered.
  group('ChunkedFileByteSource', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('chunked-source-');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    File plant(String name, List<int> bytes) {
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      file.writeAsBytesSync(bytes);
      return file;
    }

    test('reads the file back in slices', () async {
      final bytes = Uint8List.fromList(
        List.generate(200000, (index) => index % 251),
      );
      final source = await ChunkedFileByteSource.open(plant('big.bin', bytes));

      expect(source.length, bytes.length);
      final first = await source.read(0, 100);
      final middle = await source.read(150000, 50000);
      final tail = await source.read(bytes.length - 7, 7);

      expect(first, equals(bytes.sublist(0, 100)));
      expect(middle, equals(bytes.sublist(150000, 200000)));
      expect(tail, equals(bytes.sublist(bytes.length - 7)));
      await source.close();
    });

    test('hashes to the same digest a held handle would', () async {
      final bytes = Uint8List.fromList(List.generate(150000, (i) => i % 13));
      final source = await ChunkedFileByteSource.open(plant('hash.bin', bytes));

      expect(await digestOfSource(source), sha256Hex(bytes));
      await source.close();
    });

    test('a read outside the file is refused', () async {
      final source = await ChunkedFileByteSource.open(
        plant('small.bin', [1, 2, 3]),
      );

      await expectLater(source.read(2, 2), throwsRangeError);
      await expectLater(source.read(-1, 1), throwsRangeError);
      await source.close();
    });

    test('a path that is not a file is refused at open', () async {
      await expectLater(
        ChunkedFileByteSource.open(File(directory.path)),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('a file that is gone fails on its first read', () async {
      final file = plant('gone.bin', [1, 2, 3]);
      final source = await ChunkedFileByteSource.open(file);
      await file.delete();

      await expectLater(source.read(0, 3), throwsA(isA<FileSystemException>()));
      await source.close();
    });
  });
}

import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('memory sources', () {
    test('reads a slice and refuses a read outside itself', () async {
      final source = MemoryByteSource(const [1, 2, 3, 4]);
      expect(source.length, 4);
      expect(await source.read(1, 2), [2, 3]);
      await expectLater(source.read(3, 2), throwsRangeError);
      await expectLater(source.read(-1, 1), throwsRangeError);
    });

    test('hashing reads the whole item', () async {
      final bytes = List<int>.generate(200000, (index) => index % 256);
      expect(await digestOfSource(MemoryByteSource(bytes)), sha256Hex(bytes));
    });

    test('an empty item hashes to the digest of nothing', () async {
      // Not an error: an empty file still has a digest, and a transfer of one
      // still has to be verifiable.
      expect(
        await digestOfSource(MemoryByteSource(const [])),
        sha256Hex(const []),
      );
    });
  });

  group('file sources', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('transfer-source'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a file through one handle', () async {
      final bytes = List<int>.generate(100000, (index) => index % 251);
      final file = File('${dir.path}/item.bin')..writeAsBytesSync(bytes);
      final source = await FileByteSource.open(file);
      addTearDown(source.close);

      expect(source.length, bytes.length);
      expect(await source.read(0, 3), [0, 1, 2]);
      expect(await source.read(bytes.length - 2, 2), [
        bytes[bytes.length - 2],
        bytes[bytes.length - 1],
      ]);
      expect(await digestOfSource(source), sha256Hex(bytes));
    });

    test('refuses a read past the end rather than returning short', () async {
      final file = File('${dir.path}/short.bin')..writeAsBytesSync([1, 2, 3]);
      final source = await FileByteSource.open(file);
      addTearDown(source.close);

      await expectLater(source.read(2, 2), throwsRangeError);
    });

    test('closing twice is harmless', () async {
      final file = File('${dir.path}/twice.bin')..writeAsBytesSync([1]);
      final source = await FileByteSource.open(file);
      await source.close();
      await source.close();
      expect(source.isClosed, isTrue);
    });
  });

  group('memory sinks', () {
    test('appends slices and hashes exactly what it holds', () async {
      final sink = MemoryPayloadSink();
      await sink.write(0, const [1, 2, 3]);
      await sink.write(3, const [4]);

      expect(sink.bytesWritten, 4);
      expect(sink.bytes, [1, 2, 3, 4]);
      expect(await sink.digest(), sha256Hex(const [1, 2, 3, 4]));
      expect(await sink.digest(), sha256Hex(const [1, 2, 3, 4]));
    });

    test('refuses a slice that would leave a hole', () async {
      final sink = MemoryPayloadSink();
      await sink.write(0, const [1, 2]);

      await expectLater(
        sink.write(3, const [4]),
        throwsA(isA<ProtocolException>()),
      );
      expect(sink.bytesWritten, 2);
    });

    test('refuses a slice that repeats what is already held', () async {
      final sink = MemoryPayloadSink();
      await sink.write(0, const [1, 2, 3]);

      await expectLater(
        sink.write(1, const [9]),
        throwsA(isA<ProtocolException>()),
      );
      expect(sink.bytes, [1, 2, 3]);
    });
  });

  group('file sinks', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('transfer-sink'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes slices to the right offsets', () async {
      final file = File('${dir.path}/item.bin');
      final sink = await FilePayloadSink.open(file);
      addTearDown(sink.close);

      await sink.write(0, const [1, 2, 3]);
      await sink.write(3, const [4, 5]);

      expect(sink.bytesWritten, 5);
      expect(file.readAsBytesSync(), [1, 2, 3, 4, 5]);
      expect(await sink.digest(), sha256Hex(const [1, 2, 3, 4, 5]));
    });

    test('adopting a partial file hashes the part already there', () async {
      final file = File('${dir.path}/partial.bin')..writeAsBytesSync([1, 2, 3]);
      final sink = await FilePayloadSink.open(file, resume: true);
      addTearDown(sink.close);

      expect(sink.bytesWritten, 3);
      await sink.write(3, const [4, 5]);

      // The digest covers the whole item, not only the part this run wrote:
      // otherwise a resumed transfer would be verified against a fragment.
      expect(await sink.digest(), sha256Hex(const [1, 2, 3, 4, 5]));
      expect(file.readAsBytesSync(), [1, 2, 3, 4, 5]);
    });

    test('without resume the bytes already there are discarded', () async {
      final file = File('${dir.path}/stale.bin')
        ..writeAsBytesSync([9, 9, 9, 9]);
      final sink = await FilePayloadSink.open(file);
      addTearDown(sink.close);

      expect(sink.bytesWritten, 0);
      await sink.write(0, const [1]);
      expect(file.readAsBytesSync(), [1]);
      expect(await sink.digest(), sha256Hex(const [1]));
    });

    test('resuming an absent file starts from nothing', () async {
      final sink = await FilePayloadSink.open(
        File('${dir.path}/missing.bin'),
        resume: true,
      );
      addTearDown(sink.close);

      expect(sink.bytesWritten, 0);
      await sink.write(0, const [7]);
      expect(await sink.digest(), sha256Hex(const [7]));
    });

    test('refuses a slice that does not continue the file', () async {
      final file = File('${dir.path}/gap.bin');
      final sink = await FilePayloadSink.open(file);
      addTearDown(sink.close);

      await expectLater(
        sink.write(4, const [1]),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}

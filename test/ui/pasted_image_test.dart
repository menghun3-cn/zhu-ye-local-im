import 'dart:io';
import 'dart:typed_data';

import 'package:local_transfer/ui/pasted_image.dart';
import 'package:test/test.dart';

void main() {
  // A clipboard entry has no name, so these bytes are the only thing that can
  // say what it is. Getting this wrong is not cosmetic: a `.png` name on
  // something else is a bubble that can never decode.
  group('imageExtensionOf', () {
    test('names a PNG by its whole signature, not its first four bytes', () {
      expect(imageExtensionOf(_png), 'png');
      // "PNG" followed by anything else is not a PNG. An extension sniffing
      // four bytes would call this one, and the decoder would disagree.
      expect(
        imageExtensionOf(Uint8List.fromList(const [0x50, 0x4E, 0x47, 0x21])),
        isNull,
      );
    });

    test('names the other formats this app can draw', () {
      expect(imageExtensionOf(_bytes([0x42, 0x4D, 0x00, 0x00])), 'bmp');
      expect(imageExtensionOf(_bytes([0xFF, 0xD8, 0xFF, 0xE0])), 'jpg');
      expect(
        imageExtensionOf(_bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
        'gif',
      );
      expect(
        imageExtensionOf(
          _bytes([
            0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, //
            0x57, 0x45, 0x42, 0x50,
          ]),
        ),
        'webp',
      );
    });

    test('a RIFF file that is not WebP is not an image', () {
      // WAV shares the container with WebP and differs only at byte 8.
      expect(
        imageExtensionOf(
          _bytes([
            0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, //
            0x57, 0x41, 0x56, 0x45,
          ]),
        ),
        isNull,
      );
    });

    test('says nothing about what it does not recognise', () {
      expect(imageExtensionOf(Uint8List(0)), isNull);
      expect(imageExtensionOf(_bytes([0x50])), isNull);
      expect(imageExtensionOf(_bytes('just some text'.codeUnits)), isNull);
      expect(
        imageExtensionOf(_bytes([0x50, 0x4B, 0x03, 0x04])),
        isNull,
        reason: 'a zip',
      );
    });

    test('a signature that is cut short is not a match', () {
      // The PNG signature is eight bytes; seven of them prove nothing, and
      // reading past the end would be the alternative.
      expect(
        imageExtensionOf(_bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A])),
        isNull,
      );
    });
  });

  group('writePastedImage', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('local-transfer-paste-');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('writes the bytes to a file the Transfer can stream from', () async {
      final file = await writePastedImage(_png, into: directory);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(await file.readAsBytes(), _png);
      expect(file.parent.path, directory.path);
    });

    test('names the file after what the bytes are', () async {
      final file = await writePastedImage(_png, into: directory);
      expect(file!.path, endsWith('.png'));
      // The engine draws an image bubble by reading the file, so the name has
      // to be one `looksLikeImage` would accept as well as one a decoder can.
      expect(
        file.path.split(Platform.pathSeparator).last,
        startsWith('pasted-'),
      );
    });

    test('creates the directory when it is not there yet', () async {
      final nested = Directory(
        '${directory.path}${Platform.pathSeparator}deep',
      );
      expect(nested.existsSync(), isFalse);
      final file = await writePastedImage(_png, into: nested);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
    });

    test('answers null rather than writing something unreadable', () async {
      final file = await writePastedImage(
        _bytes('not a picture at all'.codeUnits),
        into: directory,
      );
      expect(file, isNull);
      // Nothing was left behind, either: a stray file in the temp directory is
      // the kind of thing that outlives the bug that made it.
      expect(directory.listSync(), isEmpty);
    });

    test('two pastes of the same picture are two files', () async {
      final first = await writePastedImage(_png, into: directory);
      final second = await writePastedImage(_png, into: directory);
      expect(first!.path, isNot(second!.path));
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);
    });
  });
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// The smallest real PNG there is: a 1x1 transparent pixel.
final Uint8List _png = _bytes(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
  0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]);

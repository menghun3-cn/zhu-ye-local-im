import 'dart:io';
import 'dart:typed_data';

/// What a clipboard's image bytes are, named by the bytes themselves.
///
/// Not by a file extension, because a clipboard entry has no name at all: the
/// only thing that can say what these bytes are is the bytes. Windows hands
/// over a `bmp` (the platform's own encoding, which is why it is first here),
/// macOS and the web hand over a `png`, and a file copied in Explorer is not
/// touched at all — that path never goes through here.
///
/// Returns null for anything this app cannot draw, which is the caller's signal
/// that the clipboard held no picture worth sending. Null rather than a
/// fallback extension on purpose: a `.png` name on a JPEG's bytes would be a
/// bubble that can only ever fail to decode.
String? imageExtensionOf(Uint8List bytes) {
  // PNG: 89 50 4E 47 0D 0A 1A 0A. The full eight bytes, not the four an
  // extension is named after — the remaining four are the ones that make it a
  // PNG rather than a file that merely starts with "PNG".
  if (_startsWith(bytes, const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return 'png';
  }
  // BMP: "BM". Two bytes is all the format gives.
  if (_startsWith(bytes, const [0x42, 0x4D])) return 'bmp';
  // JPEG: FF D8 FF, the start-of-image marker and the first byte of every
  // segment that may follow it.
  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return 'jpg';
  // GIF: "GIF8" — the version digit is 7 or 8 and both are GIF.
  if (_startsWith(bytes, const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  // WebP: "RIFF" at 0, the chunk size at 4, "WEBP" at 8.
  if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      bytes.length >= 12 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}

/// Writes clipboard image [bytes] to a file a Transfer can stream from.
///
/// A path rather than the bytes because that is what the transfer engine reads
/// from: an image message is offered with a digest and streamed from a file,
/// exactly as a chosen one is. The file is left behind deliberately — the
/// sender's own bubble points at it, and deleting it the moment the offer goes
/// out would leave that bubble with nothing to draw.
///
/// Returns null when [bytes] are not an image this app can draw, so a clipboard
/// holding something else is not turned into a message.
Future<File?> writePastedImage(Uint8List bytes, {Directory? into}) async {
  final extension = imageExtensionOf(bytes);
  if (extension == null) return null;

  final directory = into ?? Directory.systemTemp;
  if (!directory.existsSync()) directory.createSync(recursive: true);

  // The clock is the seed, not the guarantee: two pastes in the same
  // microsecond would otherwise land on one path and the second would overwrite
  // the first while its Transfer was still reading it.
  final stamp = DateTime.now().microsecondsSinceEpoch;
  for (var attempt = 0; ; attempt++) {
    final suffix = attempt == 0 ? '' : '-$attempt';
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'pasted-$stamp$suffix.$extension',
    );
    if (file.existsSync()) continue;
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

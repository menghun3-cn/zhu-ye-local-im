import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'running_digest.dart';
import 'transfer.dart';

/// Bytes an outgoing Transfer reads an item from.
///
/// Reading rather than holding. This is what lets a multi-gigabyte file be
/// offered without ever being in memory at once, and what lets a resumed
/// Transfer start from the middle of an item instead of its beginning.
abstract interface class ByteSource {
  /// The item's total length in bytes.
  int get length;

  /// Reads [count] bytes starting at [offset].
  ///
  /// Returns fewer bytes than asked for only at the end of the source. A
  /// source that returns nothing while bytes remain is treated as truncated,
  /// and the Transfer fails rather than sending a short item.
  Future<Uint8List> read(int offset, int count);

  /// Releases the underlying handle. Safe to call more than once.
  Future<void> close();
}

/// A [ByteSource] over bytes already in memory.
final class MemoryByteSource implements ByteSource {
  MemoryByteSource(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  bool _closed = false;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > _bytes.length) {
      throw RangeError(
        'a read of $count bytes at $offset is outside 0..${_bytes.length}',
      );
    }
    return Uint8List.sublistView(_bytes, offset, offset + count);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

/// A [ByteSource] over a file on disk.
///
/// The length is taken once, when the file is opened, and never re-read: an
/// item whose size changes mid-transfer would otherwise be sent as a stream
/// that does not match the digest promised in the Offer.
final class FileByteSource implements ByteSource {
  FileByteSource._(this.file, this._handle, this.length);

  /// Opens [file] and fixes its length for the life of the source.
  static Future<FileByteSource> open(File file) async {
    final handle = await file.open();
    final length = await handle.length();
    return FileByteSource._(file, handle, length);
  }

  /// The file being read.
  final File file;

  final RandomAccessFile _handle;
  bool _closed = false;

  @override
  final int length;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw RangeError(
        'a read of $count bytes at $offset is outside 0..$length',
      );
    }
    await _handle.setPosition(offset);
    return Uint8List.fromList(await _handle.read(count));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _handle.close();
  }

  @override
  String toString() => 'FileByteSource(${file.path}, $length bytes)';
}

/// SHA-256 of a whole [source], as lowercase hex.
///
/// Read before the Offer goes out: a digest in an Offer is a promise about
/// bytes that have not moved yet, so the sender has to have seen them.
Future<String> digestOfSource(ByteSource source) async {
  final digest = RunningDigest();
  var offset = 0;
  while (offset < source.length) {
    final count = math.min(transferChunkBytes, source.length - offset);
    final block = await source.read(offset, count);
    if (block.isEmpty) {
      throw StateError(
        'the source ended at $offset of ${source.length} bytes while being '
        'hashed',
      );
    }
    digest.add(block);
    offset += block.length;
  }
  return digest.finish();
}

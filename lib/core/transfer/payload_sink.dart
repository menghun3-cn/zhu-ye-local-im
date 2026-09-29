import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../protocol/frame.dart';
import 'running_digest.dart';
import 'transfer.dart';

/// Where a receiving Transfer puts an item's bytes.
///
/// A sink holds one contiguous run that starts at byte zero. A write must
/// continue that run exactly: a slice starting before its end is the peer
/// repeating itself, and one starting after it leaves a hole nothing will ever
/// fill. Both are refused at once rather than tolerated, because a hole makes
/// the item hash to something that cannot match the Offer, and that failure
/// would otherwise surface much later as a corrupt file with no explanation.
abstract interface class PayloadSink {
  /// Bytes held so far.
  ///
  /// This is also the offset a resumed Transfer reports in its acceptance: a
  /// receiver says "I already have this much" by handing over the partial file
  /// it kept from last time.
  int get bytesWritten;

  /// Appends [data] at [offset], which must equal [bytesWritten].
  Future<void> write(int offset, List<int> data);

  /// SHA-256 of everything held, as lowercase hex.
  Future<String> digest();

  /// Releases the underlying handle. Safe to call more than once.
  Future<void> close();
}

/// A [PayloadSink] that keeps everything in memory.
///
/// For payloads small enough to hold — text, a photo, a test fixture. A file
/// of any size belongs in a [FilePayloadSink], which is why this one exists at
/// all rather than being the only option.
final class MemoryPayloadSink implements PayloadSink {
  MemoryPayloadSink();

  final BytesBuilder _buffer = BytesBuilder(copy: true);
  final RunningDigest _digest = RunningDigest();
  int _written = 0;
  bool _closed = false;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  @override
  int get bytesWritten => _written;

  /// The bytes received so far, as a copy.
  Uint8List get bytes => _buffer.toBytes();

  @override
  Future<void> write(int offset, List<int> data) async {
    if (offset != _written) {
      throw ProtocolException(
        'a slice at $offset does not continue the $_written byte(s) already '
        'held',
      );
    }
    _buffer.add(data);
    _digest.add(data);
    _written += data.length;
  }

  @override
  Future<String> digest() async => _digest.finish();

  @override
  Future<void> close() async {
    _closed = true;
  }

  @override
  String toString() => 'MemoryPayloadSink($_written bytes)';
}

/// A [PayloadSink] that writes straight to a file.
final class FilePayloadSink implements PayloadSink {
  FilePayloadSink._(this.file, this._handle, this._digest, this._written);

  /// Opens [file] for an incoming item.
  ///
  /// With `resume: false` anything already in the file is discarded, so a stale
  /// partial download cannot be spliced onto a fresh one. With `resume: true`
  /// the existing bytes are kept, hashed and adopted, and their count becomes
  /// the offset this receiver asks the sender to start from.
  static Future<FilePayloadSink> open(File file, {bool resume = false}) async {
    final hasPrefix = resume && await file.exists() && await file.length() > 0;
    final handle = await file.open(
      mode: hasPrefix ? FileMode.append : FileMode.write,
    );
    final written = hasPrefix ? await handle.length() : 0;
    final digest = RunningDigest();
    if (written > 0) {
      // The adopted prefix has to go through the hash as well, or the item
      // would be verified against only the part this run downloaded.
      await handle.setPosition(0);
      var read = 0;
      while (read < written) {
        final block = await handle.read(
          math.min(transferChunkBytes, written - read),
        );
        if (block.isEmpty) {
          await handle.close();
          throw StateError(
            '${file.path} ended after $read of $written bytes while being '
            'adopted',
          );
        }
        digest.add(block);
        read += block.length;
      }
      await handle.setPosition(written);
    }
    return FilePayloadSink._(file, handle, digest, written);
  }

  /// The file being written.
  final File file;

  final RandomAccessFile _handle;
  final RunningDigest _digest;
  int _written;
  bool _closed = false;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  @override
  int get bytesWritten => _written;

  @override
  Future<void> write(int offset, List<int> data) async {
    if (offset != _written) {
      throw ProtocolException(
        'a slice at $offset does not continue the $_written byte(s) already '
        'held',
      );
    }
    await _handle.setPosition(offset);
    await _handle.writeFrom(data);
    _digest.add(data);
    _written = offset + data.length;
  }

  @override
  Future<String> digest() async => _digest.finish();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _handle.close();
  }

  @override
  String toString() => 'FilePayloadSink(${file.path}, $_written bytes)';
}

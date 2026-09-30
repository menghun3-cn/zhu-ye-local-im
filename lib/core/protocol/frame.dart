import 'dart:convert';
import 'dart:typed_data';

/// Raised when wire data does not conform to the rules this build expects.
///
/// Shared by the framing layer and by discovery: both read bytes from whoever
/// happens to be on the link, and both want a single error type meaning "this
/// was not usable" rather than a different one per layer.
final class ProtocolException implements Exception {
  const ProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}

/// The largest frame this implementation will accept, in bytes.
///
/// A frame's length arrives as an attacker-controlled 32-bit integer, so an
/// unbounded decoder can be made to allocate 4 GiB from a nine-byte prefix.
/// Every frame is therefore rejected above this ceiling, which is comfortably
/// larger than the bulk chunk size the transfer layer uses.
const int maxFrameBytes = 1 << 24; // 16 MiB

/// The nonce length a sealed record carries.
///
/// Pinned at the framing layer so a record is self-describing; it matches
/// ChaCha20-Poly1305's 96-bit nonce.
const int sealedNonceBytes = 12;

/// The Poly1305 authentication tag length in bytes.
const int sealedTagBytes = 16;

/// What a frame carries.
enum FrameKind {
  /// A UTF-8 JSON control message.
  control(0x01),

  /// A slice of a bulk payload: transfer id, byte offset, raw bytes.
  chunk(0x02),

  /// An AEAD-sealed record whose plaintext is exactly one further frame.
  ///
  /// Sealing happens a layer above framing rather than below it so the same
  /// decoder serves both the plaintext handshake and the encrypted session:
  /// there is no point mid-stream where a half-consumed read buffer has to be
  /// handed from one layer to another.
  sealed(0x03);

  const FrameKind(this.code);

  /// The wire value of this kind.
  final int code;

  /// Resolves a wire value, or throws [ProtocolException] if unknown.
  static FrameKind fromCode(int code) {
    for (final kind in FrameKind.values) {
      if (kind.code == code) return kind;
    }
    throw ProtocolException('unknown frame kind 0x${code.toRadixString(16)}');
  }
}

/// A unit of the wire protocol.
sealed class Frame {
  const Frame();
}

/// A JSON control message, such as an offer or an acceptance.
final class ControlFrame extends Frame {
  ControlFrame(this.json);

  /// The message body. Keys are ASCII; values are JSON-encodable.
  final Map<String, Object?> json;

  @override
  String toString() => 'ControlFrame(${json['t']})';
}

/// A slice of bulk payload bytes.
///
/// [offset] is the byte offset of [data] within the item named by [itemId],
/// which is what makes a transfer resumable: the receiver can persist what it
/// has and ask for the remainder rather than the whole file.
///
/// Both ids are on the wire because one Transfer may name several items, each
/// with its own byte stream and its own offsets. Without [itemId] a receiver
/// holding a three-file Transfer could not tell which file a slice at offset
/// zero belongs to, and would have to infer it from the order slices arrived.
final class ChunkFrame extends Frame {
  ChunkFrame({
    required this.transferId,
    required this.itemId,
    required this.offset,
    required this.data,
  });

  /// Identifies the Transfer this slice belongs to.
  final String transferId;

  /// Identifies the item inside [transferId] that [data] belongs to.
  final String itemId;

  /// Byte offset of [data] within the item's byte stream.
  final int offset;

  /// The payload bytes.
  final Uint8List data;

  @override
  String toString() =>
      'ChunkFrame($transferId/$itemId @$offset, ${data.length} bytes)';
}

/// An encrypted record: a nonce, then ciphertext with its Poly1305 tag.
///
/// The plaintext is the full encoding of exactly one inner [Frame], so secrecy
/// needs no separate record framing of its own.
final class SealedFrame extends Frame {
  SealedFrame({required this.nonce, required this.cipherText});

  /// Bytes the AEAD is unique per message; reusing one with the same key
  /// breaks ChaCha20-Poly1305 catastrophically.
  final Uint8List nonce;

  /// Ciphertext followed by the 16-byte authentication tag.
  final Uint8List cipherText;

  @override
  String toString() =>
      'SealedFrame(${nonce.length} byte nonce, ${cipherText.length} bytes)';
}

/// Encodes [frame] into the wire form: `u32 length | u8 kind | payload`.
///
/// `length` counts the kind byte plus the payload, so a decoder always knows
/// how many further bytes to wait for.
Uint8List encodeFrame(Frame frame) {
  final Uint8List payload;
  final int kind;
  switch (frame) {
    case ControlFrame():
      payload = utf8.encode(jsonEncode(frame.json));
      kind = FrameKind.control.code;
    case ChunkFrame():
      final idBytes = utf8.encode(frame.transferId);
      if (idBytes.length > 0xff) {
        throw ProtocolException(
          'transfer id is ${idBytes.length} bytes, limit is 255',
        );
      }
      final itemBytes = utf8.encode(frame.itemId);
      if (itemBytes.length > 0xff) {
        throw ProtocolException(
          'item id is ${itemBytes.length} bytes, limit is 255',
        );
      }
      final builder = BytesBuilder(copy: false)
        ..addByte(idBytes.length)
        ..add(idBytes)
        ..addByte(itemBytes.length)
        ..add(itemBytes)
        ..add(_uint64(frame.offset))
        ..add(frame.data);
      payload = builder.takeBytes();
      kind = FrameKind.chunk.code;
    case SealedFrame():
      if (frame.nonce.isEmpty) {
        throw const ProtocolException('a sealed frame needs a nonce');
      }
      payload =
          (BytesBuilder(copy: false)
                ..add(frame.nonce)
                ..add(frame.cipherText))
              .takeBytes();
      kind = FrameKind.sealed.code;
  }

  final total = 1 + payload.length;
  if (total > maxFrameBytes) {
    throw ProtocolException(
      'frame of $total bytes exceeds the $maxFrameBytes byte ceiling',
    );
  }

  final out = Uint8List(4 + total);
  final view = ByteData.sublistView(out);
  view.setUint32(0, total, Endian.big);
  out[4] = kind;
  out.setRange(5, out.length, payload);
  return out;
}

/// Incremental decoder turning arbitrary byte chunks into [Frame]s.
///
/// TCP delivers byte ranges, not messages, so every frame boundary has to be
/// reassembled by the reader. Instances are stateful and single-use.
///
/// A returned frame owns its bytes: [next] copies a frame's payload out of the
/// internal read buffer, so whatever the decoder does to that buffer afterwards
/// — appending, growing, compacting — cannot change a frame already handed out.
final class FrameDecoder {
  Uint8List _buffer = Uint8List(1024);
  int _start = 0;
  int _end = 0;

  /// Bytes appended so far that have not yet formed a complete frame.
  int get bufferedBytes => _end - _start;

  /// Appends bytes received from the peer.
  void add(List<int> bytes) {
    if (bytes.isEmpty) return;
    _ensureCapacity(bytes.length);
    _buffer.setRange(_end, _end + bytes.length, bytes);
    _end += bytes.length;
  }

  /// Returns the next complete frame, or `null` if more bytes are needed.
  Frame? next() {
    if (_end - _start < 4) return null;
    final length = ByteData.sublistView(
      _buffer,
      _start,
      _start + 4,
    ).getUint32(0, Endian.big);
    if (length < 1) {
      throw const ProtocolException('frame length must include a kind byte');
    }
    if (length > maxFrameBytes) {
      throw ProtocolException(
        'peer announced a $length byte frame, ceiling is $maxFrameBytes',
      );
    }
    if (_end - _start < 4 + length) return null;

    final kind = FrameKind.fromCode(_buffer[_start + 4]);
    // Copied out of the read buffer rather than viewed into it. The buffer is
    // reused: [add] appends at its end and [_compact] shifts the live tail
    // down over the bytes a frame just came from, so a frame holding a view
    // would have its own payload rewritten under it the moment the next frame
    // is decoded. That is not hypothetical — a 512 KiB record sharing one read
    // with the first bytes of the following frame came back with its nonce
    // overwritten and failed authentication for no visible reason.
    final payload = _buffer.sublist(_start + 5, _start + 4 + length);
    final frame = switch (kind) {
      FrameKind.control => _decodeControl(payload),
      FrameKind.chunk => _decodeChunk(payload),
      FrameKind.sealed => _decodeSealed(payload),
    };
    _start += 4 + length;
    _compact();
    return frame;
  }

  /// Fails if bytes remain that could never complete a frame.
  ///
  /// Call once the peer's stream has ended; a clean shutdown leaves no
  /// trailing bytes.
  void expectDrained() {
    if (bufferedBytes != 0) {
      throw ProtocolException(
        'stream ended with $bufferedBytes trailing byte(s); '
        'a frame was truncated',
      );
    }
  }

  static SealedFrame _decodeSealed(Uint8List payload) {
    const minimum = sealedNonceBytes + sealedTagBytes;
    if (payload.length < minimum) {
      throw ProtocolException(
        'sealed record of ${payload.length} bytes is shorter than the '
        '$minimum byte minimum',
      );
    }
    return SealedFrame(
      nonce: Uint8List.sublistView(payload, 0, sealedNonceBytes),
      cipherText: Uint8List.sublistView(payload, sealedNonceBytes),
    );
  }

  static ControlFrame _decodeControl(Uint8List payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(payload));
    } on FormatException catch (error) {
      throw ProtocolException('control payload is not valid JSON: $error');
    }
    if (decoded is! Map<String, Object?>) {
      throw ProtocolException('control payload must be a JSON object');
    }
    return ControlFrame(decoded);
  }

  static ChunkFrame _decodeChunk(Uint8List payload) {
    if (payload.isEmpty) {
      throw const ProtocolException('chunk payload is empty');
    }
    final transferIdLength = payload[0];
    var cursor = 1 + transferIdLength;
    if (payload.length <= cursor) {
      throw ProtocolException(
        'chunk payload of ${payload.length} bytes ends inside its transfer id',
      );
    }
    final itemIdLength = payload[cursor];
    final itemIdStart = cursor + 1;
    cursor = itemIdStart + itemIdLength;
    final headerLength = cursor + 8;
    if (payload.length < headerLength) {
      throw ProtocolException(
        'chunk payload of ${payload.length} bytes is shorter than its '
        '$headerLength byte header',
      );
    }
    return ChunkFrame(
      transferId: _utf8Id(payload.sublist(1, 1 + transferIdLength), 'id'),
      itemId: _utf8Id(payload.sublist(itemIdStart, cursor), 'item id'),
      offset: ByteData.sublistView(
        payload,
        cursor,
        headerLength,
      ).getUint64(0, Endian.big),
      data: Uint8List.sublistView(payload, headerLength),
    );
  }

  void _ensureCapacity(int extra) {
    if (_end + extra <= _buffer.length) return;
    var next = _buffer.length;
    while (next < _end + extra) {
      next *= 2;
    }
    final grown = Uint8List(next)..setRange(0, _end, _buffer);
    _buffer = grown;
  }

  void _compact() {
    if (_start == 0) return;
    if (_start == _end) {
      _start = 0;
      _end = 0;
      return;
    }
    // Only shift when the dead prefix is worth reclaiming, so a stream of
    // small frames does not memmove the live tail on every frame.
    if (_start >= 4096 || _start * 2 >= _buffer.length) {
      _buffer.setRange(0, _end - _start, _buffer, _start);
      _end -= _start;
      _start = 0;
    }
  }
}

/// Adapts a byte stream into a frame stream.
///
/// Ends with a [ProtocolException] if the source ends mid-frame, because a
/// truncated frame means the peer died or was tampered with — never a normal
/// end of conversation.
Stream<Frame> decodeFrames(Stream<List<int>> source) async* {
  final decoder = FrameDecoder();
  await for (final bytes in source) {
    decoder.add(bytes);
    for (var frame = decoder.next(); frame != null; frame = decoder.next()) {
      yield frame;
    }
  }
  decoder.expectDrained();
}

Uint8List _uint64(int value) {
  if (value < 0) {
    throw ProtocolException('chunk offset must not be negative: $value');
  }
  final bytes = Uint8List(8);
  ByteData.sublistView(bytes).setUint64(0, value, Endian.big);
  return bytes;
}

/// Decodes a length-prefixed identifier, reporting bad UTF-8 as a protocol
/// error rather than letting a decoder-level [FormatException] escape.
String _utf8Id(Uint8List bytes, String what) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw ProtocolException('the chunk $what is not valid UTF-8');
  }
}

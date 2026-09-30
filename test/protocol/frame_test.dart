import 'dart:convert';
import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('control frames', () {
    test('round-trip through the wire form', () {
      final frame = ControlFrame({'t': 'ping', 'n': 7});
      final decoded = FrameDecoder()..add(encodeFrame(frame));
      final result = decoded.next();
      expect(result, isA<ControlFrame>());
      expect((result! as ControlFrame).json, {'t': 'ping', 'n': 7});
      decoded.expectDrained();
    });

    test('reassemble correctly across every split point', () {
      final encoded = encodeFrame(
        ControlFrame({'t': 'offer', 'text': 'héllo'}),
      );
      for (var split = 0; split <= encoded.length; split++) {
        final decoder = FrameDecoder()
          ..add(encoded.sublist(0, split))
          ..add(encoded.sublist(split));
        final frame = decoder.next();
        expect(
          frame,
          isA<ControlFrame>(),
          reason: 'split at $split should still decode',
        );
        expect((frame! as ControlFrame).json['text'], 'héllo');
        expect(decoder.bufferedBytes, 0);
      }
    });

    test('decode several frames delivered in one read', () {
      final decoder = FrameDecoder()
        ..add(encodeFrame(ControlFrame({'t': 'a'})))
        ..add(encodeFrame(ControlFrame({'t': 'b'})))
        ..add(encodeFrame(ControlFrame({'t': 'c'})));
      final types = <String>[];
      for (var frame = decoder.next(); frame != null; frame = decoder.next()) {
        types.add((frame as ControlFrame).json['t']! as String);
      }
      expect(types, ['a', 'b', 'c']);
    });

    test('rejects a control payload that is not a JSON object', () {
      final payload = utf8.encode('[1,2,3]');
      final frame = Uint8List(4 + 1 + payload.length);
      ByteData.sublistView(frame).setUint32(0, 1 + payload.length, Endian.big);
      frame[4] = FrameKind.control.code;
      frame.setRange(5, frame.length, payload);
      final decoder = FrameDecoder()..add(frame);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });

    test('rejects a control payload that is not JSON at all', () {
      final payload = utf8.encode('not json');
      final frame = Uint8List(4 + 1 + payload.length);
      ByteData.sublistView(frame).setUint32(0, 1 + payload.length, Endian.big);
      frame[4] = FrameKind.control.code;
      frame.setRange(5, frame.length, payload);
      final decoder = FrameDecoder()..add(frame);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });
  });

  group('chunk frames', () {
    test('round-trip carries id, item, offset and bytes intact', () {
      final frame = ChunkFrame(
        transferId: 't-1',
        itemId: 'item-7',
        offset: 4096,
        data: _bytes([0, 1, 2, 250, 255]),
      );
      final decoder = FrameDecoder()..add(encodeFrame(frame));
      final result = decoder.next()! as ChunkFrame;
      expect(result.transferId, 't-1');
      expect(result.itemId, 'item-7');
      expect(result.offset, 4096);
      expect(result.data, [0, 1, 2, 250, 255]);
    });

    test('keeps two items of one transfer apart', () {
      final first = ChunkFrame(
        transferId: 't-9',
        itemId: 'a',
        offset: 0,
        data: _bytes([1]),
      );
      final second = ChunkFrame(
        transferId: 't-9',
        itemId: 'b',
        offset: 0,
        data: _bytes([2]),
      );
      final decoder = FrameDecoder()
        ..add(encodeFrame(first))
        ..add(encodeFrame(second));
      expect((decoder.next()! as ChunkFrame).itemId, 'a');
      expect((decoder.next()! as ChunkFrame).itemId, 'b');
    });

    test('round-trips a large offset without truncation', () {
      final frame = ChunkFrame(
        transferId: 'big',
        itemId: 'i',
        offset: 0x1FFFFFFFF,
        data: _bytes([9]),
      );
      final decoder = FrameDecoder()..add(encodeFrame(frame));
      expect((decoder.next()! as ChunkFrame).offset, 0x1FFFFFFFF);
    });

    test('refuses a negative offset', () {
      expect(
        () => encodeFrame(
          ChunkFrame(
            transferId: 't',
            itemId: 'i',
            offset: -1,
            data: _bytes([1]),
          ),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('refuses a transfer id too long for its length byte', () {
      expect(
        () => encodeFrame(
          ChunkFrame(
            transferId: 'x' * 256,
            itemId: 'i',
            offset: 0,
            data: _bytes([1]),
          ),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('refuses an item id too long for its length byte', () {
      expect(
        () => encodeFrame(
          ChunkFrame(
            transferId: 't',
            itemId: 'y' * 256,
            offset: 0,
            data: _bytes([1]),
          ),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects a payload shorter than its own header claims', () {
      final payload = _bytes([9, 0x61, 0x62]); // claims 9 id bytes, has 2
      final frame = Uint8List(4 + 1 + payload.length);
      ByteData.sublistView(frame).setUint32(0, 1 + payload.length, Endian.big);
      frame[4] = FrameKind.chunk.code;
      frame.setRange(5, frame.length, payload);
      final decoder = FrameDecoder()..add(frame);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });

    test('rejects a payload that ends before its item id byte', () {
      // one id byte ("t"), then nothing where the item id length belongs.
      final payload = _bytes([1, 0x74]);
      final frame = Uint8List(4 + 1 + payload.length);
      ByteData.sublistView(frame).setUint32(0, 1 + payload.length, Endian.big);
      frame[4] = FrameKind.chunk.code;
      frame.setRange(5, frame.length, payload);
      final decoder = FrameDecoder()..add(frame);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });

    test('reports an id that is not UTF-8 as a protocol error', () {
      // A well-formed header whose item id byte is a lone 0xff, which is not
      // valid UTF-8: transferId "t", item id 0xff, offset 0, one data byte.
      final payload = _bytes([
        1, 0x74, // transfer id: 1 byte, 't'
        1, 0xff, // item id: 1 byte, invalid UTF-8
        0, 0, 0, 0, 0, 0, 0, 0, // offset
        0x07, // data
      ]);
      final frame = Uint8List(4 + 1 + payload.length);
      ByteData.sublistView(frame).setUint32(0, 1 + payload.length, Endian.big);
      frame[4] = FrameKind.chunk.code;
      frame.setRange(5, frame.length, payload);
      final decoder = FrameDecoder()..add(frame);
      expect(
        decoder.next,
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
    });
  });

  group('sealed frames', () {
    test('round-trip preserves nonce and ciphertext', () {
      final frame = SealedFrame(
        nonce: _bytes(List.generate(12, (i) => i)),
        cipherText: _bytes(List.generate(40, (i) => 255 - i)),
      );
      final decoder = FrameDecoder()..add(encodeFrame(frame));
      final result = decoder.next()! as SealedFrame;
      expect(result.nonce, List.generate(12, (i) => i));
      expect(result.cipherText, List.generate(40, (i) => 255 - i));
    });

    test('rejects a record too short to hold a tag', () {
      final payload = _bytes(List.generate(20, (i) => i));
      final frame = Uint8List(4 + 1 + payload.length);
      ByteData.sublistView(frame).setUint32(0, 1 + payload.length, Endian.big);
      frame[4] = FrameKind.sealed.code;
      frame.setRange(5, frame.length, payload);
      final decoder = FrameDecoder()..add(frame);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });
  });

  group('decoder buffer reuse', () {
    // Regression: next() used to hand out payloads that were views into the
    // decoder's own read buffer, which _compact() then rewrote in place once a
    // frame was long enough to make the dead prefix worth reclaiming. A large
    // record that shared one read with the following frame came back with its
    // leading bytes overwritten, so it failed authentication for no reason a
    // reader of the ciphertext could see.
    test('a large sealed frame survives the next frame being buffered', () {
      final nonce = _bytes(List.generate(12, (i) => i + 1));
      final cipherText = _bytes(List.generate(512 * 1024, (i) => i % 251));
      final following = encodeFrame(
        ControlFrame({'t': 'after', 'pad': 'x' * 120}),
      );

      final decoder = FrameDecoder()
        ..add(encodeFrame(SealedFrame(nonce: nonce, cipherText: cipherText)))
        // Enough of the next frame that compaction has bytes to shift, which
        // is what used to land on top of the frame decoded just before it.
        ..add(following.sublist(0, 64));

      final frame = decoder.next()! as SealedFrame;
      expect(frame.nonce, nonce);
      expect(frame.cipherText, cipherText);
    });

    test('a large chunk frame survives the next frame being buffered', () {
      final data = _bytes(List.generate(512 * 1024, (i) => i % 251));
      final following = encodeFrame(
        ControlFrame({'t': 'after', 'pad': 'x' * 120}),
      );

      final decoder = FrameDecoder()
        ..add(
          encodeFrame(
            ChunkFrame(transferId: 't', itemId: 'i', offset: 0, data: data),
          ),
        )
        ..add(following.sublist(0, 64));

      final frame = decoder.next()! as ChunkFrame;
      expect(frame.data, data);
    });
  });

  group('decoder limits', () {
    test('rejects a length that exceeds the ceiling before allocating', () {
      final header = Uint8List(4);
      ByteData.sublistView(header).setUint32(0, maxFrameBytes + 1, Endian.big);
      final decoder = FrameDecoder()..add(header);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });

    test('rejects an unknown frame kind', () {
      final frame = _bytes([0, 0, 0, 1, 0x7f]);
      final decoder = FrameDecoder()..add(frame);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });

    test('rejects a zero length frame', () {
      final frame = _bytes([0, 0, 0, 0]);
      final decoder = FrameDecoder()..add(frame);
      expect(decoder.next, throwsA(isA<ProtocolException>()));
    });

    test('reports a truncated frame rather than silently ending', () {
      final decoder = FrameDecoder()
        ..add(encodeFrame(ControlFrame({'t': 'x'})).sublist(0, 6));
      expect(decoder.next(), isNull);
      expect(decoder.expectDrained, throwsA(isA<ProtocolException>()));
    });

    test('a clean stream drains with nothing left over', () {
      final decoder = FrameDecoder()
        ..add(encodeFrame(ControlFrame({'t': 'x'})));
      expect(decoder.next(), isNotNull);
      expect(decoder.expectDrained, returnsNormally);
    });
  });

  group('decodeFrames', () {
    test(
      'surfaces a ProtocolException when the source ends mid-frame',
      () async {
        final encoded = encodeFrame(ControlFrame({'t': 'x', 'pad': 'y' * 40}));
        final stream = Stream<List<int>>.fromIterable([encoded.sublist(0, 9)]);
        await expectLater(
          decodeFrames(stream).toList(),
          throwsA(isA<ProtocolException>()),
        );
      },
    );

    test('yields every frame from a byte stream', () async {
      final stream = Stream<List<int>>.fromIterable([
        encodeFrame(ControlFrame({'t': 'one'})),
        ...encodeFrame(
          ChunkFrame(
            transferId: 't',
            itemId: 'i',
            offset: 0,
            data: _bytes([7]),
          ),
        ).splitEvery(3),
      ]);
      final frames = await decodeFrames(stream).toList();
      expect(frames, hasLength(2));
      expect((frames[0] as ControlFrame).json['t'], 'one');
      expect((frames[1] as ChunkFrame).data, [7]);
    });
  });
}

extension on Uint8List {
  List<List<int>> splitEvery(int size) {
    final out = <List<int>>[];
    for (var i = 0; i < length; i += size) {
      out.add(sublist(i, i + size > length ? length : i + size));
    }
    return out;
  }
}

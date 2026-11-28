import 'dart:async';
import 'dart:convert';

import 'package:local_transfer/core/ai/protocol/sse_parser.dart';
import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

Stream<List<int>> _bytes(String text) => Stream.value(utf8.encode(text));

void main() {
  group('parseSse', () {
    test('yields one event per blank-line-separated frame', () async {
      final events = await parseSse(
        _bytes('data: {"a":1}\n\ndata: {"b":2}\n\n'),
      ).toList();
      expect(events, hasLength(2));
      expect(events[0].data, '{"a":1}');
      expect(events[1].data, '{"b":2}');
    });

    test('joins multi-line data fields with newlines', () async {
      final events = await parseSse(
        _bytes('data: line one\ndata: line two\n\n'),
      ).toList();
      expect(events.single.data, 'line one\nline two');
    });

    test('captures the event name and skips comments', () async {
      final events = await parseSse(
        _bytes(': keep-alive\nevent: message_delta\ndata: {}\n\n'),
      ).toList();
      expect(events.single.event, 'message_delta');
    });

    test('a multi-byte character split across chunks survives', () async {
      // 'é' is two bytes in UTF-8; splitting inside it must not corrupt.
      final bytes = utf8.encode('data: caf\u00e9\n\n');
      final split = bytes.indexOf(0xC3); // first byte of é
      final events = await parseSse(
        Stream.fromIterable([
          bytes.sublist(0, split + 1),
          bytes.sublist(split + 1),
        ]),
      ).toList();
      expect(events.single.data, 'café');
    });

    test('a trailing frame without a blank line is still yielded', () async {
      final events = await parseSse(_bytes('data: tail')).toList();
      expect(events.single.data, 'tail');
    });
  });

  group('AiModelRef', () {
    test('parses provider/model', () {
      final ref = AiModelRef.parse('deepseek/deepseek-chat')!;
      expect(ref.isGroup, isFalse);
      expect(ref.providerId, 'deepseek');
      expect(ref.modelId, 'deepseek-chat');
    });

    test('parses group/<id>', () {
      final ref = AiModelRef.parse('group/main')!;
      expect(ref.isGroup, isTrue);
      expect(ref.groupId, 'main');
    });

    test('rejects malformed references', () {
      expect(AiModelRef.parse(''), isNull);
      expect(AiModelRef.parse('noseparator'), isNull);
      expect(AiModelRef.parse('/model'), isNull);
      expect(AiModelRef.parse('provider/'), isNull);
      expect(AiModelRef.parse('group/'), isNull);
    });

    test('model ids may contain slashes after the first', () {
      final ref = AiModelRef.parse('openrouter/qwen/qwen3-32b')!;
      expect(ref.providerId, 'openrouter');
      expect(ref.modelId, 'qwen/qwen3-32b');
    });
  });
}

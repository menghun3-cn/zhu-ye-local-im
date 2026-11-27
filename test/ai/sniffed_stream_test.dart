import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

/// `sniffedDecodeStream` guards the router's stream path against providers
/// that accept `stream: true` but answer with one JSON document — without
/// it those replies decoded to zero frames and surfaced as empty 200s.
void main() {
  const codec = OpenAiChatCodec();

  Stream<List<int>> bytes(String text) => Stream.fromIterable([
    for (final c in text.codeUnits) [c],
  ]);

  Stream<List<int>> chunks(List<String> parts) =>
      Stream.fromIterable([for (final p in parts) utf8.encode(p)]);

  test('a real SSE body streams through untouched', () async {
    final events = await sniffedDecodeStream(
      codec,
      bytes(
        'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n'
        'data: {"usage":{"prompt_tokens":1,"completion_tokens":2,'
        '"total_tokens":3}}\n\n'
        'data: [DONE]\n\n',
      ),
    ).toList();
    expect(
      [for (final e in events) e.kind],
      [
        AiStreamKind.textDelta,
        AiStreamKind.textDelta,
        AiStreamKind.usage,
        AiStreamKind.done,
      ],
    );
    expect(events[0].text, 'Hel');
    expect(events[2].usage?.totalTokens, 3);
  });

  test('SSE split across tiny chunks still decodes', () async {
    final sse =
        'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
        'data: [DONE]\n\n';
    // One byte per chunk forces the sniffer to re-check the head often.
    final events = await sniffedDecodeStream(codec, bytes(sse)).toList();
    expect(events.first.kind, AiStreamKind.textDelta);
    expect(events.first.text, 'ok');
    expect(events.last.kind, AiStreamKind.done);
  });

  test('a JSON body is folded into stream events', () async {
    final events = await sniffedDecodeStream(
      codec,
      bytes(
        '{"choices":[{"message":{"role":"assistant","content":"whole"}}],'
        '"usage":{"prompt_tokens":4,"completion_tokens":1,'
        '"total_tokens":5}}',
      ),
    ).toList();
    expect(events.first.kind, AiStreamKind.textDelta);
    expect(events.first.text, 'whole');
    expect(events[1].kind, AiStreamKind.usage);
    expect(events[1].usage?.totalTokens, 5);
    expect(events.last.kind, AiStreamKind.done);
  });

  test('a body that is neither SSE nor JSON reports an error', () async {
    final events = await sniffedDecodeStream(
      codec,
      bytes('<html>bad gateway</html>'),
    ).toList();
    expect(events.first.kind, AiStreamKind.error);
    expect(events.last.kind, AiStreamKind.done);
  });

  test('an empty body reports an error rather than a blank success', () async {
    final events = await sniffedDecodeStream(codec, bytes('')).toList();
    expect(events.first.kind, AiStreamKind.error);
  });

  test('a document split across chunks still folds', () async {
    final events = await sniffedDecodeStream(
      codec,
      chunks(['{"choices":[{"message":{"content":"par', 'tial"}}]}']),
    ).toList();
    expect(events.first.text, 'partial');
    expect(events.last.kind, AiStreamKind.done);
  });
}

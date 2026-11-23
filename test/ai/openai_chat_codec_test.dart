import 'dart:async';
import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

const codec = OpenAiChatCodec();

AiChatRequest _request({bool stream = false}) => AiChatRequest(
  model: 'deepseek/deepseek-chat',
  stream: stream,
  temperature: 0.5,
  messages: const [
    AiMessage(role: AiRole.system, content: 'be brief'),
    AiMessage(role: AiRole.user, content: 'hello'),
    AiMessage(
      role: AiRole.assistant,
      toolCalls: [
        AiToolCall(id: 'call_1', name: 'lookup', arguments: '{"q":"x"}'),
      ],
    ),
    AiMessage(
      role: AiRole.tool,
      toolCallId: 'call_1',
      name: 'lookup',
      content: '42',
    ),
  ],
);

void main() {
  group('OpenAiChatCodec.encodeChat', () {
    test('builds the chat/completions request with auth and params', () {
      final spec = codec.encodeChat(
        _request(),
        baseUrl: 'https://api.deepseek.com/v1/',
        model: 'deepseek-chat',
        apiKey: 'sk-test',
      );
      expect(spec.method, 'POST');
      expect(spec.url, 'https://api.deepseek.com/v1/chat/completions');
      expect(spec.headers['authorization'], 'Bearer sk-test');
      final body = jsonDecode(spec.body!) as Map<String, Object?>;
      expect(body['model'], 'deepseek-chat');
      expect(body['stream'], isFalse);
      expect(body['temperature'], 0.5);
      final messages = body['messages'] as List;
      expect(messages, hasLength(4));
      expect((messages[2] as Map)['tool_calls'], isNotNull);
      expect((messages[3] as Map)['tool_call_id'], 'call_1');
    });

    test('streaming requests ask for usage in the final chunk', () {
      final spec = codec.encodeChat(
        _request(stream: true),
        baseUrl: 'https://api.x.ai/v1',
        model: 'grok-4',
      );
      final body = jsonDecode(spec.body!) as Map<String, Object?>;
      expect(body['stream'], isTrue);
      expect(body['stream_options'], {'include_usage': true});
      expect(spec.headers.containsKey('authorization'), isFalse);
    });
  });

  group('OpenAiChatCodec.decodeResponse', () {
    test('reads content, tool calls and usage', () {
      final reply = codec.decodeResponse(
        '{"choices":[{"message":{"role":"assistant","content":"hi",'
        '"tool_calls":[{"id":"c1","type":"function","function":'
        '{"name":"f","arguments":"{\\"a\\":1}"}}]}}],'
        '"usage":{"prompt_tokens":3,"completion_tokens":5,"total_tokens":8}}',
      );
      expect(reply.content, 'hi');
      expect(reply.toolCalls.single.name, 'f');
      expect(reply.toolCalls.single.arguments, '{"a":1}');
      expect(reply.usage.totalTokens, 8);
    });
  });

  group('OpenAiChatCodec.decodeStream', () {
    test('assembles deltas, usage and done', () async {
      final sse =
          'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n'
          'data: {"choices":[],"usage":{"prompt_tokens":1,'
          '"completion_tokens":2,"total_tokens":3}}\n\n'
          'data: [DONE]\n\n';
      final events = await codec
          .decodeStream(Stream.value(utf8.encode(sse)))
          .toList();
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
      expect(events[1].text, 'lo');
      expect(events[2].usage?.totalTokens, 3);
    });
  });

  group('OpenAiChatCodec.classifyError', () {
    test('429 and 5xx are retryable, 401 is fatal', () {
      expect(codec.classifyError(429, ''), AiErrorKind.retryable);
      expect(codec.classifyError(503, ''), AiErrorKind.retryable);
      expect(codec.classifyError(401, ''), AiErrorKind.fatal);
      expect(
        codec.classifyError(400, '{"error":{"message":"insufficient_quota"}}'),
        AiErrorKind.retryable,
      );
    });
  });

  group('OpenAiChatCodec.decodeModels', () {
    test('reads data[].id', () {
      expect(codec.decodeModels('{"data":[{"id":"a"},{"id":"b"}]}'), [
        'a',
        'b',
      ]);
    });
  });
}

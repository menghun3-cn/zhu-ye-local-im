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

    test(
      'reassembles fragmented tool_calls into one call before done',
      () async {
        final sse =
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
            '"id":"call_9","type":"function","function":{"name":"lookup",'
            '"arguments":"{\\"ci"}}]}}]}\n\n'
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
            '"function":{"arguments":"ty\\":\\"par"}}]}}]}\n\n'
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
            '"function":{"arguments":"is\\"}"}}]}}]}\n\n'
            'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n'
            'data: [DONE]\n\n';
        final events = await codec
            .decodeStream(Stream.value(utf8.encode(sse)))
            .toList();
        final calls = [
          for (final e in events)
            if (e.kind == AiStreamKind.toolCall) e.toolCall!,
        ];
        expect(calls, hasLength(1));
        expect(calls.single.id, 'call_9');
        expect(calls.single.name, 'lookup');
        expect(calls.single.arguments, '{"city":"paris"}');
        expect(events.last.kind, AiStreamKind.done);
      },
    );
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

  group('OpenAiChatCodec.decodeModelCatalog', () {
    test('plain ids carry no metadata', () {
      final catalog = codec.decodeModelCatalog(
        '{"data":[{"id":"a"},{"id":"b"}]}',
      );
      expect(catalog.map((m) => m.id), ['a', 'b']);
      expect(catalog.first.contextTokens, isNull);
      expect(catalog.first.isFree, isNull);
      expect(catalog.first.label, isNull);
    });

    test('OpenRouter shape reads context and pricing', () {
      final catalog = codec.decodeModelCatalog('''
        {"data":[
          {"id":"free/m","name":"Free Model","context_length":256000,
           "pricing":{"prompt":"0","completion":"0"}},
          {"id":"paid/m","context_length":1000000,
           "pricing":{"prompt":"0.000004","completion":"0.00002"}},
          {"id":"auto/m","context_length":1000000,
           "pricing":{"prompt":"-1","completion":"-1"}}
        ]}
      ''');
      expect(catalog[0].id, 'free/m');
      expect(catalog[0].label, 'Free Model');
      expect(catalog[0].contextTokens, 256000);
      expect(catalog[0].isFree, isTrue);
      expect(catalog[1].isFree, isFalse);
      expect(catalog[1].contextTokens, 1000000);
      // "-1" prices mean "varies" — unknown, not paid.
      expect(catalog[2].isFree, isNull);
    });

    test('Zen shape reads limit.context and cost prices', () {
      final catalog = codec.decodeModelCatalog('''
        {"data":[
          {"id":"big-pickle","name":"Big Pickle",
           "limit":{"context":200000,"input":160000,"output":32000},
           "cost":{"text":{"input":{"price":0},"output":{"price":0}}}}
        ]}
      ''');
      expect(catalog.single.id, 'big-pickle');
      expect(catalog.single.label, 'Big Pickle');
      expect(catalog.single.contextTokens, 200000);
      expect(catalog.single.isFree, isTrue);
    });
  });
}

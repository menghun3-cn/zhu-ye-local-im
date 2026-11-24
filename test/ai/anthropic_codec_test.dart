import 'dart:async';
import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

const codec = AnthropicCodec();

AiChatRequest _request({bool stream = false}) => AiChatRequest(
  model: 'anthropic/claude-opus-4-6',
  stream: stream,
  messages: const [
    AiMessage(role: AiRole.system, content: 'be brief'),
    AiMessage(role: AiRole.user, content: 'hello'),
  ],
);

void main() {
  group('AnthropicCodec.encodeChat', () {
    test('lifts system out, requires max_tokens, uses x-api-key', () {
      final spec = codec.encodeChat(
        _request(),
        baseUrl: 'https://api.anthropic.com',
        model: 'claude-opus-4-6',
        apiKey: 'sk-ant',
      );
      expect(spec.url, 'https://api.anthropic.com/v1/messages');
      expect(spec.headers['x-api-key'], 'sk-ant');
      expect(spec.headers['anthropic-version'], isNotNull);
      final body = jsonDecode(spec.body!) as Map<String, Object?>;
      expect(body['system'], 'be brief');
      expect(body['max_tokens'], AnthropicCodec.defaultMaxTokens);
      final messages = body['messages'] as List;
      expect(messages, hasLength(1)); // system was lifted out
      expect((messages[0] as Map)['role'], 'user');
    });

    test('honours an explicit maxTokens', () {
      final spec = codec.encodeChat(
        AiChatRequest(
          model: 'a/b',
          maxTokens: 100,
          messages: const [AiMessage(role: AiRole.user, content: 'hi')],
        ),
        baseUrl: 'https://api.anthropic.com',
        model: 'm',
      );
      final body = jsonDecode(spec.body!) as Map<String, Object?>;
      expect(body['max_tokens'], 100);
    });

    test('tool results become user turns with tool_result blocks', () {
      final spec = codec.encodeChat(
        AiChatRequest(
          model: 'a/b',
          messages: const [
            AiMessage(role: AiRole.user, content: 'go'),
            AiMessage(
              role: AiRole.assistant,
              toolCalls: [
                AiToolCall(id: 't1', name: 'f', arguments: '{"x":1}'),
              ],
            ),
            AiMessage(
              role: AiRole.tool,
              toolCallId: 't1',
              name: 'f',
              content: 'done',
            ),
          ],
        ),
        baseUrl: 'https://api.anthropic.com',
        model: 'm',
      );
      final body = jsonDecode(spec.body!) as Map<String, Object?>;
      final messages = body['messages'] as List;
      expect(messages, hasLength(3));
      final assistant = (messages[1] as Map)['content'] as List;
      expect((assistant[0] as Map)['type'], 'tool_use');
      final toolTurn = (messages[2] as Map)['content'] as List;
      final block = toolTurn[0] as Map;
      expect(block['type'], 'tool_result');
      expect(block['tool_use_id'], 't1');
    });
  });

  group('AnthropicCodec.decodeResponse', () {
    test('reads text blocks, tool_use blocks and usage', () {
      final reply = codec.decodeResponse(
        '{"content":[{"type":"text","text":"hi"},'
        '{"type":"tool_use","id":"t1","name":"f","input":{"x":1}}],'
        '"usage":{"input_tokens":10,"output_tokens":4}}',
      );
      expect(reply.content, 'hi');
      expect(reply.toolCalls.single.id, 't1');
      expect(reply.toolCalls.single.arguments, contains('"x"'));
      expect(reply.usage.promptTokens, 10);
      expect(reply.usage.completionTokens, 4);
    });
  });

  group('AnthropicCodec.decodeStream', () {
    test('reassembles text deltas and a tool call across block events', () async {
      final sse =
          'event: content_block_start\n'
          'data: {"type":"content_block_start","index":0,'
          '"content_block":{"type":"tool_use","id":"t1","name":"f"}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,'
          '"delta":{"type":"input_json_delta","partial_json":"{\\"x\\":"}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,'
          '"delta":{"type":"input_json_delta","partial_json":"1}"}}\n\n'
          'event: content_block_stop\n'
          'data: {"type":"content_block_stop","index":0}\n\n'
          'event: message_delta\n'
          'data: {"type":"message_delta","usage":{"output_tokens":7}}\n\n'
          'event: message_stop\n'
          'data: {"type":"message_stop"}\n\n';
      final events = await codec
          .decodeStream(Stream.value(utf8.encode(sse)))
          .toList();
      final call = events
          .where((e) => e.kind == AiStreamKind.toolCall)
          .single
          .toolCall!;
      expect(call.id, 't1');
      expect(call.name, 'f');
      expect(call.arguments, '{"x":1}');
      expect(events.last.kind, AiStreamKind.done);
      expect(
        events
            .firstWhere((e) => e.kind == AiStreamKind.usage)
            .usage
            ?.completionTokens,
        7,
      );
    });

    test('streams plain text deltas', () async {
      final sse =
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,'
          '"delta":{"type":"text_delta","text":"hello"}}\n\n'
          'event: message_stop\ndata: {}\n\n';
      final events = await codec
          .decodeStream(Stream.value(utf8.encode(sse)))
          .toList();
      expect(events.first.text, 'hello');
      expect(events.last.kind, AiStreamKind.done);
    });
  });

  group('AnthropicCodec.classifyError', () {
    test('error.type drives classification', () {
      expect(
        codec.classifyError(400, '{"error":{"type":"overloaded_error"}}'),
        AiErrorKind.retryable,
      );
      expect(
        codec.classifyError(400, '{"error":{"type":"authentication_error"}}'),
        AiErrorKind.fatal,
      );
      expect(codec.classifyError(529, ''), AiErrorKind.retryable);
    });
  });

  group('AnthropicCodec.decodeModelCatalog', () {
    test('reads ids and display_name, metadata stays unknown', () {
      final catalog = codec.decodeModelCatalog(
        '{"data":[{"id":"claude-opus-4-6","display_name":"Claude Opus"}]}',
      );
      expect(catalog.single.id, 'claude-opus-4-6');
      expect(catalog.single.label, 'Claude Opus');
      expect(catalog.single.contextTokens, isNull);
      expect(catalog.single.isFree, isNull);
    });
  });
}

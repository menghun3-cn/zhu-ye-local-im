import 'dart:async';
import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

const codec = OpenAiResponsesCodec();

void main() {
  group('OpenAiResponsesCodec.encodeChat', () {
    test('builds typed input items including function_call_output', () {
      final spec = codec.encodeChat(
        AiChatRequest(
          model: 'openai/gpt-5',
          messages: const [
            AiMessage(role: AiRole.system, content: 'sys'),
            AiMessage(role: AiRole.user, content: 'hi'),
            AiMessage(
              role: AiRole.assistant,
              toolCalls: [AiToolCall(id: 'c1', name: 'f', arguments: '{}')],
            ),
            AiMessage(
              role: AiRole.tool,
              toolCallId: 'c1',
              name: 'f',
              content: 'result',
            ),
          ],
        ),
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5',
        apiKey: 'sk-oai',
      );
      expect(spec.url, 'https://api.openai.com/v1/responses');
      final body = jsonDecode(spec.body!) as Map<String, Object?>;
      final input = body['input'] as List;
      // system message + user message + function_call + function_call_output
      expect(input, hasLength(4));
      expect((input[2] as Map)['type'], 'function_call');
      expect((input[3] as Map)['type'], 'function_call_output');
      expect((input[3] as Map)['call_id'], 'c1');
    });
  });

  group('OpenAiResponsesCodec.decodeResponse', () {
    test('reads output message text, function calls and usage', () {
      final reply = codec.decodeResponse(
        '{"output":['
        '{"type":"message","content":[{"type":"output_text","text":"hi"}]},'
        '{"type":"function_call","call_id":"c9","name":"f",'
        '"arguments":"{\\"a\\":2}"}],'
        '"usage":{"input_tokens":3,"output_tokens":4,"total_tokens":7}}',
      );
      expect(reply.content, 'hi');
      expect(reply.toolCalls.single.id, 'c9');
      expect(reply.usage.totalTokens, 7);
    });
  });

  group('OpenAiResponsesCodec.decodeStream', () {
    test('handles output_text.delta and response.completed', () async {
      final sse =
          'event: response.output_text.delta\n'
          'data: {"type":"response.output_text.delta","delta":"Hey"}\n\n'
          'event: response.completed\n'
          'data: {"type":"response.completed","response":'
          '{"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}\n\n';
      final events = await codec
          .decodeStream(Stream.value(utf8.encode(sse)))
          .toList();
      expect(events[0].text, 'Hey');
      expect(events[1].kind, AiStreamKind.usage);
      expect(events.last.kind, AiStreamKind.done);
    });

    test('response.failed surfaces an error event', () async {
      final sse =
          'event: response.failed\n'
          'data: {"type":"response.failed","response":'
          '{"error":{"message":"boom"}}}\n\n';
      final events = await codec
          .decodeStream(Stream.value(utf8.encode(sse)))
          .toList();
      expect(events.first.kind, AiStreamKind.error);
      expect(events.first.text, 'boom');
    });
  });

  group('OpenAiResponsesCodec.classifyError', () {
    test('insufficient_quota retries', () {
      expect(
        codec.classifyError(
          400,
          '{"error":{"type":"insufficient_quota","code":"insufficient_quota"}}',
        ),
        AiErrorKind.retryable,
      );
      expect(codec.classifyError(401, ''), AiErrorKind.fatal);
    });
  });
}

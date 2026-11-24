import 'dart:async';
import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

const codec = GeminiCodec();

void main() {
  group('GeminiCodec.encodeChat', () {
    test('maps roles, systemInstruction and generationConfig', () {
      final spec = codec.encodeChat(
        AiChatRequest(
          model: 'google/gemini-2.5-pro',
          temperature: 0.2,
          maxTokens: 500,
          messages: const [
            AiMessage(role: AiRole.system, content: 'sys'),
            AiMessage(role: AiRole.user, content: 'hi'),
            AiMessage(role: AiRole.assistant, content: 'hello'),
          ],
        ),
        baseUrl: 'https://generativelanguage.googleapis.com',
        model: 'gemini-2.5-pro',
        apiKey: 'g-key',
      );
      expect(
        spec.url,
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.5-pro:generateContent',
      );
      expect(spec.headers['x-goog-api-key'], 'g-key');
      final body = jsonDecode(spec.body!) as Map<String, Object?>;
      expect(body['systemInstruction'], isNotNull);
      final contents = body['contents'] as List;
      expect(contents, hasLength(2));
      expect((contents[0] as Map)['role'], 'user');
      expect((contents[1] as Map)['role'], 'model');
      final config = body['generationConfig'] as Map;
      expect(config['maxOutputTokens'], 500);
    });

    test('streaming uses streamGenerateContent with alt=sse', () {
      final spec = codec.encodeChat(
        AiChatRequest(
          model: 'g/m',
          stream: true,
          messages: const [AiMessage(role: AiRole.user, content: 'hi')],
        ),
        baseUrl: 'https://generativelanguage.googleapis.com',
        model: 'gemini-2.5-flash',
      );
      expect(spec.url, contains(':streamGenerateContent?alt=sse'));
    });
  });

  group('GeminiCodec.decodeResponse', () {
    test('reads candidates text and usageMetadata', () {
      final reply = codec.decodeResponse(
        '{"candidates":[{"content":{"role":"model","parts":'
        '[{"text":"hi"},{"text":" there"}]},"finishReason":"STOP"}],'
        '"usageMetadata":{"promptTokenCount":4,'
        '"candidatesTokenCount":2,"totalTokenCount":6}}',
      );
      expect(reply.content, 'hi there');
      expect(reply.usage.totalTokens, 6);
    });
  });

  group('GeminiCodec.decodeStream', () {
    test('concatenates chunk text and emits usage', () async {
      final sse =
          'data: {"candidates":[{"content":{"parts":'
          '[{"text":"Hel"}]}}]}\n\n'
          'data: {"candidates":[{"content":{"parts":'
          '[{"text":"lo"}]}}],"usageMetadata":'
          '{"promptTokenCount":1,"candidatesTokenCount":2,'
          '"totalTokenCount":3}}\n\n';
      final events = await codec
          .decodeStream(Stream.value(utf8.encode(sse)))
          .toList();
      expect(events[0].text, 'Hel');
      expect(events[1].text, 'lo');
      expect(events[2].kind, AiStreamKind.usage);
      expect(events.last.kind, AiStreamKind.done);
    });
  });

  group('GeminiCodec.classifyError', () {
    test('RESOURCE_EXHAUSTED retries, UNAUTHENTICATED is fatal', () {
      expect(
        codec.classifyError(429, '{"error":{"status":"RESOURCE_EXHAUSTED"}}'),
        AiErrorKind.retryable,
      );
      expect(
        codec.classifyError(403, '{"error":{"status":"PERMISSION_DENIED"}}'),
        AiErrorKind.fatal,
      );
    });
  });

  group('GeminiCodec.decodeModels', () {
    test('strips the models/ prefix', () {
      expect(
        codec.decodeModels(
          '{"models":[{"name":"models/gemini-2.5-pro"},'
          '{"name":"models/gemini-2.5-flash"}]}',
        ),
        ['gemini-2.5-pro', 'gemini-2.5-flash'],
      );
    });
  });

  group('GeminiCodec.decodeModelCatalog', () {
    test('sums input and output limits into the context window', () {
      final catalog = codec.decodeModelCatalog('''
        {"models":[
          {"name":"models/gemini-2.5-pro","displayName":"Gemini Pro",
           "inputTokenLimit":1000000,"outputTokenLimit":64000}
        ]}
      ''');
      expect(catalog.single.id, 'gemini-2.5-pro');
      expect(catalog.single.label, 'Gemini Pro');
      expect(catalog.single.contextTokens, 1064000);
      expect(catalog.single.isFree, isNull);
    });
  });
}

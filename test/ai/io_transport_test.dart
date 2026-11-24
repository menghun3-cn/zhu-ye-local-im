import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

/// Regression: `HttpClientRequest.write` encodes strings as latin1 unless
/// told otherwise, so any prompt with a non-latin1 character (every CJK
/// message) threw before a byte left the machine. The codec layer always
/// produces JSON, so the transport must send UTF-8 — this test runs a real
/// socket upstream and reads the bytes it actually received.
void main() {
  test('a non-latin1 prompt reaches the upstream as UTF-8 JSON', () async {
    String? received;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    upstream.listen((request) async {
      final body = await utf8.decodeStream(request);
      received = body;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '收到'},
              },
            ],
          }),
        );
      await request.response.close();
    });

    final secrets = SecretBox.withKey(List<int>.filled(32, 7));
    final store = AiConfigStore(store: MemoryMessageStore(), secrets: secrets);
    await store.save(
      AiConfig(
        providers: [
          AiProvider(
            id: 'local',
            name: 'Local',
            kind: AiProviderKind.custom,
            endpoints: {
              AiProtocol.openaiChat:
                  'http://${upstream.address.address}:${upstream.port}/v1',
            },
            apiKey: 'k',
            models: const [
              AiProviderModel(
                id: 'm1',
                protocol: AiProtocol.openaiChat,
                enabled: true,
              ),
            ],
          ),
        ],
      ),
    );
    // No transport override: this exercises IoAiTransport, the code that
    // had the latin1 bug.
    final router = AiRouter(store: store);

    final reply = await router.chat(
      AiChatRequest(
        model: 'local/m1',
        messages: const [AiMessage(role: AiRole.user, content: '你好，请说一句话')],
      ),
    );

    expect(reply.servedBy, 'local/m1');
    expect((reply as AiFullReply).response.content, '收到');
    // The upstream must have seen the characters intact — mojibake here
    // would mean the fix sent bytes but the wrong ones.
    final sent = jsonDecode(received!) as Map<String, Object?>;
    final messages = sent['messages'] as List<Object?>;
    final first = messages.first as Map<String, Object?>;
    expect(first['content'], '你好，请说一句话');
  });
}

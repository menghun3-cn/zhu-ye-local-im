import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

/// Same queue-answering fake as ai_router_test, kept local so this file
/// stands alone.
final class _FakeTransport implements AiTransport {
  final List<AiHttpResponse> queue = [];

  void pushJson(int status, Object? body) {
    queue.add(
      AiHttpResponse(
        statusCode: status,
        bodyBytes: Stream.value(
          utf8.encode(body is String ? body : jsonEncode(body)),
        ),
      ),
    );
  }

  void pushSse(List<String> frames) {
    queue.add(
      AiHttpResponse(
        statusCode: 200,
        bodyBytes: Stream.value(utf8.encode(frames.join('\n\n'))),
      ),
    );
  }

  @override
  Future<AiHttpResponse> send(AiRequestSpec request) async => queue.removeAt(0);
}

void main() {
  late Directory dir;
  late _FakeTransport transport;
  late AiRouter router;
  late AiRequestLog log;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ai-recording-test');
    transport = _FakeTransport();
    log = AiRequestLog(file: File('${dir.path}/requests.json'));
    final secrets = SecretBox.withKey(List<int>.filled(32, 7));
    final store = AiConfigStore(store: MemoryMessageStore(), secrets: secrets);
    await store.save(
      AiConfig(
        providers: [
          AiProvider(
            id: 'a',
            name: 'A',
            kind: AiProviderKind.custom,
            endpoints: const {AiProtocol.openaiChat: 'https://a.example/v1'},
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
    router = AiRouter(store: store, transport: transport, requestLog: log);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  AiChatRequest chat({bool stream = false}) => AiChatRequest(
    model: 'a/m1',
    stream: stream,
    messages: const [AiMessage(role: AiRole.user, content: 'hi')],
  );

  /// Recording is fire-and-forget file IO; give the event loop a beat.
  Future<List<AiRequestRecord>> settled() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final records = await log.load();
      if (records.isNotEmpty) return records;
    }
    return const [];
  }

  test('a non-streamed reply lands in the log with its usage', () async {
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'answer'},
        },
      ],
      'usage': {
        'prompt_tokens': 20,
        'completion_tokens': 5,
        'total_tokens': 25,
        'prompt_tokens_details': {'cached_tokens': 12},
      },
    });
    await router.chat(chat());
    final records = await settled();
    expect(records, hasLength(1));
    final record = records.single;
    expect(record.model, 'a/m1');
    expect(record.servedBy, 'a/m1');
    expect(record.totalTokens, 25);
    expect(record.cachedTokens, 12);
    expect(record.completionTokens, 5);
    expect(record.ttftMs, isNull);
    expect(record.durationMs, greaterThanOrEqualTo(0));
  });

  test('a streamed reply records its first-token time', () async {
    transport.pushSse([
      'data: {"choices":[{"delta":{"content":"he"}}]}',
      'data: {"choices":[{"delta":{"content":"llo"}}]}',
      'data: {"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}',
      'data: [DONE]',
    ]);
    final reply = await router.chat(chat(stream: true));
    expect(reply, isA<AiStreamReply>());
    await (reply as AiStreamReply).events.drain<void>();
    final records = await settled();
    expect(records, hasLength(1));
    expect(records.single.ttftMs, isNotNull);
    expect(records.single.totalTokens, 12);
  });

  test('a failed request leaves no log row', () async {
    transport.pushJson(401, {'error': 'bad key'});
    await expectLater(router.chat(chat()), throwsA(isA<AiRequestException>()));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await log.load(), isEmpty);
  });
}

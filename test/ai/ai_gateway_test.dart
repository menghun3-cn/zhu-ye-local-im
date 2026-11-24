import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

/// Scripted upstream answers, same shape as the router tests use.
final class FakeTransport implements AiTransport {
  final List<AiHttpResponse> queue = [];
  final List<AiRequestSpec> sent = [];

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
  Future<AiHttpResponse> send(AiRequestSpec request) async {
    sent.add(request);
    if (queue.isEmpty) {
      return AiHttpResponse(
        statusCode: 500,
        bodyBytes: Stream.value(utf8.encode('{}')),
      );
    }
    return queue.removeAt(0);
  }
}

void main() {
  late FakeTransport transport;
  late AiGateway gateway;
  late AiGatewayToken token;
  late HttpClient client;
  late String base;

  setUp(() async {
    transport = FakeTransport();
    final secrets = SecretBox.withKey(List<int>.filled(32, 3));
    final store = AiConfigStore(store: MemoryMessageStore(), secrets: secrets);
    await store.save(
      AiConfig(
        providers: [
          AiProvider(
            id: 'deepseek',
            name: 'DeepSeek',
            kind: AiProviderKind.preset,
            endpoints: const {
              AiProtocol.openaiChat: 'https://api.deepseek.com/v1',
            },
            apiKey: 'sk-test',
            models: const [
              AiProviderModel(
                id: 'deepseek-chat',
                protocol: AiProtocol.openaiChat,
                enabled: true,
              ),
            ],
          ),
        ],
        routingGroups: [
          AiRoutingGroup(
            id: 'main',
            name: 'Main',
            members: const ['deepseek/deepseek-chat'],
          ),
        ],
      ),
    );
    token = const AiGatewayToken('lt-ai-test-token');
    gateway = AiGateway(
      store: store,
      router: AiRouter(store: store, transport: transport),
      token: token,
    );
    await gateway.start();
    base = 'http://127.0.0.1:${gateway.actualPort}';
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await gateway.stop();
  });

  Future<HttpClientResponse> post(
    String path,
    Object? body, {
    bool auth = true,
  }) async {
    final request = await client.postUrl(Uri.parse('$base$path'));
    if (auth) request.headers.set('authorization', 'Bearer ${token.value}');
    request.write(jsonEncode(body));
    return request.close();
  }

  Future<HttpClientResponse> httpGet(String path, {bool auth = true}) async {
    final request = await client.getUrl(Uri.parse('$base$path'));
    if (auth) request.headers.set('authorization', 'Bearer ${token.value}');
    return request.close();
  }

  test('binds loopback only and reports its endpoint', () {
    expect(gateway.isRunning, isTrue);
    expect(gateway.endpoint, startsWith('http://127.0.0.1:'));
    expect(gateway.endpoint, endsWith('/v1'));
  });

  test('requests without the token are refused', () async {
    final response = await httpGet('/v1/models', auth: false);
    expect(response.statusCode, 401);
    await response.drain<void>();
  });

  test('/v1/models lists enabled models and groups', () async {
    final response = await httpGet('/v1/models');
    expect(response.statusCode, 200);
    final body = jsonDecode(await utf8.decodeStream(response));
    final ids = [for (final m in body['data'] as List) m['id'] as String];
    expect(ids, containsAll(['deepseek/deepseek-chat', 'group/main']));
  });

  test('chat completions answers in OpenAI shape', () async {
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'hi there'},
        },
      ],
      'usage': {'prompt_tokens': 3, 'completion_tokens': 2, 'total_tokens': 5},
    });
    final response = await post('/v1/chat/completions', {
      'model': 'deepseek/deepseek-chat',
      'messages': [
        {'role': 'user', 'content': 'hello'},
      ],
    });
    expect(response.statusCode, 200);
    final body = jsonDecode(await utf8.decodeStream(response));
    expect(body['object'], 'chat.completion');
    expect(body['choices'][0]['message']['content'], 'hi there');
    expect(body['model'], 'deepseek/deepseek-chat');
    expect(body['usage']['total_tokens'], 5);
    // The upstream saw a canonical request for the concrete model id.
    expect(transport.sent.single.url, contains('deepseek.com'));
  });

  test('a group reference routes through the router', () async {
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'grouped'},
        },
      ],
    });
    final response = await post('/v1/chat/completions', {
      'model': 'group/main',
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    final body = jsonDecode(await utf8.decodeStream(response));
    expect(body['choices'][0]['message']['content'], 'grouped');
  });

  test('streaming replies arrive as chat.completion.chunk frames', () async {
    transport.pushSse([
      'data: {"choices":[{"delta":{"content":"Hel"}}]}',
      'data: {"choices":[{"delta":{"content":"lo"}}]}',
      'data: [DONE]',
    ]);
    final response = await post('/v1/chat/completions', {
      'model': 'deepseek/deepseek-chat',
      'stream': true,
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/event-stream');
    final text = await utf8.decodeStream(response);
    expect(text, contains('chat.completion.chunk'));
    expect(text, contains('"Hel"'));
    expect(text, contains('"lo"'));
    // OpenAI clients wait for the empty-delta finish chunk before treating
    // the answer as complete.
    expect(text, contains('"finish_reason":"stop"'));
    expect(text.trimRight().endsWith('data: [DONE]'), isTrue);
  });

  test('a tool-call reply finishes with tool_calls, not stop', () async {
    transport.pushJson(200, {
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'lookup', 'arguments': '{}'},
              },
            ],
          },
          'finish_reason': 'tool_calls',
        },
      ],
    });
    final response = await post('/v1/chat/completions', {
      'model': 'deepseek/deepseek-chat',
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    expect(response.statusCode, 200);
    final body = jsonDecode(await utf8.decodeStream(response));
    expect(body['choices'][0]['finish_reason'], 'tool_calls');
    expect(body['choices'][0]['message']['tool_calls'][0]['id'], 'call_1');
  });

  test('messages with no usable entries are a 400', () async {
    final response = await post('/v1/chat/completions', {
      'model': 'deepseek/deepseek-chat',
      'messages': ['not a map', 42],
    });
    expect(response.statusCode, 400);
    await response.drain<void>();
  });

  test('malformed JSON is a 400, not a crash', () async {
    final request = await client.postUrl(
      Uri.parse('$base/v1/chat/completions'),
    );
    request.headers.set('authorization', 'Bearer ${token.value}');
    request.write('{not json');
    final response = await request.close();
    expect(response.statusCode, 400);
    await response.drain<void>();
  });

  test('missing model is a 400', () async {
    final response = await post('/v1/chat/completions', {
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    expect(response.statusCode, 400);
    await response.drain<void>();
  });

  test(
    'an upstream failure surfaces as a 502 with an OpenAI error body',
    () async {
      transport.pushJson(401, {'error': 'bad key'});
      final response = await post('/v1/chat/completions', {
        'model': 'deepseek/deepseek-chat',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(response.statusCode, 502);
      final body = jsonDecode(await utf8.decodeStream(response));
      expect(body['error']['message'], contains('401'));
    },
  );

  test('unknown paths are 404', () async {
    final response = await httpGet('/v1/nope');
    expect(response.statusCode, 404);
    await response.drain<void>();
  });
}

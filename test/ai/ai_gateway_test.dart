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
  late List<AiGatewayKey> keys;
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
    keys = [
      const AiGatewayKey(name: 'default', secret: 'lt-ai-test-token'),
      const AiGatewayKey(name: 'laptop', secret: 'sk-laptop-key'),
    ];
    gateway = AiGateway(
      store: store,
      router: AiRouter(store: store, transport: transport),
      keySource: () async => keys,
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
    if (auth) {
      request.headers.set('authorization', 'Bearer ${keys.first.secret}');
    }
    request.write(jsonEncode(body));
    return request.close();
  }

  Future<HttpClientResponse> httpGet(String path, {bool auth = true}) async {
    final request = await client.getUrl(Uri.parse('$base$path'));
    if (auth) {
      request.headers.set('authorization', 'Bearer ${keys.first.secret}');
    }
    return request.close();
  }

  test('binds loopback only and reports its endpoint', () {
    expect(gateway.isRunning, isTrue);
    expect(gateway.endpoint, startsWith('http://127.0.0.1:'));
    expect(gateway.endpoint, endsWith('/v1'));
  });

  test('LAN endpoints rank RFC1918 ahead of overlay space', () {
    // Deterministic check of the comparator the interface list is sorted
    // by — no dependence on which adapters this machine happens to have.
    expect(
      AiGateway.compareLanAddresses('192.168.1.20', '100.64.0.1'),
      lessThan(0),
    );
    expect(
      AiGateway.compareLanAddresses('10.0.0.5', '100.64.0.1'),
      lessThan(0),
    );
    expect(
      AiGateway.compareLanAddresses('172.16.0.9', '100.64.0.1'),
      lessThan(0),
    );
    expect(
      AiGateway.compareLanAddresses('100.64.0.1', '192.168.1.20'),
      greaterThan(0),
    );
    // Same rank falls back to plain string order (not numeric IP order).
    expect(AiGateway.compareLanAddresses('10.0.0.2', '10.0.0.3'), lessThan(0));
    expect(AiGateway.compareLanAddresses('10.0.0.10', '10.0.0.2'), lessThan(0));
    // Malformed input ranks as overlay rather than crashing the sort.
    expect(
      AiGateway.compareLanAddresses('not-an-ip', '192.168.1.20'),
      greaterThan(0),
    );
  });

  test('the bearer scheme is case-insensitive per RFC 7235', () async {
    for (final scheme in ['Bearer', 'bearer', 'BEARER', 'BeArEr']) {
      final request = await client.getUrl(Uri.parse('$base/v1/models'));
      request.headers.set('authorization', '$scheme ${keys.first.secret}');
      final response = await request.close();
      expect(response.statusCode, 200, reason: 'scheme: $scheme');
      await response.drain<void>();
    }
    // A different scheme is not a bearer credential.
    final basic = await client.getUrl(Uri.parse('$base/v1/models'));
    basic.headers.set(
      'authorization',
      'Basic ${base64Encode(utf8.encode('u:p'))}',
    );
    final denied = await basic.close();
    expect(denied.statusCode, 401);
    await denied.drain<void>();
    // 'Bearer' with no credential at all is refused too.
    final empty = await client.getUrl(Uri.parse('$base/v1/models'));
    empty.headers.set('authorization', 'Bearer');
    final refused = await empty.close();
    expect(refused.statusCode, 401);
    await refused.drain<void>();
  });

  test('a body over the limit is a 413', () async {
    final response = await post('/v1/chat/completions', {
      'model': 'deepseek/deepseek-chat',
      'messages': [
        // Just over the 1 MiB cap — inside the server's drain budget, so
        // the 413 arrives on a clean socket rather than a reset.
        {'role': 'user', 'content': 'x' * (1 << 20)},
      ],
    });
    expect(response.statusCode, 413);
    await response.drain<void>();
  });

  test('requests without the token are refused', () async {
    final response = await httpGet('/v1/models', auth: false);
    expect(response.statusCode, 401);
    await response.drain<void>();
  });

  test('every key authenticates, and a removed key stops working', () async {
    // The second key answers just like the default one.
    final laptop = await client.getUrl(Uri.parse('$base/v1/models'));
    laptop.headers.set('authorization', 'Bearer sk-laptop-key');
    final ok = await laptop.close();
    expect(ok.statusCode, 200);
    await ok.drain<void>();

    // The keyring is re-read per request: deleting the key revokes it
    // without a gateway restart.
    keys.removeWhere((k) => k.name == 'laptop');
    final revoked = await client.getUrl(Uri.parse('$base/v1/models'));
    revoked.headers.set('authorization', 'Bearer sk-laptop-key');
    final denied = await revoked.close();
    expect(denied.statusCode, 401);
    await denied.drain<void>();
  });

  test('/v1/models lists enabled models and groups', () async {
    final response = await httpGet('/v1/models');
    expect(response.statusCode, 200);
    final body = jsonDecode(await utf8.decodeStream(response));
    final ids = [for (final m in body['data'] as List) m['id'] as String];
    expect(ids, containsAll(['deepseek/deepseek-chat', 'group/main']));
  });

  test('chat completions answers in OpenAI shape', () async {
    // The gateway always asks upstream for a stream (that's where TTFT and
    // usage live) and folds it back for non-streaming callers.
    transport.pushSse([
      'data: {"choices":[{"delta":{"content":"hi "}}]}',
      'data: {"choices":[{"delta":{"content":"there"}}]}',
      'data: {"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}',
      'data: [DONE]',
    ]);
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
    transport.pushSse([
      'data: {"choices":[{"delta":{"content":"grouped"}}]}',
      'data: [DONE]',
    ]);
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
    transport.pushSse([
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{}"}}]}}]}',
      'data: [DONE]',
    ]);
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

  test('inbound tools and tool_choice reach the upstream request', () async {
    transport.pushSse([
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_9","type":"function","function":{"name":"lookup","arguments":"{\\"q\\":\\"x\\"}"}}]}}]}',
      'data: [DONE]',
    ]);
    final response = await post('/v1/chat/completions', {
      'model': 'deepseek/deepseek-chat',
      'messages': [
        {'role': 'user', 'content': 'find x'},
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'call_9',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{"q":"x"}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'call_9', 'content': '42'},
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'lookup',
            'description': 'Look something up',
            'parameters': {
              'type': 'object',
              'properties': {
                'q': {'type': 'string'},
              },
            },
          },
        },
        // Hosted tools have no canonical form and must not reach upstream.
        {'type': 'web_search'},
        {
          'type': 'function',
          'function': {'description': 'no name'},
        },
      ],
      'tool_choice': {
        'type': 'function',
        'function': {'name': 'lookup'},
      },
    });
    expect(response.statusCode, 200);
    await response.drain<void>();

    final upstream =
        jsonDecode(transport.sent.single.body!) as Map<String, Object?>;
    final tools = upstream['tools'] as List;
    expect(tools, hasLength(1));
    final fn = (((tools.single as Map)['function']) as Map)
        .cast<String, Object?>();
    expect(fn['name'], 'lookup');
    expect((fn['parameters'] as Map)['type'], 'object');
    final choice = (upstream['tool_choice'] as Map).cast<String, Object?>();
    expect(
      ((choice['function'] as Map).cast<String, Object?>())['name'],
      'lookup',
    );
    // The assistant tool_call and tool result survive the canonical hop.
    final messages = upstream['messages'] as List;
    expect((messages[1] as Map)['tool_calls'], isNotNull);
    expect((messages[2] as Map)['tool_call_id'], 'call_9');
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
    request.headers.set('authorization', 'Bearer ${keys.first.secret}');
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

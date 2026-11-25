import 'dart:async';
import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

/// Answers requests from a queue, in order, recording what it was asked.
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

AiConfig _config() => AiConfig(
  providers: [
    AiProvider(
      id: 'a',
      name: 'A',
      kind: AiProviderKind.custom,
      endpoints: const {AiProtocol.openaiChat: 'https://a.example/v1'},
      apiKey: 'k-a',
      models: const [
        AiProviderModel(
          id: 'm1',
          protocol: AiProtocol.openaiChat,
          enabled: true,
        ),
      ],
    ),
    AiProvider(
      id: 'b',
      name: 'B',
      kind: AiProviderKind.custom,
      endpoints: const {AiProtocol.openaiChat: 'https://b.example/v1'},
      apiKey: 'k-b',
      models: const [
        AiProviderModel(
          id: 'm2',
          protocol: AiProtocol.openaiChat,
          enabled: true,
        ),
      ],
    ),
  ],
  routingGroups: [
    AiRoutingGroup(id: 'main', name: 'Main', members: const ['a/m1', 'b/m2']),
    AiRoutingGroup(
      id: 'outer',
      name: 'Outer',
      members: const ['group/main', 'b/m2'],
    ),
    AiRoutingGroup(
      id: 'loopy',
      name: 'Loopy',
      members: const ['group/loopy', 'a/m1'],
    ),
  ],
);

void main() {
  late FakeTransport transport;
  late AiRouter router;

  setUp(() async {
    transport = FakeTransport();
    final secrets = SecretBox.withKey(List<int>.filled(32, 7));
    final store = AiConfigStore(store: MemoryMessageStore(), secrets: secrets);
    await store.save(_config());
    router = AiRouter(store: store, transport: transport);
  });

  AiChatRequest chat(String model, {bool stream = false}) => AiChatRequest(
    model: model,
    stream: stream,
    messages: const [AiMessage(role: AiRole.user, content: 'hi')],
  );

  test('a direct provider/model reference is served by that member', () async {
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'answer'},
        },
      ],
    });
    final reply = await router.chat(chat('a/m1'));
    expect(reply, isA<AiFullReply>());
    expect(reply.servedBy, 'a/m1');
    expect((reply as AiFullReply).response.content, 'answer');
    expect(transport.sent.single.url, 'https://a.example/v1/chat/completions');
  });

  test(
    'a group fails over on a retryable error and reports the survivor',
    () async {
      transport.pushJson(503, {'error': 'overloaded'});
      transport.pushJson(200, {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'from b'},
          },
        ],
      });
      final reply = await router.chat(chat('group/main'));
      expect(reply.servedBy, 'b/m2');
      expect(transport.sent, hasLength(2));
    },
  );

  test('a cooled-down member is skipped on the next request', () async {
    transport.pushJson(503, {});
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'from b'},
        },
      ],
    });
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'b again'},
        },
      ],
    });
    await router.chat(chat('group/main'));
    final second = await router.chat(chat('group/main'));
    expect(second.servedBy, 'b/m2');
    // Third request: a/m1 still cooling down, so only b is asked.
    expect(transport.sent, hasLength(3));
    expect(transport.sent.last.url, contains('b.example'));
  });

  test('a fatal error does not fail over', () async {
    transport.pushJson(401, {'error': 'bad key'});
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'should not happen'},
        },
      ],
    });
    await expectLater(
      router.chat(chat('group/main')),
      throwsA(isA<AiRequestException>()),
    );
    expect(transport.sent, hasLength(1));
  });

  test('all members retryable-failing surfaces the last error', () async {
    transport.pushJson(429, {});
    transport.pushJson(503, {});
    await expectLater(
      router.chat(chat('group/main')),
      throwsA(isA<AiRequestException>()),
    );
    expect(transport.sent, hasLength(2));
  });

  test('a cooled-down member reports the error that benched it', () async {
    transport.pushJson(503, {'error': 'overloaded'});
    // First call fails retryably and benches the only member of the group
    // reference; the second call must not pretend nobody exists — it has to
    // repeat why the member is sitting out.
    await expectLater(
      router.chat(chat('a/m1')),
      throwsA(isA<AiRequestException>()),
    );
    await expectLater(
      router.chat(chat('a/m1')),
      throwsA(
        isA<AiRequestException>().having(
          (e) => e.message,
          'message',
          contains('cooling down'),
        ),
      ),
    );
    // And the benched member was not asked again.
    expect(transport.sent, hasLength(1));
  });

  test('nested groups expand depth-first', () async {
    transport.pushJson(503, {});
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'nested ok'},
        },
      ],
    });
    final reply = await router.chat(chat('group/outer'));
    expect(reply.servedBy, 'b/m2');
    expect(transport.sent, hasLength(2));
  });

  test('a group cycle terminates instead of recursing forever', () async {
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'loopy ok'},
        },
      ],
    });
    final reply = await router.chat(chat('group/loopy'));
    expect(reply.servedBy, 'a/m1');
  });

  test('streaming requests return an AiStreamReply', () async {
    transport.pushSse([
      'data: {"choices":[{"delta":{"content":"hi"}}]}',
      'data: [DONE]',
    ]);
    final reply = await router.chat(chat('a/m1', stream: true));
    expect(reply, isA<AiStreamReply>());
    final events = await (reply as AiStreamReply).events.toList();
    expect(events.first.text, 'hi');
    expect(events.last.kind, AiStreamKind.done);
  });

  test('an unknown provider is a fatal AiRequestException', () async {
    await expectLater(
      router.chat(chat('ghost/m1')),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('a disabled model is refused even though the provider has it', () async {
    final secrets = SecretBox.withKey(List<int>.filled(32, 7));
    final store = AiConfigStore(store: MemoryMessageStore(), secrets: secrets);
    final config = _config();
    await store.save(
      config.copyWith(
        providers: [
          config.providers.first.copyWith(
            models: [
              const AiProviderModel(
                id: 'm1',
                protocol: AiProtocol.openaiChat,
                enabled: false,
              ),
            ],
          ),
          config.providers[1],
        ],
      ),
    );
    final local = AiRouter(store: store, transport: transport);
    await expectLater(
      local.chat(chat('a/m1')),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('listModels asks the codec for a spec and decodes the answer', () async {
    transport.pushJson(200, {
      'data': [
        {'id': 'm1'},
        {'id': 'm2'},
      ],
    });
    final models = await router.listModels('a', AiProtocol.openaiChat);
    expect(models, ['m1', 'm2']);
    expect(transport.sent.single.url, 'https://a.example/v1/models');
  });

  test('listModels is empty for a protocol the provider lacks', () async {
    final models = await router.listModels('a', AiProtocol.anthropic);
    expect(models, isEmpty);
    expect(transport.sent, isEmpty);
  });

  test('fetchModelCatalog keeps the metadata the endpoint reports', () async {
    transport.pushJson(200, {
      'data': [
        {
          'id': 'free/m',
          'name': 'Free Model',
          'context_length': 256000,
          'pricing': {'prompt': '0', 'completion': '0'},
        },
      ],
    });
    final provider = _config().providers.first;
    final catalog = await router.fetchModelCatalog(
      provider,
      AiProtocol.openaiChat,
    );
    expect(catalog.single.id, 'free/m');
    expect(catalog.single.label, 'Free Model');
    expect(catalog.single.contextTokens, 256000);
    expect(catalog.single.isFree, isTrue);
  });

  test('route events trace a failover under one call id', () async {
    final seen = <AiRouteEvent>[];
    final sub = router.events.listen(seen.add);
    addTearDown(sub.cancel);

    transport.pushJson(503, {});
    transport.pushJson(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'from b'},
        },
      ],
    });
    await router.chat(chat('group/main'));
    // Broadcast events are async: let the loop deliver them.
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((e) => e.phase), [
      AiRoutePhase.attempt,
      AiRoutePhase.failed,
      AiRoutePhase.attempt,
      AiRoutePhase.served,
    ]);
    expect(seen.map((e) => e.member), ['a/m1', 'a/m1', 'b/m2', 'b/m2']);
    expect(seen.every((e) => e.callId == seen.first.callId), isTrue);
    expect(seen.first.model, 'group/main');
  });

  test('a streamed reply reports served only when the stream ends', () async {
    final seen = <AiRouteEvent>[];
    final sub = router.events.listen(seen.add);
    addTearDown(sub.cancel);

    transport.pushSse([
      'data: {"choices":[{"delta":{"content":"hi"}}]}',
      'data: [DONE]',
    ]);
    final reply = await router.chat(chat('a/m1', stream: true));
    await Future<void>.delayed(Duration.zero);
    // Headers are in, but nobody has consumed the stream yet: the route
    // is still "in flight", so served must not have fired.
    expect(seen.map((e) => e.phase), isNot(contains(AiRoutePhase.served)));

    await (reply as AiStreamReply).events.toList();
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.phase, AiRoutePhase.served);
    expect(seen.last.member, 'a/m1');
  });

  test('a member rejected before dispatch emits failed, not attempt', () async {
    final seen = <AiRouteEvent>[];
    final sub = router.events.listen(seen.add);
    addTearDown(sub.cancel);

    // 'a/nope' names a model the provider does not have enabled: the router
    // rejects it before a single byte is sent, so the route trace must not
    // claim an attempt — the canvas leaf means "request went upstream".
    await expectLater(
      router.chat(chat('a/nope')),
      throwsA(isA<AiRequestException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(transport.sent, isEmpty);
    expect(seen.map((e) => e.phase), [AiRoutePhase.failed]);
    expect(seen.single.member, 'a/nope');
  });
}

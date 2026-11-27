import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late AiRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-runtime-test');
    runtime = await AiRuntime.open(directory.path);
  });

  tearDown(() async {
    await runtime.dispose();
    await directory.delete(recursive: true);
  });

  test('opens with defaults, seeds builtins and persists providers', () async {
    var config = await runtime.load();
    // First open seeds the public providers once: enabled, with their
    // shared credentials already in place.
    expect(config.builtinsSeeded, isTrue);
    expect(config.providers.map((p) => p.id), ['opencode-zen', 'kilo']);
    expect(config.providers.every((p) => p.enabled), isTrue);
    // The gateway defaults on: loopback is nil-risk behind the token, and
    // "configure once, use everywhere" needs it listening without a detour
    // through settings. `start()` was never called, so nothing is bound.
    expect(config.gateway.enabled, isTrue);
    expect(config.gateway.scope, AiGatewayScope.loopback);
    expect(runtime.gateway, isNull);

    config = config.copyWith(
      providers: [
        ...config.providers,
        AiProvider(
          id: 'local',
          name: 'Local',
          kind: AiProviderKind.local,
          endpoints: const {AiProtocol.openaiChat: 'http://localhost:11434/v1'},
          models: const [
            AiProviderModel(
              id: 'llama3',
              protocol: AiProtocol.openaiChat,
              enabled: true,
            ),
          ],
        ),
      ],
    );
    await runtime.save(config);

    final reloaded = await runtime.load();
    expect(reloaded.providers.map((p) => p.id), [
      'opencode-zen',
      'kilo',
      'local',
    ]);
    expect(reloaded.providers.last.models.single.enabled, isTrue);
  });

  test('builtins are seeded once and a deletion stays deleted', () async {
    var config = await runtime.load();
    expect(config.providers, hasLength(2));

    // The user removes Kilo; the next open must not resurrect it.
    await runtime.save(
      config.copyWith(
        providers: [
          for (final p in config.providers)
            if (p.id != 'kilo') p,
        ],
      ),
    );
    await runtime.dispose();
    runtime = await AiRuntime.open(directory.path);
    config = await runtime.load();
    expect(config.providers.map((p) => p.id), ['opencode-zen']);
    expect(config.builtinsSeeded, isTrue);
  });

  test('the gateway flag binds and releases the socket', () async {
    final config = await runtime.load();
    await runtime.save(
      config.copyWith(gateway: const AiGatewayConfig(enabled: true)),
    );
    expect(runtime.gateway, isNotNull);
    expect(runtime.endpoint, startsWith('http://127.0.0.1:'));

    await runtime.save(
      config.copyWith(gateway: const AiGatewayConfig(enabled: false)),
    );
    expect(runtime.gateway, isNull);
    expect(runtime.endpoint, isNull);
  });

  test('concurrent saves bind exactly one gateway', () async {
    final config = await runtime.load();
    final enabled = config.copyWith(
      gateway: const AiGatewayConfig(enabled: true),
    );
    // Two saves racing the bind must not each open a socket: the loser
    // would leak a listener nobody can reach to close.
    await Future.wait([runtime.save(enabled), runtime.save(enabled)]);
    expect(runtime.gateway, isNotNull);
    final endpoint = runtime.endpoint;
    expect(endpoint, isNotNull);

    await runtime.save(
      config.copyWith(gateway: const AiGatewayConfig(enabled: false)),
    );
    expect(runtime.gateway, isNull);
    // And nothing is still listening on the old endpoint.
    final client = HttpClient();
    addTearDown(client.close);
    await expectLater(
      client.getUrl(Uri.parse('$endpoint/models')),
      throwsA(isA<SocketException>()),
    );
  });

  test('a scope change rebinds the gateway', () async {
    final config = await runtime.load();
    await runtime.save(
      config.copyWith(gateway: const AiGatewayConfig(enabled: true)),
    );
    final loopback = runtime.gateway;
    expect(loopback, isNotNull);
    expect(loopback!.scope, AiGatewayScope.loopback);

    await runtime.save(
      config.copyWith(
        gateway: const AiGatewayConfig(
          enabled: true,
          scope: AiGatewayScope.lan,
        ),
      ),
    );
    final lan = runtime.gateway;
    expect(lan, isNotNull);
    expect(lan, isNot(loopback));
    expect(lan!.scope, AiGatewayScope.lan);
    // 0.0.0.0 answers loopback too, so the local endpoint still works.
    expect(runtime.endpoint, isNotNull);
  });

  test('the default gateway key is seeded once and reused', () async {
    final keys = await runtime.keys.load();
    expect(keys, hasLength(1));
    expect(keys.single.name, 'default');
    expect(keys.single.secret, startsWith('sk-'));

    // Reopening reads the same keyring rather than rotating.
    final again = await AiGatewayKeyStore(
      file: File('${directory.path}/gateway_keys.json'),
    ).load();
    expect(again.single.secret, keys.single.secret);
  });

  test('a corrupt keyring throws instead of rotating credentials', () async {
    final file = File('${directory.path}/gateway_keys.json');
    await file.writeAsString('{not json');
    final store = AiGatewayKeyStore(file: file);

    await expectLater(store.load(), throwsA(isA<AiGatewayKeyStoreException>()));
    // loadOrCreate must not "help" by minting a fresh default key — that
    // would lock every configured client out silently.
    await expectLater(
      store.loadOrCreate(),
      throwsA(isA<AiGatewayKeyStoreException>()),
    );
    expect(await file.readAsString(), '{not json');
    // The live runtime surfaces the same error rather than rotating.
    await expectLater(
      runtime.keys.load(),
      throwsA(isA<AiGatewayKeyStoreException>()),
    );
  });

  test('an emptied keyring stays empty across reopen', () async {
    // A user who deletes every key must not get `default` resurrected on
    // the next launch — an empty ring is a deliberate state, not a seed
    // signal. (The UI currently refuses to delete the last key, so this
    // guards the file-level contract.)
    final file = File('${directory.path}/gateway_keys.json');
    await file.writeAsString('[]');
    final store = AiGatewayKeyStore(file: file);
    expect(await store.loadOrCreate(), isEmpty);
    expect(await file.readAsString(), '[]');
  });

  test('a legacy gateway_token file migrates into the default key', () async {
    await File('${directory.path}/gateway_token').writeAsString('lt-ai-old');
    final store = AiGatewayKeyStore(
      file: File('${directory.path}/keys-migrated.json'),
      legacyTokenPath: '${directory.path}/gateway_token',
    );
    final keys = await store.loadOrCreate();
    expect(keys.single.name, 'default');
    expect(keys.single.secret, 'lt-ai-old');
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late AiConfigStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_config_store_test');
    final secrets = await SecretBox.open('${tempDir.path}/secrets.key');
    store = AiConfigStore(
      store: FileMessageStore('${tempDir.path}/providers.json'),
      secrets: secrets,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  AiConfig sampleConfig() => AiConfig(
    providers: [
      AiProvider(
        id: 'deepseek',
        name: 'DeepSeek',
        kind: AiProviderKind.preset,
        endpoints: const {AiProtocol.openaiChat: 'https://api.deepseek.com/v1'},
        apiKey: 'sk-live-secret',
        models: const [
          AiProviderModel(
            id: 'deepseek-chat',
            protocol: AiProtocol.openaiChat,
            enabled: true,
            label: 'DeepSeek Chat',
            contextTokens: 128000,
            isFree: false,
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
    gateway: const AiGatewayConfig(enabled: true),
  );

  test('save/load round-trips the whole config', () async {
    await store.save(sampleConfig());
    final loaded = await store.load();
    expect(loaded.providers.single.id, 'deepseek');
    expect(loaded.providers.single.apiKey, 'sk-live-secret');
    expect(loaded.providers.single.models.single.enabled, isTrue);
    final model = loaded.providers.single.models.single;
    expect(model.label, 'DeepSeek Chat');
    expect(model.contextTokens, 128000);
    expect(model.isFree, isFalse);
    expect(loaded.routingGroups.single.id, 'main');
    expect(loaded.gateway.enabled, isTrue);
  });

  test('the apiKey on disk is sealed, not plaintext', () async {
    await store.save(sampleConfig());
    final raw = await File('${tempDir.path}/providers.json').readAsString();
    expect(raw, isNot(contains('sk-live-secret')));
    expect(raw, contains('v1:'));
    // Sanity: it is still valid JSON.
    expect(jsonDecode(raw), isA<Map<String, Object?>>());
  });

  test('a plaintext apiKey from an old file is sealed on next save', () async {
    // Simulate a pre-encryption file: write plaintext directly through the
    // delegate store.
    final delegate = FileMessageStore('${tempDir.path}/providers.json');
    await delegate.save({
      'version': 1,
      'providers': [
        {
          'id': 'old',
          'name': 'Old',
          'kind': 'custom',
          'endpoints': <String, Object?>{},
          'apiKey': 'sk-legacy-plain',
          'models': <Object?>[],
          'enabled': true,
        },
      ],
      'routingGroups': <Object?>[],
      'gateway': <String, Object?>{'enabled': false, 'port': 0},
    });

    final loaded = await store.load();
    expect(loaded.providers.single.apiKey, 'sk-legacy-plain');

    await store.save(loaded);
    final raw = await File('${tempDir.path}/providers.json').readAsString();
    expect(raw, isNot(contains('sk-legacy-plain')));
  });

  test('load with nothing saved returns defaults', () async {
    final loaded = await store.load();
    expect(loaded.providers, isEmpty);
    // Gateway on by default (loopback, preferred port) — see
    // AiGatewayConfig's doc comment for why.
    expect(loaded.gateway.enabled, isTrue);
    expect(loaded.gateway.scope, AiGatewayScope.loopback);
    expect(loaded.gateway.port, AiGatewayConfig.defaultPort);
  });

  test('a stored port of 0 migrates to the preferred port', () async {
    // Files written before the fixed-port change carry "port": 0, which
    // used to mean ephemeral. It now reads as the default so existing
    // installs get the stable endpoint too.
    final delegate = FileMessageStore('${tempDir.path}/providers.json');
    await delegate.save({
      'version': 1,
      'providers': <Object?>[],
      'routingGroups': <Object?>[],
      'gateway': <String, Object?>{'enabled': true, 'port': 0},
    });
    final loaded = await store.load();
    expect(loaded.gateway.port, AiGatewayConfig.defaultPort);
  });

  test('the gateway scope round-trips through providers.json', () async {
    final config = sampleConfig().copyWith(
      gateway: const AiGatewayConfig(enabled: true, scope: AiGatewayScope.lan),
    );
    await store.save(config);
    final loaded = await store.load();
    expect(loaded.gateway.scope, AiGatewayScope.lan);
  });

  test('AiConfig.exposedModelRefs lists enabled models and groups', () async {
    await store.save(sampleConfig());
    final loaded = await store.load();
    expect(loaded.exposedModelRefs(), ['deepseek/deepseek-chat', 'group/main']);
  });
}

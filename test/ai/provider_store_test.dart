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
    gateway: const AiGatewayConfig(enabled: true, port: 0),
  );

  test('save/load round-trips the whole config', () async {
    await store.save(sampleConfig());
    final loaded = await store.load();
    expect(loaded.providers.single.id, 'deepseek');
    expect(loaded.providers.single.apiKey, 'sk-live-secret');
    expect(loaded.providers.single.models.single.enabled, isTrue);
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
    expect(loaded.gateway.enabled, isFalse);
  });

  test('AiConfig.exposedModelRefs lists enabled models and groups', () async {
    await store.save(sampleConfig());
    final loaded = await store.load();
    expect(loaded.exposedModelRefs(), ['deepseek/deepseek-chat', 'group/main']);
  });
}

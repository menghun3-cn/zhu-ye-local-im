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

  test('opens with defaults and persists providers', () async {
    var config = await runtime.load();
    expect(config.providers, isEmpty);
    expect(config.gateway.enabled, isFalse);
    expect(runtime.gateway, isNull);

    config = config.copyWith(
      providers: [
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
    expect(reloaded.providers.single.id, 'local');
    expect(reloaded.providers.single.models.single.enabled, isTrue);
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

  test('the token is generated once and reused', () async {
    final first = runtime.token.value;
    expect(first, startsWith('lt-ai-'));

    final again = await AiGatewayToken.loadOrCreate(
      '${directory.path}/gateway_token',
    );
    expect(again.value, first);
  });
}

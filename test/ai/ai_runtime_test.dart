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
    // The gateway defaults on: loopback is nil-risk behind the token, and
    // "configure once, use everywhere" needs it listening without a detour
    // through settings. `start()` was never called, so nothing is bound.
    expect(config.gateway.enabled, isTrue);
    expect(config.gateway.scope, AiGatewayScope.loopback);
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

  test('the token is generated once and reused', () async {
    final first = runtime.token.value;
    expect(first, startsWith('lt-ai-'));

    final again = await AiGatewayToken.loadOrCreate(
      '${directory.path}/gateway_token',
    );
    expect(again.value, first);
  });
}

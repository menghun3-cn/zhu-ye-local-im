import 'ai_gateway.dart';
import 'ai_router.dart';
import 'builtin_providers.dart';
import 'gateway_token.dart';
import 'provider.dart';
import 'provider_store.dart';
import 'secret_box.dart';
import '../history/message_store.dart';

/// The running AI stack: configuration store, router and — when the
/// persisted gateway flag asks for it — the loopback HTTP server.
///
/// This is the object the settings UI edits through and the object the app
/// owns for its lifetime. It exists so that "change a setting" has one
/// answer: [save] persists the new [AiConfig] *and* brings the gateway in
/// line with it, rather than leaving a caller to remember that a flag lives
/// in two places (the JSON document and the bound socket).
///
/// Plain Dart — `dart:io` only — so `dart test` covers it without a widget
/// tree.
final class AiRuntime {
  AiRuntime._({
    required this.directory,
    required this.store,
    required this.router,
    required this.token,
  });

  /// Where `providers.json`, `secrets.key` and `gateway_token` live.
  final String directory;

  /// Configuration persistence, with keys sealed on the way out.
  final AiConfigStore store;

  /// Reference resolution and failover, reading [store] per request.
  final AiRouter router;

  /// The bearer token the gateway asks callers for.
  final AiGatewayToken token;

  AiGateway? _gateway;

  /// The gateway configuration the running server was bound with — a save
  /// that changes scope or port must rebind, not just flip a flag.
  AiGatewayConfig? _boundGateway;

  /// Serializes [_syncGateway]: two saves landing while a bind is in flight
  /// must not each create a server — the loser would leak a listening port
  /// nobody holds a reference to.
  Future<void> _syncing = Future.value();

  int _configVersion = 0;

  /// Bumped on every [save]. Live views (the routing canvas) poll it to
  /// learn the document changed without a reload handshake.
  int get configVersion => _configVersion;

  /// The bound gateway, or null while the flag is off or the bind failed.
  AiGateway? get gateway => _gateway;

  /// The base URL callers configure, or null while nothing listens.
  String? get endpoint => _gateway?.endpoint;

  /// The LAN addresses the gateway answers on, empty under loopback scope
  /// or while nothing listens.
  List<String> get lanAddresses => _gateway?.lanAddresses ?? const [];

  /// Assembles the stack under [directory].
  ///
  /// Returns null only through the caller's own null check on `directory` —
  /// an unreadable store throws, because a settings page that cannot read
  /// its configuration has nothing honest to draw.
  static Future<AiRuntime> open(String directory) async {
    final secrets = await SecretBox.open('$directory/secrets.key');
    final store = AiConfigStore(
      store: FileMessageStore('$directory/providers.json'),
      secrets: secrets,
    );
    await _seedBuiltins(store);
    return AiRuntime._(
      directory: directory,
      store: store,
      router: AiRouter(store: store),
      token: await AiGatewayToken.loadOrCreate('$directory/gateway_token'),
    );
  }

  /// Writes the built-in providers once, on the first configuration the
  /// store ever loads. Ids already present are skipped rather than replaced
  /// — a returning install that deleted one keeps it deleted — and the
  /// flag flips either way so this never runs twice.
  static Future<void> _seedBuiltins(AiConfigStore store) async {
    final config = await store.load();
    if (config.builtinsSeeded) return;
    final providers = [...config.providers];
    for (final builtin in aiBuiltinProviders) {
      if (config.providerNamed(builtin.id) == null) {
        providers.add(builtin);
      }
    }
    await store.save(
      config.copyWith(providers: providers, builtinsSeeded: true),
    );
  }

  /// The persisted configuration.
  Future<AiConfig> load() => store.load();

  /// Persists [config] and reconciles the gateway with its flag.
  ///
  /// Enabling binds immediately; disabling closes the socket. A bind
  /// failure leaves the configuration saved — the flag is the user's
  /// decision, and the next app start retries the bind — while [gateway]
  /// reports null so the UI can say "configured but not listening".
  Future<void> save(AiConfig config) async {
    await store.save(config);
    _configVersion++;
    await _syncGateway(config.gateway);
  }

  /// Reads the stored configuration and binds the gateway if it asks.
  ///
  /// Called once at app start; afterwards [save] keeps the two in step.
  Future<void> start() async => _syncGateway((await store.load()).gateway);

  Future<void> _syncGateway(AiGatewayConfig gateway) {
    final run = _syncing.then((_) => _syncGatewayNow(gateway));
    // The chain survives a failed link: a bind error is already swallowed
    // inside, but a store error must not poison every later save.
    _syncing = run.catchError((_) {});
    return run;
  }

  Future<void> _syncGatewayNow(AiGatewayConfig gateway) async {
    final running = _gateway;
    if (!gateway.enabled) {
      if (running != null) {
        _gateway = null;
        _boundGateway = null;
        await running.stop();
      }
      return;
    }
    // Already bound *with this exact configuration*: a scope or port change
    // is a different server, not a no-op.
    final bound = _boundGateway;
    if (running != null &&
        bound != null &&
        bound.port == gateway.port &&
        bound.scope == gateway.scope) {
      return;
    }
    if (running != null) {
      _gateway = null;
      _boundGateway = null;
      await running.stop();
    }
    final server = AiGateway(store: store, router: router, token: token);
    try {
      await server.start(preferredPort: gateway.port, scope: gateway.scope);
      _gateway = server;
      _boundGateway = gateway;
    } on Object {
      // Port taken and the fallback also failed, or the socket is denied:
      // the flag stays set so the next launch retries, and the settings
      // surface reports the endpoint as absent rather than pretending.
      _gateway = null;
      _boundGateway = null;
    }
  }

  /// Stops the gateway. The app calls this on the way out; the configuration
  /// on disk is untouched.
  Future<void> dispose() async {
    final running = _gateway;
    _gateway = null;
    _boundGateway = null;
    await running?.stop();
  }
}

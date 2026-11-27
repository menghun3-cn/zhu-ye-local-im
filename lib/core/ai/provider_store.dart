import '../history/message_store.dart' show MessageStore;
import 'provider.dart';
import 'secret_box.dart';

/// Where the AI configuration lives: one JSON envelope plus a [SecretBox]
/// for the credentials inside it.
///
/// The store delegates the file mechanics — atomic temp-then-rename writes,
/// corrupt-file move-aside, write chaining — to the same [MessageStore]
/// abstraction the conversation history uses, so `providers.json` inherits
/// exactly the durability story the rest of the app already has. What this
/// class adds on top is the sealing boundary: [AiConfig] in memory holds
/// plaintext keys, the JSON on disk never does.
final class AiConfigStore {
  AiConfigStore({required this.store, required this.secrets});

  /// The JSON envelope mechanics — atomic writes, corrupt move-aside.
  final MessageStore store;

  /// Seals and unseals the `apiKey` fields inside the envelope.
  final SecretBox secrets;

  /// The stored configuration, or defaults when nothing has been saved.
  ///
  /// A provider whose `apiKey` still lacks the `v1:` seal prefix is read as
  /// plaintext — files written before sealing existed keep working, and the
  /// next [save] seals them.
  Future<AiConfig> load() async {
    final json = await store.load();
    if (json == null) return AiConfig();
    final config = AiConfig.fromJson(json);
    final providers = <AiProvider>[];
    for (final provider in config.providers) {
      providers.add(
        provider.copyWith(
          apiKey: await _unseal(provider.apiKey),
          proxy: await _unseal(provider.proxy),
        ),
      );
    }
    return config.copyWith(providers: providers);
  }

  /// Plaintext passes through — files written before sealing existed keep
  /// working — while a `v1:` value is decrypted. Shared by every credential
  /// field a provider carries (the key, and a proxy URL that may embed
  /// `user:pass@`).
  Future<String?> _unseal(String? stored) async {
    if (stored == null || stored.isEmpty) return stored;
    return secrets.unseal(stored);
  }

  /// Persists [config], sealing every non-empty credential field on the
  /// way out — `apiKey`, and `proxy` for the same reason.
  Future<void> save(AiConfig config) async {
    final providers = <AiProvider>[];
    for (final provider in config.providers) {
      providers.add(
        provider.copyWith(
          apiKey: await _seal(provider.apiKey),
          proxy: await _sealNullable(provider.proxy),
        ),
      );
    }
    await store.save(config.copyWith(providers: providers).toJson());
  }

  Future<String> _seal(String stored) async {
    if (stored.isEmpty || SecretBox.isSealed(stored)) return stored;
    return secrets.seal(stored);
  }

  Future<String?> _sealNullable(String? stored) async {
    if (stored == null) return null;
    return _seal(stored);
  }
}

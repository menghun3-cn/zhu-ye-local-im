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
      final key = provider.apiKey;
      providers.add(
        provider.copyWith(
          apiKey: key.isEmpty ? key : await secrets.unseal(key),
        ),
      );
    }
    return config.copyWith(providers: providers);
  }

  /// Persists [config], sealing every non-empty `apiKey` on the way out.
  Future<void> save(AiConfig config) async {
    final providers = <AiProvider>[];
    for (final provider in config.providers) {
      final key = provider.apiKey;
      providers.add(
        provider.copyWith(
          apiKey: key.isEmpty || SecretBox.isSealed(key)
              ? key
              : await secrets.seal(key),
        ),
      );
    }
    await store.save(config.copyWith(providers: providers).toJson());
  }
}

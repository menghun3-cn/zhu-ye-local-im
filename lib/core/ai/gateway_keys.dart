import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// One caller credential for the local AI gateway.
///
/// Every client that dials the gateway gets its own key so the request log
/// can say *which* client spent the tokens — "default" is the migrated
/// single-token install, and each added key is one more named client.
final class AiGatewayKey {
  const AiGatewayKey({
    required this.name,
    required this.secret,
    this.createdAt,
  });

  /// The label the user gave the client — shown in settings and stamped on
  /// every request-log row the key serves.
  final String name;

  /// The bearer secret as callers present it. Stored plaintext like the
  /// legacy `gateway_token` file: the threat model is other local processes,
  /// and the UI shows the value by design.
  final String secret;

  final DateTime? createdAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'secret': secret,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  factory AiGatewayKey.fromJson(Map<String, Object?> json) => AiGatewayKey(
    name: json['name'] as String? ?? '',
    secret: json['secret'] as String? ?? '',
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
  );
}

/// The gateway's keyring: `gateway_keys.json` beside `providers.json`.
///
/// First open migrates the single `gateway_token` file into a key named
/// `default` — existing clients keep working with the credential they
/// already have — or, on a fresh install, creates `default` with a
/// generated `sk-` secret.
final class AiGatewayKeyStore {
  AiGatewayKeyStore({required this.file, this.legacyTokenPath});

  final File file;

  /// The pre-keys credential file, read once as the `default` seed.
  final String? legacyTokenPath;

  Future<List<AiGatewayKey>> load() async {
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map)
            AiGatewayKey.fromJson(entry.cast<String, Object?>()),
      ];
    } on Object {
      return const [];
    }
  }

  Future<void> save(List<AiGatewayKey> keys) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final key in keys) key.toJson()]));
    await tmp.rename(file.path);
  }

  /// Loads the keyring, seeding `default` on first run. The legacy token
  /// file is left in place — deleting it would break a downgrade, and it
  /// holds nothing the keyring does not already know.
  Future<List<AiGatewayKey>> loadOrCreate() async {
    final existing = await load();
    if (existing.isNotEmpty) return existing;
    var secret = '';
    final legacy = legacyTokenPath;
    if (legacy != null) {
      final file = File(legacy);
      if (await file.exists()) {
        secret = (await file.readAsString()).trim();
      }
    }
    if (secret.isEmpty) secret = generateSecret();
    final keys = [
      AiGatewayKey(name: 'default', secret: secret, createdAt: DateTime.now()),
    ];
    await save(keys);
    return keys;
  }

  /// `sk-` + 24 random bytes — recognisably this gateway's credential the
  /// way `sk-magpie-key-` marks magpie's.
  static String generateSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return 'sk-${base64UrlEncode(bytes)}';
  }
}

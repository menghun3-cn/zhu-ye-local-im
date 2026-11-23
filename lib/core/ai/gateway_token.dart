import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// The bearer token the local AI gateway asks its callers for.
///
/// The gateway binds loopback only, so the token is not protecting the
/// network — it is protecting the *user*: any process on this machine can
/// otherwise spend the API keys stored in `providers.json` by pointing a
/// client at `127.0.0.1`. A generated, persisted token means the keys stay
/// usable by the user's own tools (they paste the token once, like magpie's
/// `sk-magpie-key`) without being free for every local process to find.
///
/// It lives in its own file rather than inside `providers.json` for the same
/// reason the document gives secrets their own boundary: the token is shown
/// in the UI in plaintext by design, and a leak of the displayed string
/// should not hand over the provider keys beside it.
final class AiGatewayToken {
  const AiGatewayToken(this.value);

  /// The token as callers present it: `Authorization: Bearer <value>`.
  final String value;

  /// Reads the token at [path], creating and persisting one on first use.
  ///
  /// The file holds the bare token string. A file that exists but is empty
  /// or whitespace is treated as absent and rotated — a token nobody can
  /// type is not a token.
  static Future<AiGatewayToken> loadOrCreate(String path) async {
    final file = File(path);
    if (await file.exists()) {
      final stored = (await file.readAsString()).trim();
      if (stored.isNotEmpty) return AiGatewayToken(stored);
    }
    final token = AiGatewayToken(_generate());
    await file.parent.create(recursive: true);
    await file.writeAsString(token.value, flush: true);
    return token;
  }

  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    // `lt-ai-` marks it as this app's token the way `sk-magpie-key-` marks
    // magpie's, so a pasted credential is recognisable at a glance.
    return 'lt-ai-${base64UrlEncode(bytes)}';
  }
}

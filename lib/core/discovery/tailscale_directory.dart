import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The IPv4 addresses of the Devices in this machine's Tailscale tailnet.
///
/// Broadcast discovery cannot cross the tailnet — Tailscale carries no
/// broadcast or multicast — but every peer's Tailscale IP is unicast
/// reachable, so naming them turns "who is out there" back into a probing
/// problem the [DiscoveryService] already solves.
///
/// The addresses come from tailscaled's local API, `GET /localapi/v0/status`
/// on the loopback address. That endpoint needs no credential from a
/// loopback client under a default install; a daemon started with a custom
/// socket or an operator-only policy simply does not answer, which this
/// class treats as "no tailnet" rather than as an error — discovery falls
/// back to whatever other targets exist.
///
/// The Tailscale app on Android does not expose this API, so on that
/// platform [peers] is always empty and remembered addresses carry the
/// load alone. That asymmetry is a platform fact, not a bug.
final class TailscaleDirectory {
  TailscaleDirectory({
    String baseUrl = defaultBaseUrl,
    this.refreshInterval = const Duration(seconds: 30),
    Future<String?> Function(Uri url)? fetch,
    DateTime Function()? clock,
  }) : _statusUrl = Uri.parse(
         '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}'
         '$statusPath',
       ),
       _fetch = fetch ?? _httpGet,
       _clock = clock ?? DateTime.now;

  /// Where tailscaled's local API listens on a default install.
  static const String defaultBaseUrl = 'http://127.0.0.1:41112';

  /// The local API endpoint that reports this node and its peers.
  static const String statusPath = '/localapi/v0/status';

  /// How often the status endpoint is asked again.
  ///
  /// Peers join and leave a tailnet on human timescales, so half a minute is
  /// freshness nobody can perceive and cost nobody pays: one small loopback
  /// request.
  final Duration refreshInterval;

  final Uri _statusUrl;
  final Future<String?> Function(Uri url) _fetch;
  final DateTime Function() _clock;

  List<InternetAddress> _peers = const [];
  DateTime? _fetchedAt;
  bool _fetching = false;

  /// The peers' Tailscale IPv4 addresses, cached between refreshes.
  ///
  /// Never throws: an absent daemon, a refused connection, a non-200 answer
  /// or a body that does not parse all mean "nothing to add right now", and
  /// whatever was learned last time is kept — a tailnet that blinks should
  /// not empty the target list.
  Future<List<InternetAddress>> peers() async {
    final fetched = _fetchedAt;
    if (fetched == null || _clock().difference(fetched) >= refreshInterval) {
      await _refresh();
    }
    return _peers;
  }

  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    // Stamped before the request, not after: a daemon that is down must not
    // turn every probe round into a fresh connection attempt.
    _fetchedAt = _clock();
    try {
      final body = await _fetch(_statusUrl);
      if (body != null) _peers = parseStatus(body);
    } on Object {
      // The fetch seam is expected not to throw; if a substitute does, the
      // directory still owes its caller an answer.
    } finally {
      _fetching = false;
    }
  }

  /// Extracts peer Tailscale IPv4 addresses from a `/localapi/v0/status` body.
  ///
  /// Only `Peer` entries are read — `Self` is this machine, not a target.
  /// Peers reporting `Online: false` are skipped: probing one costs a
  /// datagram and can never be answered. Anything malformed yields an empty
  /// list rather than a partial guess, because a half-parsed directory is a
  /// directory that lies about who is out there.
  static List<InternetAddress> parseStatus(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on Object {
      return const [];
    }
    if (decoded is! Map) return const [];
    final peer = decoded['Peer'];
    if (peer is! Map) return const [];
    final addresses = <InternetAddress>[];
    final seen = <String>{};
    for (final entry in peer.values) {
      if (entry is! Map || entry['Online'] == false) continue;
      final ips = entry['TailscaleIPs'];
      if (ips is! List) continue;
      for (final raw in ips) {
        if (raw is! String) continue;
        final address = InternetAddress.tryParse(raw);
        if (address == null ||
            address.type != InternetAddressType.IPv4 ||
            !seen.add(address.address)) {
          continue;
        }
        addresses.add(address);
      }
    }
    return addresses;
  }

  /// The production fetch: one loopback GET, bounded in time and size.
  ///
  /// A client is created per call rather than held: the directory asks every
  /// half minute at most, and a held client would keep idle connections to a
  /// daemon that may not exist.
  static Future<String?> _httpGet(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      // A status document is kilobytes; anything past this is not one, and
      // reading it to the end would let a hostile or broken endpoint spend
      // memory the discovery path does not need to give it.
      return body.length > 256 * 1024 ? null : body;
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }
}

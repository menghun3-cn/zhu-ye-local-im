import 'dart:io';

import '../discovery/peer_registry.dart';
import 'link_server.dart';

/// Link-based file transfer service.
///
/// Provides temporary HTTP download links for files, allowing recipients
/// to download without installing the app. Links expire after 30 minutes.
class LinkTransfer {
  LinkTransfer._();

  static final LinkTransfer _instance = LinkTransfer._();
  static LinkTransfer get instance => _instance;

  final LinkTransferServer _server = LinkTransferServer();

  /// Whether the link transfer server is running.
  bool get isRunning => _server.isRunning;

  /// The actual port the server is listening on.
  int? get port => _server.actualPort;

  /// Starts the link transfer server.
  Future<void> start() async {
    await _server.start();
  }

  /// Stops the link transfer server.
  Future<void> stop() async {
    await _server.stop();
  }

  /// Creates a download link for a file.
  ///
  /// [peerAddresses] are passed to [shareAddressHints]-style callers as the
  /// addresses Devices were recently heard at; they steer which of this
  /// machine's interfaces the link names. Returns the full URL or null if
  /// the server is not running or the file does not exist.
  Future<String?> createLink(
    String filePath, {
    String? fileName,
    List<String> peerAddresses = const [],
  }) async {
    if (!_server.isRunning) return null;
    if (!File(filePath).existsSync()) return null;
    return _server.createLink(
      filePath,
      fileName: fileName,
      peerAddresses: peerAddresses,
    );
  }
}

/// Flattens discovered peers into the address hints a share link prefers:
/// every address each peer was heard at, freshest sightings first.
///
/// A peer reachable over both a LAN and a VPN contributes both addresses —
/// whichever link the recipient is actually on, the local address sharing
/// its prefix is the one the link can name.
List<String> shareAddressHints(Iterable<DiscoveredPeer> peers) {
  final sightings = [for (final peer in peers) ...peer.addresses]
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  return [for (final sighting in sightings) sighting.address.address];
}

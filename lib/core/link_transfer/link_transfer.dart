import 'dart:io';

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
  /// Returns the full URL or null if the server is not running or
  /// the file does not exist.
  Future<String?> createLink(String filePath, {String? fileName}) async {
    if (!_server.isRunning) return null;
    if (!File(filePath).existsSync()) return null;
    return _server.createLink(filePath, fileName: fileName);
  }
}

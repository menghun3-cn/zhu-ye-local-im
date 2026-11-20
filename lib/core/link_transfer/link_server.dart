import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'share_address.dart';

/// The port link-share downloads prefer to listen on.
///
/// A preference, not a requirement: when the operating system refuses it the
/// server falls back to any free port and the generated links name that one
/// instead, which is why diagnostics must read [LinkTransferServer.actualPort]
/// rather than assume this value.
const int defaultLinkTransferPort = 47657;

/// Temporary HTTP server for link-based file transfer.
///
/// Serves a simple web page that allows recipients to download files
/// without installing the app. Links expire after 30 minutes.
class LinkTransferServer {
  LinkTransferServer({this.preferredPort = defaultLinkTransferPort});

  final int preferredPort;
  HttpServer? _server;
  int? _actualPort;
  final Map<String, _LinkEntry> _links = {};
  final Map<String, _ShareEntry> _shares = {};
  Timer? _expiryTimer;

  /// The actual port the server is listening on.
  int? get actualPort => _actualPort;

  /// Whether the server is running.
  bool get isRunning => _server != null;

  /// Starts the server. Falls back to a random port if the preferred port is unavailable.
  Future<void> start() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
    } on SocketException {
      // Port is in use, try a random port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _actualPort = _server!.port;

    _server!.listen(_handleRequest);

    // Start expiry timer
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _cleanupExpiredLinks();
    });
  }

  /// Stops the server and cleans up resources.
  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _server?.close(force: true);
    _server = null;
    _actualPort = null;
    _links.clear();
    _shares.clear();
  }

  /// Creates a download link for a file.
  ///
  /// [peerAddresses] are the addresses Devices were recently heard at; they
  /// tell [chooseShareAddress] which of this machine's several interfaces a
  /// recipient can actually reach. Returns the full URL or null if the
  /// server is not running.
  Future<String?> createLink(
    String filePath, {
    String? fileName,
    List<String> peerAddresses = const [],
  }) async {
    if (_server == null) return null;

    final token = _generateToken();
    final name = fileName ?? filePath.split(Platform.pathSeparator).last;

    _links[token] = _LinkEntry(
      filePath: filePath,
      fileName: name,
      createdAt: DateTime.now(),
    );

    final ip = await _getLocalIp(peerAddresses);
    return 'http://$ip:$actualPort/download/$token';
  }

  /// Creates a share link covering several files at once.
  ///
  /// [files] are `(path, name)` pairs in the order the user chose them; paths
  /// that name nothing — a directory, a file that just left — are filtered
  /// out, and an empty remainder yields null rather than a page with no
  /// downloads on it. [peerAddresses] steer the address the link names, same
  /// as [createLink]. The returned URL opens a list page (`/s/<token>`)
  /// whose rows download through `/f/<token>/<index>`.
  Future<String?> createShare(
    List<({String path, String name})> files, {
    List<String> peerAddresses = const [],
  }) async {
    if (_server == null) return null;

    final existing = [
      for (final file in files)
        if (File(file.path).existsSync()) file,
    ];
    if (existing.isEmpty) return null;

    final token = _generateToken();
    _shares[token] = _ShareEntry(files: existing, createdAt: DateTime.now());

    final ip = await _getLocalIp(peerAddresses);
    return 'http://$ip:$actualPort/s/$token';
  }

  /// Handles incoming HTTP requests.
  void _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (path == '/') {
        await _serveIndex(request);
      } else if (path.startsWith('/download/')) {
        final token = path.substring('/download/'.length);
        await _serveDownload(request, token);
      } else if (path.startsWith('/info/')) {
        final token = path.substring('/info/'.length);
        await _serveInfo(request, token);
      } else if (path.startsWith('/s/')) {
        final token = path.substring('/s/'.length);
        await _serveSharePage(request, token);
      } else if (path.startsWith('/f/')) {
        await _serveShareFile(request, path.substring('/f/'.length));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (_) {
      // A handler that throws before answering — an unwritable header, a file
      // that vanished mid-check — must still close the request, or the
      // recipient's browser waits on a connection that will never answer.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // The response is already gone; nothing left to tell the client.
      }
    }
  }

  /// Serves the index page.
  Future<void> _serveIndex(HttpRequest request) async {
    final html = '''
<!DOCTYPE html>
<html>
<head>
    <title>Local Transfer - File Download</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 600px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .file-info {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 4px;
            margin: 20px 0;
        }
        .download-btn {
            display: inline-block;
            padding: 12px 24px;
            background: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 4px;
            margin-top: 20px;
        }
        .download-btn:hover {
            background: #0056b3;
        }
        .error {
            color: #dc3545;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Local Transfer</h1>
        <p>File download service</p>
        <div id="content">Loading...</div>
    </div>
    <script>
        // Extract token from URL path
        const path = window.location.pathname;
        const token = path.split('/').pop();
        
        fetch('/info/' + token)
            .then(r => r.json())
            .then(data => {
                if (data.error) {
                    document.getElementById('content').innerHTML = 
                        '<p class="error">' + data.error + '</p>';
                } else {
                    document.getElementById('content').innerHTML = 
                        '<div class="file-info">' +
                        '<p><strong>File:</strong> ' + data.fileName + '</p>' +
                        '<p><strong>Size:</strong> ' + data.size + ' bytes</p>' +
                        '<p><strong>Expires:</strong> ' + data.expiresIn + '</p>' +
                        '</div>' +
                        '<a href="/download/' + token + '" class="download-btn">Download</a>';
                }
            })
            .catch(err => {
                document.getElementById('content').innerHTML = 
                    '<p class="error">Failed to load file information</p>';
            });
    </script>
</body>
</html>
''';

    request.response.headers.contentType = ContentType.html;
    request.response.write(html);
    await request.response.close();
  }

  /// Serves file information as JSON.
  Future<void> _serveInfo(HttpRequest request, String token) async {
    final entry = _links[token];

    if (entry == null || entry.isExpired) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"error": "Link expired or not found"}');
      await request.response.close();
      return;
    }

    final file = File(entry.filePath);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"error": "File not found"}');
      await request.response.close();
      return;
    }

    final stats = await file.stat();
    final expiresIn = entry.expiresAt.difference(DateTime.now());

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'fileName': entry.fileName,
        'size': stats.size,
        'expiresIn': '${expiresIn.inMinutes} minutes',
      }),
    );
    await request.response.close();
  }

  /// Serves the file for download.
  Future<void> _serveDownload(HttpRequest request, String token) async {
    final entry = _links[token];

    if (entry == null || entry.isExpired) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Link expired or not found');
      await request.response.close();
      return;
    }

    final file = File(entry.filePath);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('File not found');
      await request.response.close();
      return;
    }

    final stats = await file.stat();
    request.response.headers.contentType = ContentType(
      'application',
      'octet-stream',
    );
    request.response.headers.contentLength = stats.size;
    request.response.headers.set(
      'Content-Disposition',
      _contentDisposition(entry.fileName),
    );

    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  /// Serves the share list page: every file in the group, each with its own
  /// download button.
  ///
  /// Rendered here rather than fetched as JSON because the recipient is a
  /// plain browser that may not have the app — and possibly not the app's
  /// locale either, which is why the page is English like the single-file
  /// index. File names go through [_escapeHtml] because they are whatever the
  /// sender's disk happened to call them.
  Future<void> _serveSharePage(HttpRequest request, String token) async {
    final entry = _shares[token];

    if (entry == null || entry.isExpired) {
      await _serveShareError(request, 'Share link expired or not found');
      return;
    }

    final rows = StringBuffer();
    for (var i = 0; i < entry.files.length; i++) {
      final file = entry.files[i];
      final size = await File(file.path)
          .stat()
          .then((stats) => stats.size)
          .catchError((_) => -1);
      final sizeText = size < 0 ? '' : ' · ${_formatSize(size)}';
      rows.write(
        '<div class="file-row">'
        '<span class="file-name">${_escapeHtml(file.name)}</span>'
        '<span class="file-size">${_escapeHtml(sizeText.trim())}</span>'
        '<a class="download-btn" href="/f/$token/$i">Download</a>'
        '</div>',
      );
    }

    final expiresIn = entry.expiresAt.difference(DateTime.now());

    final html =
        '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Local Transfer - ${entry.files.length} file(s)</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 640px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; margin-bottom: 10px; }
        .file-row {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px 0;
            border-bottom: 1px solid #eee;
        }
        .file-row:last-child { border-bottom: none; }
        .file-name {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .file-size { color: #888; font-size: 0.9em; white-space: nowrap; }
        .download-btn {
            padding: 8px 16px;
            background: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 4px;
            white-space: nowrap;
        }
        .download-btn:hover { background: #0056b3; }
        .expiry { color: #888; margin-top: 20px; font-size: 0.9em; }
        .error { color: #dc3545; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Local Transfer</h1>
        <p>${entry.files.length} file(s) shared · expires in ${expiresIn.inMinutes} minute(s)</p>
        $rows
        <p class="expiry">This page expires in ${expiresIn.inMinutes} minute(s).</p>
    </div>
</body>
</html>
''';

    request.response.headers.contentType = ContentType(
      'text',
      'html',
      charset: 'utf-8',
    );
    request.response.write(html);
    await request.response.close();
  }

  /// Serves one file out of a share group, addressed by its index in the
  /// group's file list — never by name, so non-latin-1 and duplicated names
  /// cannot break the URL.
  Future<void> _serveShareFile(HttpRequest request, String rest) async {
    final slash = rest.lastIndexOf('/');
    final token = slash < 0 ? rest : rest.substring(0, slash);
    final index = slash < 0
        ? -1
        : int.tryParse(rest.substring(slash + 1)) ?? -1;

    final entry = _shares[token];
    if (entry == null ||
        entry.isExpired ||
        index < 0 ||
        index >= entry.files.length) {
      await _serveShareError(request, 'Share link expired or not found');
      return;
    }

    final file = File(entry.files[index].path);
    if (!await file.exists()) {
      await _serveShareError(request, 'File not found');
      return;
    }

    final stats = await file.stat();
    request.response.headers.contentType = ContentType(
      'application',
      'octet-stream',
    );
    request.response.headers.contentLength = stats.size;
    request.response.headers.set(
      'Content-Disposition',
      _contentDisposition(entry.files[index].name),
    );

    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  /// Answers a share request that cannot be served, as a small HTML page —
  /// the recipient clicked a link, so a bare status line is a worse answer
  /// than a sentence.
  Future<void> _serveShareError(HttpRequest request, String message) async {
    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      '<!DOCTYPE html><html><body style="font-family:sans-serif;'
      'max-width:480px;margin:80px auto;text-align:center">'
      '<h2>Local Transfer</h2><p>${_escapeHtml(message)}</p>'
      '</body></html>',
    );
    await request.response.close();
  }

  /// Escapes the five characters that can break out of HTML text or an
  /// attribute on the share page.
  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  /// A byte count the way a person reads one: 512 B, 1.5 KB, 230 MB.
  static String _formatSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final rounded = value >= 10 || unit == 0
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return '$rounded ${units[unit]}';
  }

  /// Builds a `Content-Disposition` value that survives any file name.
  ///
  /// HTTP header values are latin-1 at best, so the real name travels in the
  /// RFC 5987 `filename*` parameter while `filename` carries an ASCII
  /// fallback. Interpolating the name raw made `headers.set` throw on any
  /// non-latin-1 name — `报告.pdf`, say — and the throw happened before the
  /// response was answered, so the recipient's browser saw a dead connection
  /// instead of a download.
  static String _contentDisposition(String fileName) {
    final fallback = String.fromCharCodes(
      fileName.runes.map(
        (rune) => rune >= 0x20 && rune <= 0x7E && rune != 0x22 && rune != 0x5C
            ? rune
            : 0x5F,
      ),
    );
    final encoded = _encodeAttrValue(fileName);
    return 'attachment; filename="${fallback.isEmpty ? 'file' : fallback}"; '
        "filename*=UTF-8''$encoded";
  }

  /// Percent-encodes [value] as UTF-8, leaving RFC 5987 attr-char bytes as-is.
  static String _encodeAttrValue(String value) {
    final out = StringBuffer();
    for (final byte in utf8.encode(value)) {
      final isAttrChar =
          (byte >= 0x30 && byte <= 0x39) || // 0-9
          (byte >= 0x41 && byte <= 0x5A) || // A-Z
          (byte >= 0x61 && byte <= 0x7A) || // a-z
          _attrChars.contains(byte);
      if (isAttrChar) {
        out.writeCharCode(byte);
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  /// The punctuation RFC 5987 allows unencoded in an attribute value.
  static const Set<int> _attrChars = {
    0x21, // !
    0x23, // #
    0x24, // $
    0x26, // &
    0x2B, // +
    0x2D, // -
    0x2E, // .
    0x5E, // ^
    0x5F, // _
    0x60, // `
    0x7C, // |
    0x7E, // ~
  };

  /// Generates a unique token for link identification.
  String _generateToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 1000000;
    return '${timestamp}_$random';
  }

  /// Gets the local IP address for the download link.
  ///
  /// The first non-loopback address is not good enough: a machine on both a
  /// router LAN and a VPN or tailnet enumerates several, and whichever comes
  /// first is as likely to be the adapter nobody else can reach. The peers'
  /// own addresses say which link the link belongs on; without them the
  /// ranking in [chooseShareAddress] prefers physical private interfaces.
  Future<String> _getLocalIp(List<String> peerAddresses) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final chosen = chooseShareAddress(
        candidates: [
          for (final interface in interfaces)
            for (final address in interface.addresses)
              if (address.type == InternetAddressType.IPv4)
                ShareAddressCandidate(
                  address: address.address,
                  interfaceName: interface.name,
                ),
        ],
        peerAddresses: peerAddresses,
      );
      if (chosen != null) return chosen;
    } catch (e) {
      // Fallback to localhost if we can't determine the IP
    }
    return 'localhost';
  }

  /// Removes expired links and shares.
  void _cleanupExpiredLinks() {
    final now = DateTime.now();
    _links.removeWhere((_, entry) => entry.isExpiredAt(now));
    _shares.removeWhere((_, entry) => entry.isExpiredAt(now));
  }
}

class _LinkEntry {
  _LinkEntry({
    required this.filePath,
    required this.fileName,
    required this.createdAt,
  });

  final String filePath;
  final String fileName;
  final DateTime createdAt;

  DateTime get expiresAt => createdAt.add(const Duration(minutes: 30));

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool isExpiredAt(DateTime time) => time.isAfter(expiresAt);
}

/// One shared group: the files a single `/s/<token>` page lists, in the
/// order the sender chose them.
class _ShareEntry {
  _ShareEntry({required this.files, required this.createdAt});

  final List<({String path, String name})> files;
  final DateTime createdAt;

  DateTime get expiresAt => createdAt.add(const Duration(minutes: 30));

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool isExpiredAt(DateTime time) => time.isAfter(expiresAt);
}

import 'dart:async';
import 'dart:io';

/// Temporary HTTP server for link-based file transfer.
///
/// Serves a simple web page that allows recipients to download files
/// without installing the app. Links expire after 30 minutes.
class LinkTransferServer {
  LinkTransferServer({this.preferredPort = 18080});

  final int preferredPort;
  HttpServer? _server;
  int? _actualPort;
  final Map<String, _LinkEntry> _links = {};
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
      _actualPort = preferredPort;
    } on SocketException {
      // Port is in use, try a random port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _actualPort = _server!.port;
    }

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
  }

  /// Creates a download link for a file.
  ///
  /// Returns the full URL or null if the server is not running.
  String? createLink(String filePath, {String? fileName}) {
    if (_server == null) return null;

    final token = _generateToken();
    final name = fileName ?? filePath.split(Platform.pathSeparator).last;

    _links[token] = _LinkEntry(
      filePath: filePath,
      fileName: name,
      createdAt: DateTime.now(),
    );

    return 'http://${_getLocalIp()}:$actualPort/download/$token';
  }

  /// Handles incoming HTTP requests.
  void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/') {
      await _serveIndex(request);
    } else if (path.startsWith('/download/')) {
      final token = path.substring('/download/'.length);
      await _serveDownload(request, token);
    } else if (path.startsWith('/info/')) {
      final token = path.substring('/info/'.length);
      await _serveInfo(request, token);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
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
    request.response.write('''{
        "fileName": "${entry.fileName}",
        "size": ${stats.size},
        "expiresIn": "${expiresIn.inMinutes} minutes"
    }''');
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

    request.response.headers.contentType = ContentType(
      'application',
      'octet-stream',
    );
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="${entry.fileName}"',
    );

    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  /// Generates a unique token for link identification.
  String _generateToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 1000000;
    return '${timestamp}_$random';
  }

  /// Gets the local IP address for the download link.
  String _getLocalIp() {
    try {
      final interfaces = NetworkInterface.listSync();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // Fallback to localhost if we can't determine the IP
    }
    return 'localhost';
  }

  /// Removes expired links.
  void _cleanupExpiredLinks() {
    final now = DateTime.now();
    _links.removeWhere((_, entry) => entry.isExpiredAt(now));
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

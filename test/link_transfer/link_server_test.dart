import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/core/link_transfer/link_server.dart';
import 'package:test/test.dart';

void main() {
  late LinkTransferServer server;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('link_server_test');
    server = LinkTransferServer(preferredPort: 0);
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await tempDir.delete(recursive: true);
  });

  /// The path portion of a link [server] produced, requested against loopback.
  Uri localUri(String link) {
    final uri = Uri.parse(link);
    return uri.replace(host: '127.0.0.1', port: server.actualPort);
  }

  Future<HttpClientResponse> get(Uri uri) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(uri);
    return request.close();
  }

  test('serves a file for download', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}hello.txt')
      ..writeAsStringSync('hello world');
    final link = await server.createLink(file.path);
    expect(link, isNotNull);

    final response = await get(localUri(link!));
    expect(response.statusCode, HttpStatus.ok);
    expect(
      response.headers.value('content-disposition'),
      contains('filename="hello.txt"'),
    );
    expect(await response.transform(utf8.decoder).join(), 'hello world');
  });

  test('downloads a file whose name is not latin-1', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}报告 final.pdf')
      ..writeAsStringSync('pdf bytes');
    final link = await server.createLink(file.path);
    expect(link, isNotNull);

    final response = await get(localUri(link!));
    expect(response.statusCode, HttpStatus.ok);
    final disposition = response.headers.value('content-disposition')!;
    // The UTF-8 name must travel in filename*; the ASCII fallback must not
    // carry characters that make the header unwritable.
    expect(disposition, contains("filename*=UTF-8''"));
    expect(disposition, isNot(contains('报告')));
    expect(await response.transform(utf8.decoder).join(), 'pdf bytes');
  });

  test('serves parseable file info', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}报告.txt')
      ..writeAsStringSync('x');
    final link = await server.createLink(file.path, fileName: '报告.txt');
    final token = Uri.parse(link!).pathSegments.last;

    final response = await get(
      Uri.parse('http://127.0.0.1:${server.actualPort}/info/$token'),
    );
    expect(response.statusCode, HttpStatus.ok);
    final body = jsonDecode(await response.transform(utf8.decoder).join());
    expect(body['fileName'], '报告.txt');
    expect(body['size'], 1);
  });

  test('answers 404 for an unknown token', () async {
    final response = await get(
      Uri.parse('http://127.0.0.1:${server.actualPort}/download/nope'),
    );
    expect(response.statusCode, HttpStatus.notFound);
  });
}

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

  group('share links', () {
    /// The `/f/` URL for file [index] of the share [link] points at.
    Uri shareFileUri(String link, int index) {
      final token = Uri.parse(link).pathSegments.last;
      return Uri.parse('http://127.0.0.1:${server.actualPort}/f/$token/$index');
    }

    test('serves a page listing every file in the share', () async {
      final first = File('${tempDir.path}${Platform.pathSeparator}a.txt')
        ..writeAsStringSync('aaa');
      final second = File('${tempDir.path}${Platform.pathSeparator}报告.pdf')
        ..writeAsStringSync('bbb');
      final link = await server.createShare([
        (path: first.path, name: 'a.txt'),
        (path: second.path, name: '报告.pdf'),
      ]);
      expect(link, isNotNull);
      expect(Uri.parse(link!).path, startsWith('/s/'));

      final response = await get(localUri(link));
      expect(response.statusCode, HttpStatus.ok);
      final body = await response.transform(utf8.decoder).join();
      expect(body, contains('a.txt'));
      expect(body, contains('报告.pdf'));
      expect(body, contains('/f/'));
    });

    test('downloads each file by its index in the share', () async {
      final first = File('${tempDir.path}${Platform.pathSeparator}one.bin')
        ..writeAsBytesSync([1, 2, 3]);
      final second = File('${tempDir.path}${Platform.pathSeparator}two.bin')
        ..writeAsBytesSync([4, 5, 6]);
      final link = await server.createShare([
        (path: first.path, name: 'one.bin'),
        (path: second.path, name: '报告 final.pdf'),
      ]);
      expect(link, isNotNull);

      final response = await get(shareFileUri(link!, 1));
      expect(response.statusCode, HttpStatus.ok);
      expect(
        response.headers.value('content-disposition'),
        contains('attachment'),
      );
      expect(
        response.headers.value('content-disposition'),
        contains("filename*=UTF-8''"),
      );
      expect(await response.expand((chunk) => chunk).toList(), [4, 5, 6]);
    });

    test('filters out paths that name nothing', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}real.txt')
        ..writeAsStringSync('x');
      // A directory has a path but nothing the share page can serve.
      final link = await server.createShare([
        (path: tempDir.path, name: 'a-folder'),
        (path: file.path, name: 'real.txt'),
        (
          path: '${tempDir.path}${Platform.pathSeparator}gone.txt',
          name: 'gone',
        ),
      ]);
      expect(link, isNotNull);

      final response = await get(localUri(link!));
      final body = await response.transform(utf8.decoder).join();
      expect(body, contains('real.txt'));
      expect(body, isNot(contains('a-folder')));
      expect(body, isNot(contains('gone.txt')));
    });

    test('answers null when nothing shareable was handed in', () async {
      expect(
        await server.createShare([(path: tempDir.path, name: 'a-folder')]),
        isNull,
      );
      expect(await server.createShare(const []), isNull);
    });

    test('answers 404 for an unknown share token or index', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}a.txt')
        ..writeAsStringSync('x');
      final link = await server.createShare([(path: file.path, name: 'a.txt')]);
      expect(link, isNotNull);

      expect(
        (await get(Uri.parse('http://127.0.0.1:${server.actualPort}/s/nope')))
            .statusCode,
        HttpStatus.notFound,
      );
      // The share has exactly one file: index 1 is out of range, and a
      // non-numeric tail is not an index at all.
      expect(
        (await get(shareFileUri(link!, 1))).statusCode,
        HttpStatus.notFound,
      );
      final token = Uri.parse(link).pathSegments.last;
      expect(
        (await get(
          Uri.parse('http://127.0.0.1:${server.actualPort}/f/$token/abc'),
        )).statusCode,
        HttpStatus.notFound,
      );
    });
  });
}

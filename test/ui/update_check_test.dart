import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/ui/update_check.dart';
import 'package:test/test.dart';

/// Reading a release out of the API's answer.
///
/// The four outcomes and the list of files, against the shape GitHub really
/// answers with — cut down to the fields this reads, and keeping the two a
/// download rests on: the address to fetch and the digest to check it against.
void main() {
  /// Stands for "this test did not say", which is not the same as "this test
  /// said null".
  const Object unset = Object();

  const page =
      'https://github.com/menghun3-cn/zhu-ye-local-im/releases/tag/v9.9.9';

  /// An asset as the API spells one.
  Map<String, Object?> asset(
    String name, {
    String? digest = 'sha256:abc123',
    int size = 1024,
  }) => {
    'name': name,
    'browser_download_url': 'https://example.test/$name',
    'size': size,
    'digest': digest,
  };

  /// A release as the API spells one.
  ///
  /// [assets] defaults to one file rather than to null, and the difference
  /// matters: "the answer carries no assets key" and "the answer carries one
  /// this cannot read" are two of the cases below.
  Map<String, Object?> release({
    Object? tag = 'v9.9.9',
    Object? assets = unset,
    Object? htmlUrl = page,
  }) => {
    'tag_name': ?tag,
    'html_url': ?htmlUrl,
    'assets': identical(assets, unset)
        ? [asset('LocalTransfer-9.9.9-windows-x64-portable.zip')]
        : assets,
  };

  UpdateCheck parse(Object? decoded) => parseRelease(
    decoded,
    currentVersion: '0.1.1',
    fallbackUrl: updateReleasesPage,
  );

  group('parseRelease', () {
    test('reads a newer release, and the files it carries', () {
      final check = parse(
        release(
          assets: [
            asset('LocalTransfer-9.9.9-android.apk', digest: null, size: 7),
            asset('LocalTransfer-9.9.9-windows-x64-setup.exe'),
          ],
        ),
      );

      expect(check.outcome, UpdateOutcome.available);
      expect(check.version, 'v9.9.9');
      expect(check.url, page);
      expect(check.assets.map((asset) => asset.name), [
        'LocalTransfer-9.9.9-android.apk',
        'LocalTransfer-9.9.9-windows-x64-setup.exe',
      ]);
      expect(
        check.assets.first.url,
        'https://example.test/LocalTransfer-9.9.9-android.apk',
      );
      expect(check.assets.first.size, 7);
      expect(check.assets.last.sha256, 'abc123');
    });

    test('is up to date when the tag is the version running', () {
      // The `v` is the tag's, not the version's: comparing them without
      // stripping it would make every release look newer than 0.1.1.
      expect(parse(release(tag: 'v0.1.1')).outcome, UpdateOutcome.upToDate);
      expect(parse(release(tag: '0.1.1')).outcome, UpdateOutcome.upToDate);
    });

    test('has nothing to compare against when no tag came back', () {
      expect(parse(release(tag: null)).outcome, UpdateOutcome.noRelease);
      expect(parse(release(tag: '')).outcome, UpdateOutcome.noRelease);
      expect(parse(release(tag: 7)).outcome, UpdateOutcome.noRelease);
    });

    test('could not be asked when the body is not a release', () {
      expect(parse('not a release').outcome, UpdateOutcome.unreachable);
      expect(parse(null).outcome, UpdateOutcome.unreachable);
    });

    test('falls back to the releases page when the answer names none', () {
      expect(parse(release(htmlUrl: null)).url, updateReleasesPage);
      expect(parse(release(htmlUrl: '')).url, updateReleasesPage);
    });

    test('drops files that could not be downloaded', () {
      final check = parse(
        release(
          assets: [
            {'name': 'no address'},
            {'browser_download_url': 'https://example.test/no-name'},
            {'name': '', 'browser_download_url': 'https://example.test/empty'},
            asset('kept.zip'),
          ],
        ),
      );

      expect(check.assets.map((asset) => asset.name), ['kept.zip']);
    });

    test('has no files when the answer carries none it can read', () {
      expect(parse(release(assets: 'nonsense')).assets, isEmpty);
      expect(parse(release(assets: null)).assets, isEmpty);
    });
  });

  group('UpdateAsset.sha256', () {
    test('is bare lowercase hex', () {
      const digest = 'sha256:AB01CD';
      expect(
        const UpdateAsset(name: 'a', url: 'u', size: 1, digest: digest).sha256,
        'ab01cd',
      );
    });

    test('is null when the release published none', () {
      expect(const UpdateAsset(name: 'a', url: 'u', size: 1).sha256, isNull);
      expect(
        const UpdateAsset(name: 'a', url: 'u', size: 1, digest: '').sha256,
        isNull,
      );
    });
  });

  group('GitHubUpdateChecker', () {
    test('asks the host it was given, and reads what comes back', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final asked = <String>[];
      server.listen((request) {
        asked.add(request.uri.path);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(release()));
        request.response.close();
      });

      final answer = await GitHubUpdateChecker(
        repository: 'menghun3-cn/zhu-ye-local-im',
        apiHost: 'http://127.0.0.1:${server.port}',
      ).latest();

      expect(asked, ['/repos/menghun3-cn/zhu-ye-local-im/releases/latest']);
      expect(answer.outcome, UpdateOutcome.available);
      expect(answer.assets.single.sha256, 'abc123');
    });

    test('reads a 404 as nothing published rather than as a failure', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      });

      final answer = await GitHubUpdateChecker(
        apiHost: 'http://127.0.0.1:${server.port}',
      ).latest();

      expect(answer.outcome, UpdateOutcome.noRelease);
    });

    test(
      'reads anything else as a question that did not get through',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.close();
        });

        final answer = await GitHubUpdateChecker(
          apiHost: 'http://127.0.0.1:${server.port}',
        ).latest();

        expect(answer.outcome, UpdateOutcome.unreachable);
      },
    );

    test('ships pointed at GitHub', () {
      // A guard rather than a fact anybody needs: pointing the real host
      // somewhere else is how this file's own tests would be written, and a
      // build that shipped pointed at a test server would answer every user's
      // "is there a newer version" with the truth about a machine that is not
      // theirs.
      expect(updateApiHost, 'https://api.github.com');
      expect(updateRepository, 'menghun3-cn/zhu-ye-local-im');
    });
  });
}

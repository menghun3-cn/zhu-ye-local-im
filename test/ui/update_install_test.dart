import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:local_transfer/app/app_version.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/update_install.dart';
import 'package:test/test.dart';

/// Fetching a build and putting it where the running one is.
///
/// Everything here that touches a disk touches a folder of its own under the
/// system's temporary directory, and everything that would replace *this* build
/// is left to the seam: what is under test is the machinery — which file a
/// release's list holds for this shape of copy, where a fetched package lands,
/// what the folder looks like half-way through a replacement, and what happens
/// to it when one fails.
void main() {
  /// [relative] under [root], with this platform's separator.
  String pathUnder(String root, String relative) =>
      '$root${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}';

  /// A folder that cleans up after itself.
  Directory folder(String prefix) {
    final directory = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    return directory;
  }

  /// Writes [files] — relative path to contents — under [root].
  Directory tree(String prefix, Map<String, String> files) {
    final root = folder(prefix);
    for (final entry in files.entries) {
      final file = File(pathUnder(root.path, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    return root;
  }

  /// A build, as much of one as [isAPackage] asks about.
  Map<String, String> packageFiles() => {
    'local_transfer.exe': 'the new executable',
    'flutter_windows.dll': 'the engine',
    'data/app.so': 'the new Dart code',
    'data/flutter_assets/AssetManifest.json': '{}',
  };

  /// The two files a release carries, one of them the same file under a fixed
  /// name.
  UpdateCheck releaseWith({List<UpdateAsset>? assets}) => UpdateCheck(
    UpdateOutcome.available,
    version: 'v9.9.9',
    assets:
        assets ??
        const [
          UpdateAsset(
            name: 'LocalTransfer-9.9.9-windows-x64-portable.zip',
            url: 'https://example.test/portable.zip',
            size: 10,
            digest: 'sha256:aa',
          ),
          UpdateAsset(
            name: 'LocalTransfer-latest-windows-x64-portable.zip',
            url: 'https://example.test/latest.zip',
            size: 10,
            digest: 'sha256:aa',
          ),
          UpdateAsset(
            name: 'LocalTransfer-9.9.9-android.apk',
            url: 'https://example.test/android.apk',
            size: 10,
            digest: 'sha256:aa',
          ),
        ],
  );

  group('which file to fetch', () {
    test('is named after the version the release is tagged with', () {
      expect(
        updateAssetName(tag: 'v0.1.2', payload: UpdatePayload.portablePackage),
        'LocalTransfer-0.1.2-windows-x64-portable.zip',
      );
      expect(
        updateAssetName(tag: 'v0.1.2', payload: UpdatePayload.installer),
        'LocalTransfer-0.1.2-windows-x64-setup.exe',
      );
      // A tag without the `v` is a tag all the same.
      expect(
        updateAssetName(tag: '0.1.2', payload: UpdatePayload.installer),
        'LocalTransfer-0.1.2-windows-x64-setup.exe',
      );
      expect(
        updateAssetName(tag: 'v0.1.2', payload: UpdatePayload.androidPackage),
        'LocalTransfer-0.1.2-android.apk',
      );
    });

    test('is the versioned one, never the fixed name beside it', () {
      // Both names end in the same suffix, so a release that is matched by
      // suffix picks whichever the API listed first — and one of the two is an
      // alias whose whole point is that it does not say which build it is.
      final asset = updateAssetFor(
        releaseWith(),
        UpdatePayload.portablePackage,
      );
      expect(asset?.name, 'LocalTransfer-9.9.9-windows-x64-portable.zip');
    });

    test('is nothing when the release does not carry it', () {
      final installedOnly = releaseWith(
        assets: const [
          UpdateAsset(
            name: 'LocalTransfer-9.9.9-windows-x64-setup.exe',
            url: 'https://example.test/setup.exe',
            size: 10,
          ),
        ],
      );
      expect(
        updateAssetFor(installedOnly, UpdatePayload.portablePackage),
        isNull,
      );
      expect(
        updateAssetFor(installedOnly, UpdatePayload.installer)?.url,
        'https://example.test/setup.exe',
      );
    });

    test('is nothing when the answer named no version', () {
      expect(
        updateAssetFor(
          const UpdateCheck(UpdateOutcome.upToDate),
          UpdatePayload.portablePackage,
        ),
        isNull,
      );
    });
  });

  group('stagedFiles', () {
    test('is every file under the folder, relative and sorted', () {
      final staged = tree('lt_staged_', {
        'b.txt': 'b',
        'local_transfer.exe': 'exe',
        'data/app.so': 'so',
      });

      expect(stagedFiles(staged), [
        'b.txt',
        'data/app.so',
        'local_transfer.exe',
      ]);
    });

    test('leaves out what a rename that did not happen left behind', () {
      final staged = tree('lt_staged_', {
        'local_transfer.exe': 'exe',
        'local_transfer.exe.ltnew': 'half of a copy',
      });

      expect(stagedFiles(staged), ['local_transfer.exe']);
    });
  });

  group('isAPackage', () {
    test('is true for something that could run', () {
      expect(isAPackage(tree('lt_pkg_', packageFiles())), isTrue);
    });

    test('is false when a piece of it is missing', () {
      final noDart = packageFiles()..remove('data/app.so');
      expect(isAPackage(tree('lt_pkg_', noDart)), isFalse);
      expect(
        isAPackage(tree('lt_pkg_', {'local_transfer.exe': 'exe'})),
        isFalse,
      );
      expect(isAPackage(folder('lt_pkg_')), isFalse);
    });

    test('is false when the assets arrived empty', () {
      final staged = tree('lt_pkg_', packageFiles());
      Directory(pathUnder(staged.path, 'data/flutter_assets'))
        ..deleteSync(recursive: true)
        ..createSync();
      expect(isAPackage(staged), isFalse);
    });
  });

  group('dropStagedTree', () {
    test('puts every file where it belongs, replacing what was there', () {
      final staged = tree('lt_staged_', packageFiles());
      final target = tree('lt_target_', {
        'local_transfer.exe': 'the old executable',
        'left_alone.txt': 'mine',
      });

      dropStagedTree(staged: staged, target: target);

      expect(
        File(pathUnder(target.path, 'local_transfer.exe')).readAsStringSync(),
        'the new executable',
      );
      expect(
        File(pathUnder(target.path, 'data/app.so')).readAsStringSync(),
        'the new Dart code',
      );
      // Anything the new build does not carry is not this code's business.
      expect(
        File(pathUnder(target.path, 'left_alone.txt')).readAsStringSync(),
        'mine',
      );
      // And nothing is left under the suffix it was dropped in with.
      expect(
        stagedFiles(target).where((path) => path.endsWith(droppedInSuffix)),
        isEmpty,
      );
    });

    test('leaves the folder untouched when the copy runs out of room', () {
      final staged = tree('lt_staged_', {'a.txt': 'new a', 'b.txt': 'new b'});
      final target = tree('lt_target_', {'a.txt': 'old a'});
      // The second file cannot be written: something is already sitting on the
      // name it would be dropped under. (A full disk is the honest version of
      // this, and not one a test can arrange.)
      Directory(pathUnder(target.path, 'b.txt$droppedInSuffix')).createSync();

      expect(
        () => dropStagedTree(staged: staged, target: target),
        throwsA(isA<FileSystemException>()),
      );

      // Nothing was renamed into place, so the build that is there now is
      // whole — which is the whole reason for dropping bytes before moving any.
      expect(File(pathUnder(target.path, 'a.txt')).readAsStringSync(), 'old a');
      expect(
        File(pathUnder(target.path, 'a.txt$droppedInSuffix')).existsSync(),
        isFalse,
      );
      expect(File(pathUnder(target.path, 'b.txt')).existsSync(), isFalse);
    });
  });

  group('UpdateHandoff', () {
    test('is read off the command line', () {
      final handoff = UpdateHandoff.parse([
        '--apply-update',
        '--staged',
        r'C:\temp\lt\stage',
        '--target',
        r'D:\apps\LocalTransfer',
      ]);

      expect(handoff?.staged, r'C:\temp\lt\stage');
      expect(handoff?.target, r'D:\apps\LocalTransfer');
    });

    test('is nothing at all for an ordinary start', () {
      expect(UpdateHandoff.parse(const []), isNull);
      expect(
        UpdateHandoff.parse(const ['--staged', 'x', '--target', 'y']),
        isNull,
      );
    });

    test('is still a hand-over when the folders are missing', () {
      // The one reading that cannot be right is "an ordinary start": a build
      // that was started this way is running from a folder that is being
      // replaced under it.
      final handoff = UpdateHandoff.parse(const ['--apply-update']);
      expect(handoff, isNotNull);
      expect(handoff?.staged, isEmpty);
    });

    test('puts the folder in place and names what to start', () {
      final staged = tree('lt_staged_', packageFiles());
      final target = tree('lt_target_', {
        'local_transfer.exe': 'the old executable',
        'data/app.so': 'the old Dart code',
      });

      final executable = UpdateHandoff(
        staged: staged.path,
        target: target.path,
      ).putInPlace();

      expect(executable, pathUnder(target.path, 'local_transfer.exe'));
      expect(File(executable).readAsStringSync(), 'the new executable');
      expect(
        File(pathUnder(target.path, 'data/app.so')).readAsStringSync(),
        'the new Dart code',
      );
    });

    test('refuses a hand-over with nowhere to put anything', () {
      expect(
        () => const UpdateHandoff(staged: '', target: '').putInPlace(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => UpdateHandoff(staged: 'nowhere', target: 'nowhere').putInPlace(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('startDetached waits for the process to start before returning', () async {
      // The hand-over window exits the moment startDetached answers. A
      // fire-and-forget start would let the old build vanish while nobody had
      // created the new one yet, so the failure to start has to surface here
      // rather than be lost in an unawaited future.
      await expectLater(
        startDetached(
          'definitely-not-a-real-executable-${DateTime.now().microsecondsSinceEpoch}',
        ),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('the report a hand-over leaves', () {
    test('is read once and taken away', () {
      final report = File(
        pathUnder(folder('lt_report_').path, handoverReportName),
      );
      expect(readHandoverReport(report), isNull);

      writeHandoverReport(report, 'the folder was busy');

      expect(report.existsSync(), isTrue);
      expect(readHandoverReport(report), UpdateInstallFailure.handover);
      expect(
        report.existsSync(),
        isFalse,
        reason: 'a line about a failure already dealt with must not stay',
      );
      expect(readHandoverReport(report), isNull);
    });

    test('says what went wrong in the file itself', () {
      final report = File(
        pathUnder(folder('lt_report_').path, handoverReportName),
      );
      writeHandoverReport(report, StateError('something specific'));
      expect(report.readAsStringSync(), contains('something specific'));
    });
  });

  group('clearStaleUpdateStages', () {
    /// A folder directly under the system's temporary directory, which is where
    /// a hand-over puts one.
    Directory stage(String name) {
      final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$name',
      )..createSync();
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      return directory;
    }

    test('leaves anything too recent to be finished with alone', () {
      final stale = stage(
        'local_transfer_update_${DateTime.now().microsecondsSinceEpoch}',
      );
      File(pathUnder(stale.path, 'local_transfer.exe')).writeAsStringSync('x');

      // A cutoff before every one of these folders was made: the scan is over
      // the real temporary directory, and [now] is the only thing standing
      // between a hand-over that is still running and its own folder.
      clearStaleUpdateStages(olderThan: Duration.zero, now: DateTime(2000));

      expect(stale.existsSync(), isTrue);
    });

    test('takes away an old stage, and only a stage', () {
      final stale = stage(
        'local_transfer_update_${DateTime.now().microsecondsSinceEpoch}',
      );
      File(pathUnder(stale.path, 'local_transfer.exe')).writeAsStringSync('x');
      final unrelated = stage(
        'lt_not_a_stage_${DateTime.now().microsecondsSinceEpoch}',
      );

      clearStaleUpdateStages(
        olderThan: Duration.zero,
        now: DateTime.now().add(const Duration(minutes: 1)),
      );

      expect(stale.existsSync(), isFalse);
      expect(unrelated.existsSync(), isTrue);
    });
  });

  group('which address the file comes from', () {
    /// One file, reachable at whichever of the two addresses [apiUrl] says.
    UpdateAsset file({
      String? apiUrl,
      String url = 'https://github.test/portable.zip',
    }) => UpdateAsset(
      name: 'LocalTransfer-9.9.9-windows-x64-portable.zip',
      url: url,
      apiUrl: apiUrl,
      size: 10,
      digest: 'sha256:aa',
    );

    test('is the release API first, then the download address', () {
      // The order is the point. The API's host is the one this copy has already
      // reached in order to be holding this answer at all; the download address
      // is on `github.com`, which is the host a filtered network is likelier to
      // refuse. Neither is written off, and the one already proven reachable
      // goes first.
      expect(downloadAddresses(file(apiUrl: 'https://api.github.test/1')), [
        'https://api.github.test/1',
        'https://github.test/portable.zip',
      ]);
    });

    test('is the download address alone when the answer named no other', () {
      expect(downloadAddresses(file()), ['https://github.test/portable.zip']);
    });

    test('names an address once, even when both fields agree', () {
      expect(
        downloadAddresses(file(apiUrl: 'https://github.test/portable.zip')),
        ['https://github.test/portable.zip'],
      );
    });
  });

  group('fetching the file', () {
    /// What the release says the file weighs, and what a server that answers
    /// with it has to send. Short enough to write out.
    const fileSize = 12;
    const fileBody = 'not the file';

    /// A release carrying the one file this shape of copy needs, at the two
    /// addresses [apiUrl] and [url].
    UpdateCheck releaseAt({
      String? apiUrl,
      required String url,
      String digest = 'sha256:aa',
    }) => UpdateCheck(
      UpdateOutcome.available,
      version: 'v9.9.9',
      assets: [
        UpdateAsset(
          name: 'LocalTransfer-9.9.9-windows-x64-portable.zip',
          url: url,
          apiUrl: apiUrl,
          // A digest nothing can match by default, so that every test here
          // stops at the checksum: what is under test is which address
          // delivered the bytes, and a matching digest would carry on into
          // unpacking and replacing the folder this suite is running from.
          size: fileSize,
          digest: digest,
        ),
      ],
    );

    /// A server answering on every path, recording the paths it was asked for.
    ///
    /// Bound to a loopback port the operating system picks, so several of these
    /// run in one suite without fighting over an address.
    Future<(HttpServer, List<String>)> server(
      void Function(HttpRequest request) answer,
    ) async {
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final asked = <String>[];
      addTearDown(() => bound.close(force: true));
      bound.listen((request) {
        asked.add(request.uri.path);
        answer(request);
        request.response.close();
      });
      return (bound, asked);
    }

    /// What an attempt ended as, remembering to take the folders away after it.
    ///
    /// The application folder is one of its own under the system's temporary
    /// directory: the real installer fetches into the folder it runs from, and
    /// a test that ran it unwired would be fetching into the folder the suite
    /// itself runs from.
    Future<UpdatePrepareResult> attempt(
      UpdateCheck release, {
      required Directory root,
    }) async {
      addTearDown(() => clearStaleUpdateStages(olderThan: Duration.zero));
      return PlatformUpdateInstaller(application: root.path)
          .prepare(release, onProgress: (progress) {});
    }

    test(
      'falls through to the second address when the first refuses',
      () async {
        // Windows is the only platform whose packaging this installer knows, so
        // it is the only one where there is a download to test at all.
        if (!Platform.isWindows) return;
        final (bound, asked) = await server((request) {
          if (request.uri.path == '/api') {
            request.response.statusCode = HttpStatus.badGateway;
            return;
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..write(fileBody);
        });
        final port = bound.port;
        final root = folder('lt_app_');

        final result = await attempt(
          releaseAt(
            apiUrl: 'http://127.0.0.1:$port/api',
            url: 'http://127.0.0.1:$port/download',
          ),
          root: root,
        );

        expect(asked, ['/api', '/download']);
        // The bytes arrived and were then thrown away for not being what the
        // release published — which is the proof that the *second* address was
        // the one that delivered them.
        expect(result.failure, UpdateInstallFailure.checksum);
      },
    );

    test('falls through when the first answers with the wrong file', () async {
      // A refusal is the loud case. The quiet one is a 200 carrying something
      // that is not this file — an interception with a page of its own — which
      // is why the byte count the release published is checked before the
      // checksum is: without it, one wrong answer would end the attempt and the
      // other address would never be asked.
      if (!Platform.isWindows) return;
      final (bound, asked) = await server((request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(request.uri.path == '/api' ? 'no' : fileBody);
      });
      final port = bound.port;
      final root = folder('lt_app_');

      final result = await attempt(
        releaseAt(
          apiUrl: 'http://127.0.0.1:$port/api',
          url: 'http://127.0.0.1:$port/download',
        ),
        root: root,
      );

      expect(asked, ['/api', '/download']);
      expect(result.failure, UpdateInstallFailure.checksum);
    });

    test(
      'says the download did not arrive once both addresses have failed',
      () async {
        if (!Platform.isWindows) return;
        final (bound, asked) = await server((request) {
          request.response.statusCode = HttpStatus.badGateway;
        });
        final port = bound.port;
        final root = folder('lt_app_');

        final result = await attempt(
          releaseAt(
            apiUrl: 'http://127.0.0.1:$port/api',
            url: 'http://127.0.0.1:$port/download',
          ),
          root: root,
        );

        // Both were tried, and the answer is the one the user can act on.
        expect(asked, ['/api', '/download']);
        expect(result.failure, UpdateInstallFailure.download);
      },
    );

    test('does not fetch a package that is already there', () async {
      // What a cancelled attempt leaves behind: the package in the update
      // folder, correct and checked. Fetching it again would be twenty
      // megabytes for a file that is already the right one.
      if (!Platform.isWindows) return;
      final (bound, asked) = await server((request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(fileBody);
      });
      final port = bound.port;
      final root = folder('lt_app_');
      final update = updateDirectory(root.path);
      final wanted = 'LocalTransfer-9.9.9-windows-x64-portable.zip';
      File(pathUnder(update.path, wanted)).writeAsStringSync(fileBody);
      // Last week's, which the attempt supersedes the moment it is asked for.
      File(
        pathUnder(update.path, 'LocalTransfer-0.0.9-windows-x64-portable.zip'),
      ).writeAsStringSync('last week');

      final result = await attempt(
        releaseAt(
          apiUrl: 'http://127.0.0.1:$port/api',
          url: 'http://127.0.0.1:$port/download',
          digest: 'sha256:${sha256.convert(utf8.encode(fileBody))}',
        ),
        root: root,
      );

      expect(asked, isEmpty, reason: 'the right bytes were already there');
      // One package at a time, and the one that was there stays: what failed
      // was the unpacking of a file that is not a zip, not the package.
      expect(result.failure, UpdateInstallFailure.unpack);
      expect(
        File(pathUnder(update.path, wanted)).existsSync(),
        isTrue,
        reason: 'a retry starts from it rather than from the network',
      );
      expect(
        File(
          pathUnder(
            update.path,
            'LocalTransfer-0.0.9-windows-x64-portable.zip',
          ),
        ).existsSync(),
        isFalse,
      );
    });
  });

  group('PlatformUpdateInstaller', () {
    test('knows the packaging of both supported platforms', () {
      expect(
        const PlatformUpdateInstaller(platform: UpdateInstallPlatform.windows)
            .supported,
        isTrue,
      );
      expect(
        const PlatformUpdateInstaller(platform: UpdateInstallPlatform.android)
            .supported,
        isTrue,
      );
      expect(
        const PlatformUpdateInstaller(platform: UpdateInstallPlatform.other)
            .supported,
        isFalse,
      );
    });

    test('does nothing at all on a platform that cannot', () async {
      final result = await PlatformUpdateInstaller(
        application: folder('lt_app_').path,
        platform: UpdateInstallPlatform.other,
      ).prepare(releaseWith(), onProgress: (progress) {});
      expect(result.failure, UpdateInstallFailure.unsupported);
    });

    test('fetches an Android APK and hands it to the installer', () async {
      final root = folder('lt_android_');
      const body = 'checked APK bytes';
      final update = updateDirectory(root.path);
      final apk = File(
        pathUnder(update.path, 'LocalTransfer-9.9.9-android.apk'),
      )..writeAsStringSync(body);
      final release = UpdateCheck(
        UpdateOutcome.available,
        version: 'v9.9.9',
        assets: [
          UpdateAsset(
            name: 'LocalTransfer-9.9.9-android.apk',
            url: 'https://example.test/android.apk',
            size: body.length,
            digest: 'sha256:${sha256.convert(utf8.encode(body))}',
          ),
        ],
      );
      final stages = <UpdateInstallStage>[];
      String? handedToInstaller;
      var left = false;
      final installer = PlatformUpdateInstaller(
        application: root.path,
        platform: UpdateInstallPlatform.android,
        leave: () => left = true,
        androidInstall: (path) async {
          handedToInstaller = path;
          return AndroidInstallOutcome.started;
        },
      );

      final result = await installer.prepare(
        release,
        onProgress: (progress) => stages.add(progress.stage),
      );

      expect(result.prepared?.payload, UpdatePayload.androidPackage);
      expect(result.prepared?.package, apk.path);
      expect(stages, [
        UpdateInstallStage.downloading,
        UpdateInstallStage.verifying,
      ]);

      await installer.apply(
        result.prepared!,
        onProgress: (progress) => stages.add(progress.stage),
      );

      expect(handedToInstaller, apk.path);
      expect(stages.last, UpdateInstallStage.installing);
      expect(
        left,
        isFalse,
        reason: 'Android opens its installer and this process keeps running',
      );
    });

    test('reports the two Android hand-off failures separately', () async {
      const prepared = PreparedUpdate.android('/tmp/update.apk');
      final permission = PlatformUpdateInstaller(
        platform: UpdateInstallPlatform.android,
        androidInstall: (_) async => AndroidInstallOutcome.permission,
      );
      final missing = const PlatformUpdateInstaller(
        platform: UpdateInstallPlatform.android,
      );

      await expectLater(
        permission.apply(prepared, onProgress: (_) {}),
        throwsA(
          isA<UpdateInstallException>().having(
            (error) => error.failure,
            'failure',
            UpdateInstallFailure.permission,
          ),
        ),
      );
      await expectLater(
        missing.apply(prepared, onProgress: (_) {}),
        throwsA(
          isA<UpdateInstallException>().having(
            (error) => error.failure,
            'failure',
            UpdateInstallFailure.installer,
          ),
        ),
      );
    });
  });

  group('the update folder', () {
    test('is under the application, called update', () {
      final root = folder('lt_app_');
      expect(
        updateDirectory(root.path).path,
        pathUnder(root.path, 'update'),
        reason: 'beside the build, not in its root and not in the temp',
      );
    });

    test('is made when it is not there', () {
      final root = folder('lt_app_');
      expect(Directory(pathUnder(root.path, 'update')).existsSync(), isFalse);
      updateDirectory(root.path);
      expect(Directory(pathUnder(root.path, 'update')).existsSync(), isTrue);
    });
  });

  group('clearFetchedUpdate', () {
    /// The update folder under [root], with [files] written into it.
    Directory updateWith(String prefix, Map<String, String> files) {
      final root = folder(prefix);
      final update = updateDirectory(root.path);
      for (final entry in files.entries) {
        File(pathUnder(update.path, entry.key)).writeAsStringSync(entry.value);
      }
      return root;
    }

    test('takes away the package of the version that is running', () {
      // The only trace that says an update happened is the name: this build is
      // the one that package carried, and it is twenty megabytes of nothing.
      final root = updateWith('lt_app_', {
        updateAssetName(
          tag: 'v$appVersion',
          payload: UpdatePayload.portablePackage,
        ): 'the package that was just installed',
        updateAssetName(
          tag: 'v$appVersion',
          payload: UpdatePayload.androidPackage,
        ): 'the APK that was just installed',
      });

      clearFetchedUpdate(root: root.path);

      expect(
        File(
          pathUnder(
            root.path,
            'update/${updateAssetName(tag: 'v$appVersion', payload: UpdatePayload.portablePackage)}',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          pathUnder(
            root.path,
            'update/${updateAssetName(tag: 'v$appVersion', payload: UpdatePayload.androidPackage)}',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('leaves a package for any other version where it is', () {
      // A cancelled or failed update: the package is what a retry starts from.
      final root = updateWith('lt_app_', {
        'LocalTransfer-9.9.9-windows-x64-portable.zip': 'a cancelled update',
      });

      clearFetchedUpdate(root: root.path);

      expect(
        File(
          pathUnder(
            root.path,
            'update/LocalTransfer-9.9.9-windows-x64-portable.zip',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('is nothing at all when the folder is not there', () {
      // The ordinary state of every build that has never updated itself.
      clearFetchedUpdate(root: folder('lt_app_').path);
    });
  });
}

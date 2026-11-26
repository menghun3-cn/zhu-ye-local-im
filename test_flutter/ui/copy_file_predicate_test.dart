import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/transfer_actions.dart';

/// The predicate behind the 复制文件 line, exercised without a widget tree.
///
/// `canCopyFile` is the whole contract for when the line may appear: a file
/// message, exactly one name, and a `localPath` that is a real file rather
/// than a directory or a path that is gone. The cases that must answer no —
/// a folder send whose path is the directory, a multi-item send, an image —
/// are the ones a menu built on `localPath != null` alone would get wrong.
void main() {
  final peer = Fingerprint.ofPublicKey(const [7, 8, 9]);

  TransferView view({
    PayloadKind kind = PayloadKind.file,
    List<String> names = const ['report.bin'],
    String? localPath,
  }) => TransferView(
    id: 't1',
    direction: TransferDirection.incoming,
    kind: kind,
    peer: peer,
    at: DateTime.utc(2026, 11, 26),
    state: TransferState.completed,
    transferredBytes: 1,
    totalBytes: 1,
    names: names,
    text: null,
    offer: null,
    localPath: localPath,
  );

  late Directory home;
  setUp(() {
    home = Directory.systemTemp.createTempSync('copy-file-predicate-');
  });
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  String file(String name) {
    final path = '${home.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync([1, 2, 3]);
    return path;
  }

  test('a single landed file offers the line', () {
    expect(canCopyFile(view(localPath: file('report.bin'))), isTrue);
  });

  test('a path that is a directory does not — the folder send case', () {
    expect(canCopyFile(view(localPath: home.path)), isFalse);
  });

  test('more than one name does not', () {
    expect(
      canCopyFile(
        view(names: const ['a.bin', 'b.bin'], localPath: file('a.bin')),
      ),
      isFalse,
    );
  });

  test('a picture does not — it has its own copy line', () {
    expect(
      canCopyFile(view(kind: PayloadKind.image, localPath: file('a.png'))),
      isFalse,
    );
  });

  test('no path, or a path that is gone, does not', () {
    expect(canCopyFile(view()), isFalse);
    expect(
      canCopyFile(
        view(localPath: '${home.path}${Platform.pathSeparator}gone.bin'),
      ),
      isFalse,
    );
  });
}

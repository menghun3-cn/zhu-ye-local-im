import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String keyPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_secret_box_test');
    keyPath = '${tempDir.path}/secrets.key';
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('seal/open round-trips and is not plaintext', () async {
    final box = await SecretBox.open(keyPath);
    final sealed = await box.seal('sk-super-secret');
    expect(sealed, startsWith('v1:'));
    expect(sealed, isNot(contains('sk-super-secret')));
    expect(await box.unseal(sealed), 'sk-super-secret');
  });

  test('unseal passes plaintext through for pre-encryption files', () async {
    final box = await SecretBox.open(keyPath);
    expect(await box.unseal('sk-plain'), 'sk-plain');
  });

  test('the key file persists across opens', () async {
    final first = await SecretBox.open(keyPath);
    final sealed = await first.seal('persist me');
    final second = await SecretBox.open(keyPath);
    expect(await second.unseal(sealed), 'persist me');
  });

  test('a wrong-length key file is replaced, not trusted', () async {
    await File(keyPath).writeAsBytes([1, 2, 3]);
    final box = await SecretBox.open(keyPath);
    final sealed = await box.seal('x');
    expect(await box.unseal(sealed), 'x');
    expect((await File(keyPath).readAsBytes()).length, 32);
  });
}

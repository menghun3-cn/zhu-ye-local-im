import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

Fingerprint _peer(String label) => Fingerprint.ofPublicKey(utf8.encode(label));

MessageRecord _message({
  String id = 'one',
  String text = 'hello',
  DateTime? at,
}) => MessageRecord(
  peer: _peer('Alice'),
  id: id,
  direction: TransferDirection.incoming,
  kind: PayloadKind.text,
  at: at ?? DateTime.utc(2026, 10, 10, 9, 30),
  settledAt: (at ?? DateTime.utc(2026, 10, 10, 9, 30)).add(
    const Duration(seconds: 1),
  ),
  state: TransferState.completed,
  names: const ['text'],
  totalBytes: text.length,
  text: text,
);

void main() {
  group('MemoryMessageStore', () {
    test('an empty store holds no messages', () async {
      expect(await loadMessages(MemoryMessageStore()), isEmpty);
    });

    test(
      'a saved conversation loads back in the order it was written',
      () async {
        final store = MemoryMessageStore();
        await saveMessages([
          _message(id: 'first', text: 'one'),
          _message(id: 'second', text: 'two'),
          _message(id: 'third', text: 'three'),
        ], store);

        expect(
          [for (final message in await loadMessages(store)) message.id],
          ['first', 'second', 'third'],
        );
      },
    );

    test('what is loaded shares nothing with what was saved', () async {
      final store = MemoryMessageStore();
      final written = _message(text: 'original');
      await saveMessages([written], store);

      final read = await loadMessages(store);
      expect(read.single.text, 'original');
      expect(identical(read.single, written), isFalse);
    });
  });

  group('the file a conversation is kept in', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('message-store-test');
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    FileMessageStore storeIn(String name) =>
        FileMessageStore('${sandbox.path}${Platform.pathSeparator}$name');

    test('a file that is not there is an empty conversation', () async {
      expect(await loadMessages(storeIn('messages.json')), isEmpty);
    });

    test('a saved conversation is really on disk, and comes back', () async {
      final store = storeIn('messages.json');
      await saveMessages([_message(id: 'kept', text: 'still here')], store);

      expect(File(store.path).existsSync(), isTrue);
      final read = await loadMessages(storeIn('messages.json'));
      expect(read.single.id, 'kept');
      expect(read.single.text, 'still here');
    });

    test(
      'the version is written, so a later change has somewhere to look',
      () async {
        final store = storeIn('messages.json');
        await saveMessages([_message()], store);

        final json = jsonDecode(
          File(store.path).readAsStringSync(),
        ) as Map<String, Object?>;
        expect(json['version'], 1);
        expect(json['messages'], isA<List<Object?>>());
      },
    );

    test('a directory that is not there yet is made, not assumed', () async {
      // A first launch has created nothing under the data directory: the very
      // first save is the one that brings it into being.
      final store = storeIn('nested/inside/messages.json');
      expect(
        Directory('${sandbox.path}${Platform.pathSeparator}nested')
            .existsSync(),
        isFalse,
      );

      await saveMessages([_message()], store);

      expect(File(store.path).existsSync(), isTrue);
    });

    test('a message that cannot be decoded is moved aside, not lost', () async {
      final store = storeIn('messages.json');
      File(store.path).writeAsStringSync('{ this is not json');

      await expectLater(
        loadMessages(store),
        throwsA(isA<MessageHistoryCorruptedException>()),
      );

      expect(
        File('${store.path}.corrupt').existsSync(),
        isTrue,
        reason: 'the bytes are the user\'s, not the program\'s to throw away',
      );
      expect(File(store.path).existsSync(), isFalse);
    });

    test('a conversation that is not a list cannot be read', () async {
      final store = storeIn('messages.json');
      File(store.path).writeAsStringSync('{"version": 1, "messages": "nope"}');

      await expectLater(loadMessages(store), throwsFormatException);
    });

    test('a message that is not an object cannot be read', () async {
      final store = storeIn('messages.json');
      File(store.path)
          .writeAsStringSync('{"version": 1, "messages": ["nope"]}');

      await expectLater(loadMessages(store), throwsFormatException);
    });
  });
}

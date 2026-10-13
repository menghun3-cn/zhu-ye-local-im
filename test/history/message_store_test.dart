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

String _hex(String label) => _peer(label).hex;

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

  group('what the user has read', () {
    test('a file with no reading key reads back as never opened', () async {
      // Exactly the shape the version before `reading` wrote. Every incoming
      // message in it is unread, because nobody had opened a conversation
      // since the app learned to care.
      final store = MemoryMessageStore();
      await store.save({
        'version': 1,
        'messages': [_message().toJson()],
      });

      final stored = await loadConversation(store);

      expect(stored.messages, hasLength(1));
      expect(stored.reading.hasOpened(_peer('Alice')), isFalse);
      expect(stored.reading.lastPeer, isNull);
    });

    test('the reading state survives a round trip', () async {
      final store = MemoryMessageStore();
      final opened = DateTime.utc(2026, 10, 10, 10);
      final reading = ConversationReading()..markOpened(_peer('Alice'), opened);
      reading.lastPeer = _hex('Alice');

      await saveConversation(
        StoredConversation(messages: [_message()], reading: reading),
        store,
      );

      final stored = await loadConversation(store);

      expect(stored.messages, hasLength(1));
      expect(stored.reading.openedThrough(_peer('Alice')), opened);
      expect(stored.reading.lastPeer, _hex('Alice'));
    });

    test('the empty store is empty, not unknown', () async {
      final stored = await loadConversation(MemoryMessageStore());

      expect(stored.messages, isEmpty);
      expect(stored.reading.lastPeer, isNull);
    });

    test('a reading block that is not an object cannot be read', () async {
      final store = MemoryMessageStore();
      await store.save({
        'version': 1,
        'messages': <Object>[],
        'reading': 'nope',
      });

      await expectLater(loadConversation(store), throwsFormatException);
    });

    test('a watermark that is not a timestamp cannot be read', () async {
      // Strict on purpose: guessing here would silently reset every unread
      // count, which is a change nobody would trace back to this line.
      final store = MemoryMessageStore();
      await store.save({
        'version': 1,
        'messages': <Object>[],
        'reading': {
          'openedThrough': {_hex('Alice'): 'yesterday'},
        },
      });

      await expectLater(loadConversation(store), throwsFormatException);
    });

    test('a saved reading state is really in the file', () async {
      final store = MemoryMessageStore();
      final reading = ConversationReading()
        ..markOpened(_peer('Alice'), DateTime.utc(2026, 10, 10, 10));
      await saveConversation(
        StoredConversation(messages: const [], reading: reading),
        store,
      );

      final json = (await store.load())!;
      expect(json['reading'], {
        'openedThrough': {_hex('Alice'): '2026-10-10T10:00:00.000Z'},
      });
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

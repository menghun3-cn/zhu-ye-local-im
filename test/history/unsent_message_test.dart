import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

Fingerprint _peer(String label) => Fingerprint.ofPublicKey(utf8.encode(label));

UnsentMessage _draft({
  PayloadKind kind = PayloadKind.text,
  String id = 'draft-one',
  String? text = 'hello there',
  String? path,
  bool appOwned = false,
}) => UnsentMessage(
  peer: _peer('Alice'),
  id: id,
  kind: kind,
  at: DateTime.utc(2026, 10, 10, 9, 30),
  names: kind == PayloadKind.text || kind == PayloadKind.emoji
      ? [kind.wireName]
      : const ['payload.bin'],
  totalBytes: kind == PayloadKind.text || kind == PayloadKind.emoji
      ? utf8.encode(text ?? '').length
      : 1024,
  text: kind == PayloadKind.text || kind == PayloadKind.emoji ? text : null,
  localPath: path,
  appOwned: appOwned,
);

void main() {
  group('UnsentMessage', () {
    test('a text draft round-trips through JSON', () {
      final draft = _draft();

      final read = UnsentMessage.fromJson(draft.toJson());

      expect(read.peer, draft.peer);
      expect(read.id, draft.id);
      expect(read.kind, PayloadKind.text);
      expect(read.at, draft.at);
      expect(read.text, 'hello there');
      expect(read.names, ['text']);
      expect(read.localPath, isNull);
      expect(read.handle, draft.handle);
    });

    test('a file draft keeps its path and app-owned flag', () {
      final draft = _draft(
        kind: PayloadKind.image,
        text: null,
        path: '/tmp/pasted.png',
        appOwned: true,
      );

      final read = UnsentMessage.fromJson(draft.toJson());

      expect(read.kind, PayloadKind.image);
      expect(read.localPath, '/tmp/pasted.png');
      expect(read.appOwned, isTrue);
      expect(read.text, isNull);
    });

    test('the timestamp is written in UTC and read back as UTC', () {
      final local = DateTime(2026, 10, 10, 17, 30);
      final draft = UnsentMessage(
        peer: _peer('Alice'),
        id: 'draft-zone',
        kind: PayloadKind.emoji,
        at: local,
        names: const ['emoji'],
        totalBytes: 4,
        text: '😀',
      );

      final json = draft.toJson();
      expect(json['at'], '2026-10-10T09:30:00.000Z');

      final read = UnsentMessage.fromJson(json);
      expect(read.at.isUtc, isTrue);
      expect(read.at, local.toUtc());
    });

    test('clipboard content is refused, here and on disk', () {
      expect(
        () => UnsentMessage.fromJson({
          'peer': _peer('Alice').hex,
          'id': 'x',
          'kind': 'clipboard',
          'at': '2026-10-10T09:30:00.000Z',
          'names': const ['clipboard'],
          'bytes': 3,
        }),
        throwsFormatException,
      );
    });

    test('a text draft with no body cannot be read', () {
      expect(
        () => UnsentMessage.fromJson({
          'peer': _peer('Alice').hex,
          'id': 'x',
          'kind': 'text',
          'at': '2026-10-10T09:30:00.000Z',
          'names': const ['text'],
          'bytes': 0,
        }),
        throwsFormatException,
      );
    });

    test('a file draft with no path cannot be read', () {
      expect(
        () => UnsentMessage.fromJson({
          'peer': _peer('Alice').hex,
          'id': 'x',
          'kind': 'file',
          'at': '2026-10-10T09:30:00.000Z',
          'names': const ['a.bin'],
          'bytes': 1,
        }),
        throwsFormatException,
      );
    });

    test('a file draft that also carries a body is malformed', () {
      expect(
        () => UnsentMessage.fromJson({
          'peer': _peer('Alice').hex,
          'id': 'x',
          'kind': 'file',
          'at': '2026-10-10T09:30:00.000Z',
          'names': const ['a.bin'],
          'bytes': 1,
          'path': '/tmp/a.bin',
          'text': 'and a body',
        }),
        throwsFormatException,
      );
    });
  });

  group('the conversation file', () {
    test('unsent drafts ride in the same envelope as the messages', () async {
      final store = MemoryMessageStore();
      final reading = ConversationReading()
        ..markOpened(_peer('Alice'), DateTime.utc(2026, 10, 10, 10));

      await saveConversation(
        StoredConversation(
          messages: const [],
          reading: reading,
          unsent: [_draft()],
        ),
        store,
      );

      final stored = await loadConversation(store);
      expect(stored.unsent, hasLength(1));
      expect(stored.unsent.single.text, 'hello there');
      expect(stored.unsent.single.peer, _peer('Alice'));
    });

    test('a file written before drafts existed reads back with none', () async {
      // The shape the version before `unsent` wrote: messages and reading,
      // and no third key. Every draft a user had then simply did not exist.
      final store = MemoryMessageStore();
      await store.save({
        'version': 1,
        'messages': <Object?>[],
        'reading': <String, Object?>{},
      });

      final stored = await loadConversation(store);
      expect(stored.unsent, isEmpty);
    });

    test('an unsent key that is not a list cannot be read', () async {
      final store = MemoryMessageStore();
      await store.save({
        'version': 1,
        'messages': <Object?>[],
        'reading': <String, Object?>{},
        'unsent': 'nope',
      });

      await expectLater(loadConversation(store), throwsFormatException);
    });
  });
}

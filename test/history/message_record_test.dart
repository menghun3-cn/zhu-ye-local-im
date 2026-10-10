import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

Fingerprint _peer(String label) => Fingerprint.ofPublicKey(utf8.encode(label));

MessageRecord _sample({
  Fingerprint? peer,
  String id = 'a1b2c3',
  TransferDirection direction = TransferDirection.incoming,
  PayloadKind kind = PayloadKind.text,
  DateTime? at,
  DateTime? settledAt,
  TransferState state = TransferState.completed,
  List<String> names = const ['text'],
  int totalBytes = 5,
  String? text = 'hello',
  String? localPath,
}) {
  final when = at ?? DateTime.utc(2026, 10, 10, 9, 30);
  return MessageRecord(
    peer: peer ?? _peer('Alice'),
    id: id,
    direction: direction,
    kind: kind,
    at: when,
    settledAt: settledAt ?? when.add(const Duration(seconds: 2)),
    state: state,
    names: names,
    totalBytes: totalBytes,
    text: text,
    localPath: localPath,
  );
}

/// [record] after the trip it really takes: encoded to text and parsed again.
///
/// Through a real JSON string rather than straight from the map, because that
/// is the only way the round trip is the one the file does — a map handed
/// straight back would hide a value that encodes to something else, and the
/// timestamps and the names list are both types that do.
MessageRecord _roundTrip(MessageRecord record) => MessageRecord.fromJson(
  jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
);

/// A message's JSON with one key replaced, for the malformed cases.
Map<String, Object?> _jsonWith(String key, Object? value) {
  final json = _sample().toJson();
  if (value == null) {
    json.remove(key);
  } else {
    json[key] = value;
  }
  return json;
}

void main() {
  group('a remembered message', () {
    test('survives the trip through the file unchanged', () {
      final record = _sample(
        kind: PayloadKind.file,
        direction: TransferDirection.outgoing,
        names: ['report.pdf', 'notes.txt'],
        totalBytes: 4096,
        text: null,
        localPath: r'C:\Users\me\Downloads\report.pdf',
      );

      final read = _roundTrip(record);

      expect(read.peer, record.peer);
      expect(read.id, record.id);
      expect(read.direction, TransferDirection.outgoing);
      expect(read.kind, PayloadKind.file);
      expect(read.at, record.at);
      expect(read.settledAt, record.settledAt);
      expect(read.state, TransferState.completed);
      expect(read.names, ['report.pdf', 'notes.txt']);
      expect(read.totalBytes, 4096);
      expect(read.text, isNull);
      expect(read.localPath, r'C:\Users\me\Downloads\report.pdf');
      expect(read.handle, record.handle);
    });

    test('a text message keeps its body and names no file', () {
      final read = _roundTrip(_sample(text: 'see you at six'));

      expect(read.kind, PayloadKind.text);
      expect(read.text, 'see you at six');
      expect(read.localPath, isNull);
    });

    test('an ending other than completion is remembered as it was', () {
      for (final state in [
        TransferState.rejected,
        TransferState.cancelled,
        TransferState.failed,
      ]) {
        expect(_roundTrip(_sample(state: state, text: null)).state, state);
      }
    });

    test('a message that ended at a different moment keeps both moments', () {
      final at = DateTime.utc(2026, 10, 10, 9, 30);
      final settled = DateTime.utc(2026, 10, 10, 9, 31, 15);

      final read = _roundTrip(_sample(at: at, settledAt: settled));

      expect(read.at, at);
      expect(read.settledAt, settled);
    });

    test('a message with no ending time reads back with none', () {
      final record = MessageRecord(
        peer: _peer('Alice'),
        id: 'x',
        direction: TransferDirection.incoming,
        kind: PayloadKind.text,
        at: DateTime.utc(2026, 10, 10),
        state: TransferState.completed,
        names: const ['text'],
        totalBytes: 1,
        text: 'hi',
      );

      expect(_roundTrip(record).settledAt, isNull);
    });
  });

  group('reading a message back', () {
    test('refuses a state that is not an ending', () {
      for (final open in ['awaitingDecision', 'transferring', 'verifying']) {
        expect(
          () => MessageRecord.fromJson(_jsonWith('state', open)),
          throwsFormatException,
          reason: '$open describes a connection, not something that happened',
        );
      }
    });

    test('refuses a field a record cannot do without', () {
      for (final key in ['peer', 'id', 'direction', 'kind', 'at', 'state']) {
        expect(
          () => MessageRecord.fromJson(_jsonWith(key, null)),
          throwsFormatException,
          reason: '"$key" is not optional',
        );
      }
    });

    test('refuses a value of the wrong type', () {
      expect(
        () => MessageRecord.fromJson(_jsonWith('bytes', 'lots')),
        throwsFormatException,
      );
      expect(
        () => MessageRecord.fromJson(_jsonWith('names', 'report.pdf')),
        throwsFormatException,
      );
      expect(
        () => MessageRecord.fromJson(_jsonWith('peer', 'not-a-fingerprint')),
        throwsFormatException,
      );
    });

    test('refuses a timestamp that is not one', () {
      expect(
        () => MessageRecord.fromJson(_jsonWith('at', 'yesterday')),
        throwsFormatException,
      );
    });
  });

  group('what names a message', () {
    test('is the peer and the id together', () {
      final message = _sample(id: 'abc');

      expect(message.handle, '${message.peer.hex}\u0000abc');
    });

    test('tells the same id from two peers apart', () {
      // Two Devices may hand out the same id — nothing coordinates them — so a
      // conversation that outlives a Session has to key on the pair.
      final fromAlice = _sample(peer: _peer('Alice'), id: 'same');
      final fromBob = _sample(peer: _peer('Bob'), id: 'same');

      expect(fromAlice.handle, isNot(fromBob.handle));
    });
  });
}

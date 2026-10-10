import 'dart:convert';
import 'dart:io';

import 'message_record.dart';

/// How many messages this Device keeps, across every conversation.
///
/// A ceiling rather than no bound at all, for the same reason the live list has
/// one: a file that grows for the life of an installation is a file that
/// eventually costs more to read and write than the history in it is worth.
/// A thousand is far more than anybody scrolls back through — the shell's
/// conversation list holds every message ever exchanged, and a busy year of
/// typing is a few thousand — and it is small enough that the whole file is a
/// couple of hundred kilobytes, which is what makes writing it out whole on
/// every change reasonable.
const int maxRememberedMessages = 1000;

/// Raised when a persisted conversation cannot be decoded.
///
/// The damaged file has been moved aside by the time this is thrown, so the
/// caller can carry on with an empty history — the honest answer, because a
/// conversation is a record and not the Device's identity — while leaving the
/// bytes where a user could look at them.
final class MessageHistoryCorruptedException implements Exception {
  const MessageHistoryCorruptedException(
    this.path,
    this.cause,
    this.backupPath,
  );

  /// Where the history was expected.
  final String path;

  /// What was wrong with it.
  final Object cause;

  /// Where the damaged file was moved, for the user to inspect or delete.
  final String backupPath;

  @override
  String toString() =>
      'MessageHistoryCorruptedException: $path is unreadable ($cause); '
      'moved to $backupPath';
}

/// Where a conversation's remembered messages live.
///
/// The same shape as `ProfileStore` on purpose: a store moves a JSON map and
/// knows nothing about its meaning, and the encoding rules live with
/// [loadMessages] and [saveMessages] so that a change to the persisted shape
/// cannot be made in one place and forgotten in the other.
abstract interface class MessageStore {
  /// The stored history, or null when nothing has been saved yet.
  Future<Map<String, Object?>?> load();

  /// Replaces the stored history.
  Future<void> save(Map<String, Object?> json);
}

/// A [MessageStore] held in memory, for tests and for a Device that runs
/// without disk persistence.
final class MemoryMessageStore implements MessageStore {
  Map<String, Object?>? _json;

  @override
  Future<Map<String, Object?>?> load() async => _json == null
      ? null
      : jsonDecode(jsonEncode(_json)) as Map<String, Object?>;

  @override
  Future<void> save(Map<String, Object?> incoming) async {
    // Round-tripped through JSON so the caller's map cannot be mutated after
    // the fact into something the store no longer holds.
    _json = jsonDecode(jsonEncode(incoming)) as Map<String, Object?>;
  }
}

/// A [MessageStore] backed by one JSON file on this Device's disk.
///
/// Written the way the profile is written — into a sibling temp file, then
/// renamed over the target — so a crash mid-write leaves the previous history
/// intact rather than a truncated one. A conversation is worth less than an
/// identity, but a file half written is a file that fails to decode, and this
/// costs nothing to avoid.
final class FileMessageStore implements MessageStore {
  /// A store over [path], created on first save.
  FileMessageStore(this.path);

  /// Where the history lives.
  final String path;

  /// The temp file written before each replace.
  String get _tempPath => '$path.tmp';

  /// Where a damaged history is moved instead of being deleted.
  String get _corruptPath => '$path.corrupt';

  @override
  Future<Map<String, Object?>?> load() async {
    final file = File(path);
    if (!await file.exists()) return null;
    String text;
    try {
      text = await file.readAsString();
    } on FileSystemException catch (error) {
      throw MessageHistoryCorruptedException(path, error, _corruptPath);
    }
    try {
      final value = jsonDecode(text);
      if (value is! Map<String, Object?>) {
        throw const FormatException('a history is a JSON object');
      }
      return value;
    } on FormatException catch (error) {
      await _moveAside(file);
      throw MessageHistoryCorruptedException(path, error, _corruptPath);
    }
  }

  @override
  Future<void> save(Map<String, Object?> json) async {
    final temp = File(_tempPath);
    // The directory is made rather than assumed, for the same reason the
    // profile store makes it: on a first launch nothing under the data
    // directory exists yet.
    await temp.parent.create(recursive: true);
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    final target = File(path);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(path);
  }

  Future<void> _moveAside(File file) async {
    final backup = File(_corruptPath);
    if (await backup.exists()) {
      await backup.delete();
    }
    await file.rename(_corruptPath);
  }
}

/// The messages a store holds, oldest first.
///
/// Oldest first because that is how the file is written and how a running
/// conversation appends; the newest-first order a UI draws is the controller's
/// business, not the file's. An empty store answers with an empty list rather
/// than throwing — a Device that has never exchanged a message has a
/// conversation of zero messages, which is not an error.
Future<List<MessageRecord>> loadMessages(MessageStore store) async {
  final json = await store.load();
  if (json == null) return const <MessageRecord>[];
  final raw = json['messages'];
  if (raw is! List) {
    throw const FormatException('"messages" must be a list');
  }
  final messages = <MessageRecord>[];
  for (final entry in raw) {
    if (entry is! Map) {
      throw const FormatException('every message must be an object');
    }
    messages.add(MessageRecord.fromJson(entry.cast<String, Object?>()));
  }
  return messages;
}

/// Persists [messages], oldest first, through [store].
///
/// The whole list is written every time. A conversation changes when a person
/// sends or deletes something, which is a handful of times a minute at most, so
/// there is nothing to gain from a journal, and a single file that is always
/// either the old list or the new one is a file a reader can trust.
Future<void> saveMessages(List<MessageRecord> messages, MessageStore store) {
  return store.save({
    'version': 1,
    'messages': [for (final message in messages) message.toJson()],
  });
}

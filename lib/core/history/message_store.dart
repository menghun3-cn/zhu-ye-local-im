import 'dart:convert';
import 'dart:io';

import 'conversation_reading.dart';
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

  /// The save in flight, or null once the last one has finished.
  ///
  /// Saves are chained rather than left to overlap, and the reason is Windows:
  /// every save writes the *same* temp file and then renames it over the
  /// target, and two of those running at once race on that file. The rename
  /// that lands while the other save still holds the temp file open is
  /// refused, and the refusal is `ERROR_SHARING_VIOLATION` — reported as
  /// "another program is using this file" about a program's own earlier save.
  /// The controller asks for a save from several directions at once (a
  /// Transfer settling, a conversation being opened, a message being deleted),
  /// so this is an ordinary case and not a hypothetical one.
  Future<void>? _inFlight;

  @override
  Future<void> save(Map<String, Object?> json) {
    final previous = _inFlight;
    final started = previous == null
        ? _write(json)
        : previous.then((_) => _write(json));
    // Held as a future that cannot fail: one rejected save must not turn every
    // later one into the same failure without trying.
    final settled = started.then((_) {}, onError: (Object _) {});
    _inFlight = settled;
    settled.whenComplete(() {
      // Cleared only when the newest save is the one that just finished, so
      // the chain does not grow for the life of the process.
      if (identical(_inFlight, settled)) _inFlight = null;
    });
    return started;
  }

  /// The write itself, with no other save running beside it.
  Future<void> _write(Map<String, Object?> json) async {
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

/// The whole of what a conversation file holds: the messages, and what the
/// user has read of them.
///
/// One object rather than two, because the two are written together and a file
/// that could hold one without the other would eventually be read in a state
/// neither writer intended — a message list with no reading state says every
/// message just arrived, and a reading state with no messages says nothing at
/// all. They travel in one envelope and one `save`.
final class StoredConversation {
  /// Pairs [messages] with [reading].
  const StoredConversation({required this.messages, required this.reading});

  /// Every remembered message, oldest first.
  final List<MessageRecord> messages;

  /// What the user has read of them.
  final ConversationReading reading;

  /// Nothing remembered at all — a Device that has never exchanged anything.
  static final StoredConversation empty = StoredConversation(
    messages: const <MessageRecord>[],
    reading: ConversationReading(),
  );
}

/// Everything a store holds, oldest message first.
///
/// An empty store answers with [StoredConversation.empty] rather than throwing:
/// a Device that has never exchanged a message has a conversation of zero
/// messages, which is not an error. A file written before the reading state
/// existed reads back with an empty one, which is exactly right for it — every
/// incoming message in it is unread, because nobody has opened a conversation
/// since the app learned to care.
Future<StoredConversation> loadConversation(MessageStore store) async {
  final json = await store.load();
  if (json == null) return StoredConversation.empty;
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
  final rawReading = json['reading'];
  final reading = rawReading == null
      ? ConversationReading()
      : ConversationReading.fromJson(_object(rawReading, 'reading'));
  return StoredConversation(messages: messages, reading: reading);
}

/// Persists [conversation], oldest message first, through [store].
///
/// The whole thing is written every time. A conversation changes when a person
/// sends, deletes or opens something, which is a handful of times a minute at
/// most, so there is nothing to gain from a journal, and a single file that is
/// always either the old conversation or the new one is a file a reader can
/// trust.
///
/// The version stays 1. The envelope gained a key rather than changing one, and
/// the older reader this has to stay compatible with is the one that read
/// `messages` and ignored everything else — which is exactly what a version
/// bump would break for no gain. Bump it when a key's *meaning* changes, not
/// when one is added.
Future<void> saveConversation(
  StoredConversation conversation,
  MessageStore store,
) {
  return store.save({
    'version': 1,
    'messages': [for (final message in conversation.messages) message.toJson()],
    'reading': conversation.reading.toJson(),
  });
}

/// The messages a store holds, oldest first.
///
/// Kept beside [loadConversation] because a caller that only wants the messages
/// is common and saying `(await loadConversation(store)).messages` at every one
/// of them is noise. The reading state is *not* optional to persist, only to
/// ask for.
Future<List<MessageRecord>> loadMessages(MessageStore store) async {
  return (await loadConversation(store)).messages;
}

/// Persists [messages], oldest first, through [store].
///
/// Kept beside [saveConversation] for the same reason, and it writes an empty
/// reading state: a caller that had a reading state to keep would be calling
/// [saveConversation]. Anything else would silently drop what the user had
/// read, which is the one mistake this pair of functions exists to make hard.
Future<void> saveMessages(List<MessageRecord> messages, MessageStore store) {
  return saveConversation(
    StoredConversation(messages: messages, reading: ConversationReading()),
    store,
  );
}

Map<String, Object?> _object(Object? value, String key) {
  if (value is! Map) {
    throw FormatException('"$key" must be an object');
  }
  return value.cast<String, Object?>();
}

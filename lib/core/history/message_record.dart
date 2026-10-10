import '../identity/fingerprint.dart';
import '../protocol/messages.dart';
import '../transfer/transfer.dart';

/// What names one message in a conversation for as long as this Device keeps
/// it.
///
/// A Transfer's own id is unique **within the Session that carried it** and
/// nothing more: the engine mints it from twelve random bytes, so two Sessions
/// colliding by accident is not a thing that happens, but a Session is not a
/// lifetime. Reopening one and sending again produces a new id, and two
/// Sessions with the same peer — before and after a restart, or after a link
/// dropped — are the same conversation. What survives every Session is the
/// peer, so the pair is what names a remembered message.
///
/// The separator is a NUL, which no fingerprint and no hex id can contain, so
/// two different pairs cannot build one handle.
String messageHandle(Fingerprint peer, String id) => '${peer.hex}\u0000$id';

/// One message in one conversation, as it is remembered once it has ended.
///
/// A `TransferView` is a *live* thing: it hands out the offer a user can still
/// answer and the send a user can still stop, and both of those are objects
/// that only exist while a Session does. What outlives the process is far
/// smaller — what was said, when, how it ended, and where its bytes are — and
/// that is all this holds. A conversation restored from disk is therefore a
/// history and not a set of live handles, which is exactly right: nothing in it
/// can be answered or cancelled any more.
///
/// Only *settled* messages are remembered. An unanswered offer and a Transfer
/// still on the wire are not history — they are the state of a connection that
/// ended with the process — and restoring one would put a question on screen
/// that nobody is waiting on the other end for.
final class MessageRecord {
  const MessageRecord({
    required this.peer,
    required this.id,
    required this.direction,
    required this.kind,
    required this.at,
    required this.state,
    required this.names,
    required this.totalBytes,
    this.text,
    this.localPath,
    this.settledAt,
  });

  /// The Device on the other end of this message.
  final Fingerprint peer;

  /// The Transfer's id, unique within the Session that carried it.
  final String id;

  /// Whether this Device sent or received it.
  final TransferDirection direction;

  /// What the message carries.
  final PayloadKind kind;

  /// When it entered the conversation.
  final DateTime at;

  /// When it ended.
  final DateTime? settledAt;

  /// How it ended. Always a state that [TransferState.isSettled] calls settled.
  final TransferState state;

  /// The names of the items, in the order the sender listed them.
  final List<String> names;

  /// Payload bytes the message added up to.
  final int totalBytes;

  /// The body of a text Payload, as it was said.
  final String? text;

  /// Where this message's bytes ended up on this machine, when they did.
  final String? localPath;

  /// What names this message from now on, here and on disk.
  String get handle => messageHandle(peer, id);

  /// This message as JSON.
  ///
  /// `at` and `settledAt` are written in UTC and read back as UTC: an ISO-8601
  /// string with an offset would round-trip too, but a local time written
  /// without one would be re-read in whatever zone the Device woke up in.
  Map<String, Object?> toJson() => {
    'peer': peer.hex,
    'id': id,
    'direction': _directionOf(direction),
    'kind': kind.wireName,
    'at': at.toUtc().toIso8601String(),
    if (settledAt != null) 'settled': settledAt!.toUtc().toIso8601String(),
    'state': _stateName(state),
    'names': names,
    'bytes': totalBytes,
    if (text != null) 'text': text,
    if (localPath != null) 'path': localPath,
  };

  /// Reads a message back, throwing [FormatException] on anything malformed.
  ///
  /// Strict on purpose. A record that decodes into *something* — a message
  /// with no direction, a state that is not an ending — would be a conversation
  /// with a hole in it that nobody could see, and the file this reads is
  /// written by this same code, so a shape it does not recognise is a bug or a
  /// hand-edit rather than an ordinary case to paper over.
  static MessageRecord fromJson(Map<String, Object?> json) {
    final state = _stateOf(_string(json, 'state'));
    if (!state.isSettled) {
      throw FormatException('"state" ${_stateName(state)} is not an ending');
    }
    final names = json['names'];
    if (names is! List) {
      throw const FormatException('"names" must be a list');
    }
    return MessageRecord(
      peer: Fingerprint(_string(json, 'peer')),
      id: _string(json, 'id'),
      direction: _directionFrom(_string(json, 'direction')),
      kind: PayloadKind.fromWireName(_string(json, 'kind')),
      at: _time(json, 'at'),
      settledAt: json.containsKey('settled') ? _time(json, 'settled') : null,
      state: state,
      names: [for (final name in names) name as String],
      totalBytes: _int(json, 'bytes'),
      text: _optionalString(json, 'text'),
      localPath: _optionalString(json, 'path'),
    );
  }

  @override
  String toString() =>
      'MessageRecord(${peer.short()}, $id, ${kind.wireName}, ${state.name})';

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('"$key" must be a string');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('"$key" must be a string when present');
    }
    return value;
  }

  static int _int(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('"$key" must be an integer');
    }
    return value;
  }

  static DateTime _time(Map<String, Object?> json, String key) {
    final raw = _string(json, key);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('"$key" is not an ISO-8601 timestamp: "$raw"');
    }
    return parsed;
  }
}

/// Which side of a Transfer a record is about, spelled the way the file does.
///
/// Short words rather than the enum's own names: the enum is internal and may
/// be renamed, and a persisted format that followed it would break the file
/// every time somebody improved a variable name.
String _directionOf(TransferDirection direction) =>
    direction == TransferDirection.outgoing ? 'out' : 'in';

TransferDirection _directionFrom(String value) => switch (value) {
  'out' => TransferDirection.outgoing,
  'in' => TransferDirection.incoming,
  _ => throw FormatException('unknown direction "$value"'),
};

/// The endings a remembered message can have, spelled the way the file does.
///
/// Every one of them settles a Transfer. The three states that do not —
/// awaiting a decision, transferring, verifying — describe a connection that is
/// still open, and a record of one would be a promise this Device cannot keep
/// after a restart.
String _stateName(TransferState state) => switch (state) {
  TransferState.completed => 'completed',
  TransferState.rejected => 'rejected',
  TransferState.cancelled => 'cancelled',
  TransferState.failed => 'failed',
  TransferState.awaitingDecision ||
  TransferState.transferring ||
  TransferState.verifying => throw ArgumentError.value(
    state,
    'state',
    'only a settled Transfer is remembered',
  ),
};

TransferState _stateOf(String value) => switch (value) {
  'completed' => TransferState.completed,
  'rejected' => TransferState.rejected,
  'cancelled' => TransferState.cancelled,
  'failed' => TransferState.failed,
  _ => throw FormatException('unknown state "$value"'),
};

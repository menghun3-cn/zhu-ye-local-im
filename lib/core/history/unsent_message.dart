import '../identity/fingerprint.dart';
import '../protocol/messages.dart';
import 'message_record.dart' show messageHandle;

/// One message this Device meant to send and could not, because the peer had
/// no Session to carry it.
///
/// A `MessageRecord` is what a *settled* Transfer becomes: it only exists
/// because something happened on the wire. An unsent message is the opposite
/// case — nothing was ever offered, so there is no Transfer to remember and no
/// ending to record. What is kept is what the user wrote and where it was
/// going, which is everything a resend needs and nothing more.
///
/// The record is deliberately not a `MessageRecord` with a made-up state:
/// the history file's reader refuses anything that is not an ending, and an
/// unsent message is not an ending — it is a thing still owed. It travels in
/// the same envelope under its own key instead, so a build that predates it
/// reads the conversation and ignores the drafts, exactly as it does for
/// `reading`.
final class UnsentMessage {
  const UnsentMessage({
    required this.peer,
    required this.id,
    required this.kind,
    required this.at,
    required this.names,
    required this.totalBytes,
    this.text,
    this.localPath,
    this.appOwned = false,
  });

  /// The Device this message was addressed to.
  final Fingerprint peer;

  /// This message's own id, minted locally rather than by an engine.
  ///
  /// Unique within the conversation for the same reason a Transfer id is:
  /// [messageHandle] pairs it with [peer], and a resend produces a *new*
  /// Transfer with a *new* id — this one names the draft, not the delivery.
  final String id;

  /// What the message carries: text, emoji, or a file/image with bytes at
  /// [localPath]. Clipboard content is never queued — mirroring has no
  /// composer and no "send" to fail.
  final PayloadKind kind;

  /// When the user tried to send it.
  final DateTime at;

  /// The names of the items, in the order the sender listed them.
  final List<String> names;

  /// Payload bytes the message adds up to, as far as this Device knows.
  final int totalBytes;

  /// The body of a text or emoji message.
  final String? text;

  /// Where the bytes live on this machine, for a file or image message.
  final String? localPath;

  /// Whether [localPath] names a temporary file this application created.
  ///
  /// True only for the image a paste writes: such a file may be taken away
  /// when the draft is deleted, and must never be taken away while it is
  /// still owed to the peer.
  final bool appOwned;

  /// What names this message from now on, here and on disk.
  String get handle => messageHandle(peer, id);

  /// This message as JSON.
  ///
  /// `at` is written in UTC and read back as UTC, for the same reason
  /// [MessageRecord.toJson] does it: a local time without an offset would be
  /// re-read in whatever zone the Device woke up in.
  Map<String, Object?> toJson() => {
    'peer': peer.hex,
    'id': id,
    'kind': kind.wireName,
    'at': at.toUtc().toIso8601String(),
    'names': names,
    'bytes': totalBytes,
    if (text != null) 'text': text,
    if (localPath != null) 'path': localPath,
    if (appOwned) 'appOwned': true,
  };

  /// Reads a message back, throwing [FormatException] on anything malformed.
  ///
  /// Strict for the same reason [MessageRecord.fromJson] is: the file is
  /// written by this same code, so a shape it does not recognise is a bug or
  /// a hand-edit, and a draft decoded into *something* would be a message
  /// that can be resent into the wrong shape.
  static UnsentMessage fromJson(Map<String, Object?> json) {
    final kind = PayloadKind.fromWireName(_string(json, 'kind'));
    switch (kind) {
      case PayloadKind.text || PayloadKind.emoji:
        if (json['path'] != null) {
          throw const FormatException(
            'a text or emoji draft carries no file path',
          );
        }
      case PayloadKind.file || PayloadKind.image:
        _string(json, 'path');
        if (json['text'] != null) {
          throw const FormatException(
            'a file draft carries no body; its words are its names',
          );
        }
      case PayloadKind.clipboard:
        throw const FormatException('clipboard content is never queued');
    }
    final names = json['names'];
    if (names is! List) {
      throw const FormatException('"names" must be a list');
    }
    final message = UnsentMessage(
      peer: Fingerprint(_string(json, 'peer')),
      id: _string(json, 'id'),
      kind: kind,
      at: _time(json, 'at'),
      names: [for (final name in names) name as String],
      totalBytes: _int(json, 'bytes'),
      text: _optionalString(json, 'text'),
      localPath: _optionalString(json, 'path'),
      appOwned: json['appOwned'] == true,
    );
    // The kind decides what a resend needs, so the pairing is checked rather
    // than trusted: a text draft with no body, or a file draft with no path,
    // is a record that cannot be delivered and should not be kept.
    final carriesBody = kind == PayloadKind.text || kind == PayloadKind.emoji;
    if (carriesBody && message.text == null) {
      throw const FormatException('a text draft must carry its body');
    }
    return message;
  }

  @override
  String toString() => 'UnsentMessage(${peer.short()}, $id, ${kind.wireName})';

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

import '../identity/fingerprint.dart';
import '../protocol/messages.dart';

/// One value taken from a Device's system clipboard, tagged with the Device it
/// was copied on.
///
/// The tag is what makes Mirroring safe to run automatically. Without it, a
/// Device that applied an incoming entry would see its own clipboard change,
/// capture that change as a local copy, and send it straight back — a two-
/// Device loop that never settles. [origin] is how a Device recognises its own
/// content returning, and [entryId] is how it recognises a duplicate of
/// something it has already handled.
final class ClipboardEntry {
  const ClipboardEntry({
    required this.entryId,
    required this.origin,
    required this.text,
    required this.capturedAt,
  });

  /// Identifies the entry for its whole life, so a Device can drop a duplicate.
  final String entryId;

  /// The Device the content was copied on.
  final Fingerprint origin;

  /// The clipboard text.
  final String text;

  /// When the copy was observed, as reported by the capturing Device.
  ///
  /// Device clocks are not synchronised, so this is only comparable with other
  /// timestamps from the same [origin] — which is exactly how it is used.
  final DateTime capturedAt;

  /// Whether [text] holds nothing a person would call a copy.
  bool get isEmpty => text.isEmpty;

  /// The wire form of this entry.
  ClipboardMessage toMessage() => ClipboardMessage(
    entryId: entryId,
    originFingerprint: origin,
    text: text,
    capturedAt: capturedAt,
  );

  /// Reads an entry off the wire.
  static ClipboardEntry fromMessage(ClipboardMessage message) => ClipboardEntry(
    entryId: message.entryId,
    origin: message.originFingerprint,
    text: message.text,
    capturedAt: message.capturedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is ClipboardEntry &&
      other.entryId == entryId &&
      other.origin == origin &&
      other.text == text &&
      other.capturedAt == capturedAt;

  @override
  int get hashCode => Object.hash(entryId, origin, text, capturedAt);

  /// Never reveals the content.
  ///
  /// A clipboard routinely holds passwords and one-time codes, so an entry that
  /// reaches a log line or an error message must not carry its text with it.
  @override
  String toString() =>
      'ClipboardEntry($entryId from ${origin.short()}, '
      '${text.length} chars, redacted)';
}

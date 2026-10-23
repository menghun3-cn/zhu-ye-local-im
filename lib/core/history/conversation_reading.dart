import '../identity/fingerprint.dart';

/// What this Device remembers about *reading* a conversation, as opposed to
/// what was said in it.
///
/// A separate thing from the conversation itself, because the two answer
/// different questions and change at different times. [MessageRecord] says what
/// was exchanged; this says which of it the user has already looked at, and
/// which conversation they were looking at last. Neither is derivable from the
/// other — a message does not know whether anybody read it — so this has to be
/// written down.
///
/// ## The unread rule
///
/// One watermark per peer, and it is a **time**, not a count: everything
/// received from a peer with an `at` later than [openedThrough] is unread.
/// A count would have to be maintained through every deletion, every resend and
/// every restart, and would be wrong the first time any of those disagreed with
/// it; a watermark is one number that answers the same question by being
/// compared against the messages that actually exist.
///
/// The desktop client this borrows its shape from marks a conversation read the
/// moment its window is open, and the whole of what a user expects is in that
/// sentence: the count clears on opening rather than on scrolling to the
/// bottom, and it does not come back on leaving. It also has no read receipt —
/// nothing here is told to the peer, and nothing here is a peer's business.
/// See `2026-10-12-unread-counts-and-last-conversation.md`.
///
/// Only *incoming* messages count. What this Device sent is not something its
/// own user has to be told about, and counting it would make a conversation the
/// user just typed in show a badge for their own words.
final class ConversationReading {
  /// Builds a reading state from explicit maps.
  ///
  /// [openedThrough] is keyed by peer fingerprint hex; [lastPeer] is the
  /// conversation the user was last in, by the same key.
  ConversationReading({
    Map<String, DateTime> openedThrough = const {},
    this.lastPeer,
  }) : _openedThrough = {...openedThrough};

  /// When each peer's conversation was last open, by fingerprint hex.
  ///
  /// Absent for a peer whose conversation has never been opened — which is a
  /// different thing from "opened at the epoch": a conversation this Device has
  /// never looked at is one where *every* message is unread, and the absence
  /// says that without a sentinel date anybody could compare against by
  /// accident.
  final Map<String, DateTime> _openedThrough;

  /// The conversation the user was last in, or null for none yet.
  ///
  /// Held as a hex string rather than a [Fingerprint] for the same reason the
  /// page holds its selection that way: it outlives the peer being on the
  /// network, and a conversation that outlives its Session is the whole premise
  /// of this surface.
  String? lastPeer;

  /// When [peer]'s conversation was last open, or null if never.
  DateTime? openedThrough(Fingerprint peer) => _openedThrough[peer.hex];

  /// Whether [peer]'s conversation has ever been opened.
  bool hasOpened(Fingerprint peer) => _openedThrough.containsKey(peer.hex);

  /// Records that [peer]'s conversation is being read as of [at].
  ///
  /// Monotonic: a later mark never moves the watermark backwards, so a clock
  /// that stepped back — a timezone change, an NTP correction — cannot make a
  /// conversation a user has read show everything again as unread.
  void markOpened(Fingerprint peer, DateTime at) {
    final current = _openedThrough[peer.hex];
    if (current != null && !at.isAfter(current)) return;
    _openedThrough[peer.hex] = at;
  }

  /// How many messages in [latest]'s conversation [peer] has not read yet.
  ///
  /// [messages] is that conversation's history, and this counts the ones that
  /// are *incoming* and newer than the watermark. A peer whose conversation has
  /// never been opened counts every incoming message, including ones that
  /// arrived before this Device existed as far as the user is concerned — a
  /// first look at an old conversation is still a first look.
  int unreadFor(
    Fingerprint peer,
    Iterable<({bool incoming, DateTime at})> messages,
  ) {
    final opened = _openedThrough[peer.hex];
    var count = 0;
    for (final message in messages) {
      if (!message.incoming) continue;
      if (opened != null && !message.at.isAfter(opened)) continue;
      count++;
    }
    return count;
  }

  /// Forgets everything about peers that are no longer known.
  ///
  /// [keep] is the set of fingerprints still worth remembering — every peer
  /// this Device still holds a conversation for. This exists so that the map
  /// cannot grow one entry per Device ever seen and never lose one; a Device
  /// whose history has been deleted has nothing left to be unread.
  void retainOnly(Set<String> keep) {
    _openedThrough.removeWhere((hex, _) => !keep.contains(hex));
    final last = lastPeer;
    if (last != null && !keep.contains(last)) lastPeer = null;
  }

  /// Forgets everything about [peer]'s conversation.
  ///
  /// Used when the user clears the conversation itself: a watermark with no
  /// messages to compare against is not history, and leaving it behind would
  /// make a new first message look as though it had already been read.
  void forget(Fingerprint peer) {
    _openedThrough.remove(peer.hex);
    if (lastPeer == peer.hex) lastPeer = null;
  }

  /// This state as JSON.
  ///
  /// Times are written in UTC, like a message's: an ISO-8601 string with an
  /// offset would round-trip, but a local one written without it would be read
  /// back in whatever zone the Device woke up in, and a watermark that moved by
  /// hours would show a whole conversation as unread.
  Map<String, Object?> toJson() => {
    'openedThrough': {
      for (final entry in _openedThrough.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    },
    if (lastPeer != null) 'lastPeer': lastPeer,
  };

  /// Reads a state back, throwing [FormatException] on anything malformed.
  ///
  /// Strict, like a message's, and for the same reason: the file is written by
  /// this code, so a shape it does not recognise is a bug or a hand-edit rather
  /// than an ordinary case. Being lenient here would silently reset every
  /// unread count, which is a change nobody would trace back to this line.
  static ConversationReading fromJson(Map<String, Object?> json) {
    final raw = json['openedThrough'];
    final opened = <String, DateTime>{};
    if (raw != null) {
      if (raw is! Map) {
        throw const FormatException('"openedThrough" must be an object');
      }
      for (final entry in raw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! String) {
          throw const FormatException(
            '"openedThrough" must map strings to strings',
          );
        }
        final parsed = DateTime.tryParse(value);
        if (parsed == null) {
          throw FormatException('"openedThrough.$key" is not a timestamp');
        }
        opened[key] = parsed;
      }
    }
    final last = json['lastPeer'];
    if (last != null && last is! String) {
      throw const FormatException('"lastPeer" must be a string when present');
    }
    return ConversationReading(
      openedThrough: opened,
      lastPeer: last as String?,
    );
  }

  @override
  String toString() =>
      'ConversationReading(${_openedThrough.length} opened, '
      'last ${lastPeer ?? 'none'})';
}

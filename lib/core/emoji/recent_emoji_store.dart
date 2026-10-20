/// How many recently used emoticons the picker keeps.
///
/// WeChat's desktop picker shows a row of eight, and eight is also the width
/// of a full row in the grid below it, so a Recent strip that never has to
/// scroll fits the same measurement as the grid's own row. Kept per Device
/// and across restarts, because "the ones I used" being lost when the app
/// closes is what turns recents into a history of the last ten minutes.
const int recentEmojiLimit = 8;

/// The faces a Recent strip should draw, newest first and capped.
///
/// Faces this build no longer knows are dropped rather than drawn: a stale
/// face in the strip is a face nobody can choose again, and a strip is
/// supposed to be the fast path for exactly the choosing. Unknown entries are
/// only ever *ignored*, never mistaken for somebody else's entry.
List<String> recentEmojis(Iterable<String> table, List<String>? stored) {
  if (stored == null || stored.isEmpty) return const [];
  final known = table.toSet();
  return [
    for (final face in stored)
      if (known.contains(face)) face,
  ].take(recentEmojiLimit).toList();
}

/// Records [face] as the most recently used, and answers the strip to draw.
///
/// The same list the user is looking at, so that a face chosen from the
/// picker moves to the front immediately and a face already in the strip is
/// not duplicated. Faces outside the current table are dropped, because what
/// a strip cannot draw it cannot mean.
List<String> rememberRecentEmoji(
  Iterable<String> table,
  List<String>? stored, {
  required String face,
  int limit = recentEmojiLimit,
}) {
  final known = table.toSet();
  if (!known.contains(face)) return List.of(stored ?? const <String>[]);
  return [
    face,
    for (final entry in stored ?? const <String>[])
      if (entry != face && known.contains(entry)) entry,
  ].take(limit).toList();
}

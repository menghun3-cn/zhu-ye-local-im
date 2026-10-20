/// The emoticons the composer offers.
///
/// One table for every use of an emoticon in the product, so that a sender
/// and a receiver always draw the same face: the palette a chat can put in a
/// bubble is the palette a bubble can render. The content is pure data, which
/// keeps this file importable from anywhere in `lib/core` without dragging
/// Flutter in.
///
/// The faces are Unicode code points rather than bitmap stickers, on purpose:
/// a code point is a fact about Unicode that the receiving platform renders,
/// so two builds never have to agree on a pixel for a face to be the same.
/// The set is a curated take on the faces a chat user reaches for — feelings,
/// gestures and small objects — in a fixed order, so a picker never has to
/// invent one.
///
/// Sorted the way a picker would order a grid: feelings first, then actions,
/// then objects. Ordering is a property of this table and not of the Recent
/// strip, which is always in recency order.
const List<EmojiEntry> emojiTable = [
  // Feelings.
  EmojiEntry(emoji: '😀', name: 'smile'),
  EmojiEntry(emoji: '😁', name: 'grin'),
  EmojiEntry(emoji: '😂', name: 'joy'),
  EmojiEntry(emoji: '🤣', name: 'rofl'),
  EmojiEntry(emoji: '😊', name: 'blush'),
  EmojiEntry(emoji: '😍', name: 'heart eyes'),
  EmojiEntry(emoji: '😘', name: 'kiss'),
  EmojiEntry(emoji: '😗', name: 'kissing'),
  EmojiEntry(emoji: '😋', name: 'yum'),
  EmojiEntry(emoji: '😜', name: 'wink tongue'),
  EmojiEntry(emoji: '🤪', name: 'zany'),
  EmojiEntry(emoji: '😎', name: 'cool'),
  EmojiEntry(emoji: '🤓', name: 'nerd'),
  EmojiEntry(emoji: '🥳', name: 'party'),
  EmojiEntry(emoji: '🥺', name: 'pleading'),
  EmojiEntry(emoji: '😢', name: 'cry'),
  EmojiEntry(emoji: '😭', name: 'sob'),
  EmojiEntry(emoji: '😡', name: 'pout'),
  EmojiEntry(emoji: '😱', name: 'scream'),
  EmojiEntry(emoji: '😴', name: 'sleepy'),

  // Actions and signs.
  EmojiEntry(emoji: '👍', name: 'thumbs up'),
  EmojiEntry(emoji: '👎', name: 'thumbs down'),
  EmojiEntry(emoji: '👏', name: 'clap'),
  EmojiEntry(emoji: '🙏', name: 'pray'),
  EmojiEntry(emoji: '🤝', name: 'handshake'),
  EmojiEntry(emoji: '💪', name: 'muscle'),
  EmojiEntry(emoji: '✌️', name: 'victory'),
  EmojiEntry(emoji: '🤞', name: 'crossed fingers'),
  EmojiEntry(emoji: '👌', name: 'ok'),
  EmojiEntry(emoji: '✋', name: 'raised hand'),
  EmojiEntry(emoji: '👋', name: 'wave'),
  EmojiEntry(emoji: '🤔', name: 'thinking'),
  EmojiEntry(emoji: '🤗', name: 'hug'),
  EmojiEntry(emoji: '🤫', name: 'shush'),
  EmojiEntry(emoji: '🤭', name: 'giggle'),
  EmojiEntry(emoji: '😶', name: 'no mouth'),
  EmojiEntry(emoji: '🫡', name: 'salute'),
  EmojiEntry(emoji: '❌', name: 'cross mark'),
  EmojiEntry(emoji: '✅', name: 'check mark'),
  EmojiEntry(emoji: '❓', name: 'question'),
  EmojiEntry(emoji: '❗', name: 'exclamation'),

  // Objects and sweetness.
  EmojiEntry(emoji: '❤️', name: 'heart'),
  EmojiEntry(emoji: '🧡', name: 'orange heart'),
  EmojiEntry(emoji: '💛', name: 'yellow heart'),
  EmojiEntry(emoji: '💚', name: 'green heart'),
  EmojiEntry(emoji: '💙', name: 'blue heart'),
  EmojiEntry(emoji: '💜', name: 'purple heart'),
  EmojiEntry(emoji: '💔', name: 'broken heart'),
  EmojiEntry(emoji: '💯', name: 'hundred'),
  EmojiEntry(emoji: '🔥', name: 'fire'),
  EmojiEntry(emoji: '⭐', name: 'star'),
  EmojiEntry(emoji: '🎉', name: 'tada'),
  EmojiEntry(emoji: '🎂', name: 'birthday'),
  EmojiEntry(emoji: '🌹', name: 'rose'),
  EmojiEntry(emoji: '💐', name: 'bouquet'),
  EmojiEntry(emoji: '🌸', name: 'cherry blossom'),
  EmojiEntry(emoji: '🍀', name: 'clover'),
  EmojiEntry(emoji: '🌈', name: 'rainbow'),
  EmojiEntry(emoji: '☀️', name: 'sun'),
  EmojiEntry(emoji: '🌙', name: 'moon'),
  EmojiEntry(emoji: '⚡', name: 'zap'),
];

/// Every face the composer can offer, in [emojiTable]'s order.
///
/// Computed rather than written out a second time, so the recents store and
/// the profile never have to remember a face the table did not.
List<String> get emojiFaces => [for (final entry in emojiTable) entry.emoji];

/// One emoticon the composer can send.
final class EmojiEntry {
  const EmojiEntry({required this.emoji, required this.name});

  /// The code point, which is also what travels over the wire.
  final String emoji;

  /// The face's English name, for a tooltip and for the escaped key used in
  /// persistence. Not shown in the picker.
  final String name;

  @override
  bool operator ==(Object other) => other is EmojiEntry && other.emoji == emoji;

  @override
  int get hashCode => emoji.hashCode;
}

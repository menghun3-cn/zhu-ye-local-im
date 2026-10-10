import 'package:flutter/material.dart';

import 'theme.dart';

/// A round avatar with an initial in it.
///
/// WeChat has a photo per contact. There is nothing to photograph here — a
/// Device is a Fingerprint — so the avatar carries the first character of
/// whatever the Device is called, on a colour derived from its Fingerprint.
/// The colour is derived rather than stored so that the same Device keeps the
/// same avatar across restarts without anything being persisted, and so that
/// two nameless Devices still look different from each other.
///
/// The one Device that is not drawn from the first character of its name is a
/// Device named by its address, which gets its last octet instead — see [label].
///
/// Drawn on both sides of a conversation: the peer's on the left, the user's
/// own on the right, exactly as the desktop client does.
class Avatar extends StatelessWidget {
  /// Draws an avatar for [name], coloured from [seed].
  const Avatar({
    super.key,
    required this.name,
    required this.seed,
    this.label,
    this.size = WeChat.avatar,
  });

  /// What the Device is called. The first character is shown.
  final String name;

  /// What the colour is derived from — a Fingerprint, normally.
  final String seed;

  /// What to draw instead of the first character of [name].
  ///
  /// For a Device that is named by its address. The first character of
  /// `192.168.1.115` is a `1`, and a `1` is what every address in the list
  /// starts with — a circle that reads the same on every row tells the user
  /// nothing, which is the one thing an avatar must not do. The last octet is
  /// what differs between two machines on one network, so that is what
  /// `PeerView.avatarLabel` hands in here.
  final String? label;

  /// Diameter in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    // A Device that announced no name is named by its Fingerprint, which is
    // hex — so the first character would be a letter of a hash nobody chose.
    // That is still the honest label for it, and it still differs per Device,
    // which is what an avatar is for.
    final label = this.label;
    final initial =
        label ?? (name.isEmpty ? '?' : name.characters.first.toUpperCase());
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colourFor(seed),
        borderRadius: BorderRadius.circular(WeChat.avatarRadius),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w500,
          height: 1,
        ),
      ),
    );
  }

  /// A stable colour for [seed], from a small hand-picked palette.
  ///
  /// A hand-picked set rather than a hash-to-RGB: random hues produce greens
  /// and yellows that fight the brand colour and the bubble green. These all
  /// sit behind white text legibly.
  static Color _colourFor(String seed) {
    const palette = [
      Color(0xFF4A90D9),
      Color(0xFF9B6BC4),
      Color(0xFFD97A4A),
      Color(0xFF3FA98A),
      Color(0xFFC2557A),
      Color(0xFF5C7FA8),
      Color(0xFF8A8F5C),
      Color(0xFF6B7BB0),
    ];
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }
}

/// The bubble a message is drawn in: a rounded rectangle whose corner by the
/// avatar is tucked in.
///
/// The tucked corner is what makes a bubble readable as *from* somebody rather
/// than merely *on* a side. It replaced a tail — a small rotated square tucked
/// behind the corner — because a tail reads as a cartoon speech balloon, while
/// a corner says the same thing with no extra shape at all. Only the corner
/// beside the avatar tucks; the other three take `WeChat.bubbleRadius`.
///
/// A received bubble is drawn with a hairline as well as a fill, because on the
/// light page its fill is the conversation board's own white and without the
/// line there would be nothing to see. An outgoing bubble sits in its own green
/// and needs none. On a dark page both relationships turn over — the received
/// bubble is a notch *brighter* than the board — but the line stays, and reads
/// as an edge rather than as the only thing separating two identical fills.
class MessageBubbleShape extends StatelessWidget {
  /// Wraps [child] in a bubble of [colour], tucked towards the avatar when
  /// [outgoing] is false and away from it when [outgoing] is true.
  const MessageBubbleShape({
    super.key,
    required this.colour,
    required this.outgoing,
    required this.child,
  });

  /// The bubble's fill.
  final Color colour;

  /// Which side the tucked corner is on.
  final bool outgoing;

  /// The bubble's contents.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(WeChat.bubbleRadius);
    const tucked = Radius.circular(WeChat.bubbleTuckRadius);
    // The corner nearest the avatar is the one that tucks: the left when the
    // message came in (the peer's avatar is on the left), the right when it
    // went out.
    final radius = BorderRadius.only(
      topLeft: outgoing ? round : tucked,
      topRight: outgoing ? tucked : round,
      bottomLeft: round,
      bottomRight: round,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            padding: WeChat.bubblePadding,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: radius,
              border: outgoing
                  ? null
                  : Border.all(
                      color: WeChatColors.of(context).divider,
                      width: 1,
                    ),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

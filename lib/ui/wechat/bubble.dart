import 'package:flutter/material.dart';

import 'bubble_paint.dart';
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
/// A received bubble carries a hairline as well as a fill, in both themes. The
/// line is an edge, not the thing that makes the bubble visible: on the light
/// page the fill is a soft grey against the board's white, and on the dark page
/// it is a grey *lighter* than the board — so the fill alone separates the two,
/// and the hairline only crisps the boundary. An outgoing bubble sits in its own
/// green and needs no line at all.
class MessageBubbleShape extends StatelessWidget {
  /// Wraps [child] in a bubble painted with [paint], tucked towards the
  /// avatar when [outgoing] is false and away from it when [outgoing] is true.
  const MessageBubbleShape({
    super.key,
    required this.paint,
    required this.outgoing,
    required this.child,
    this.maxWidth,
  });

  /// What the bubble is painted with — fill, ink and scrim.
  ///
  /// The fill is a [BoxDecoration] without a corner radius: which corner
  /// tucks is this widget's decision, made from [outgoing], so the radius is
  /// merged in here rather than asked of the caller.
  final BubblePaint paint;

  /// The fill's solid colour, when it has one — null for a gradient or an
  /// image fill.
  ///
  /// Kept as a getter rather than removed because the tests that pin "the
  /// outgoing bubble is the theme's green" read it; for every fill that is a
  /// plain colour it answers what `paint.decoration.color` does.
  Color? get colour => paint.decoration.color;

  /// Which side the tucked corner is on.
  final bool outgoing;

  /// The bubble's contents.
  final Widget child;

  /// How wide the bubble may get, or null for as wide as it needs.
  ///
  /// The cap belongs to the *chat area*, not to the bubble: a bubble that
  /// grew with its text would one day be a single line across a 2560-pixel
  /// window, and the reader would have to scroll sideways to find the end of
  /// a sentence. Capped, the text wraps and the bubble grows downward
  /// instead, which is what a message in a column is supposed to do.
  final double? maxWidth;

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

    // The padding sits inside the scrim rather than outside it: a scrim that
    // stopped at the content's edge would leave a rim of unscrimmed picture
    // around the words, which is exactly the rim that makes a skin look
    // unfinished. With no scrim the padding is simply the container's own,
    // as it always was.
    Widget content = Padding(padding: WeChat.bubblePadding, child: child);
    final scrim = paint.scrim;
    if (scrim != null) {
      content = ColoredBox(color: scrim, child: content);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ConstrainedBox(
            // The floor is what keeps a one-word message from being a dot:
            // a bubble has to look like a bubble even when there is barely
            // anything in it.
            constraints: BoxConstraints(
              minWidth: WeChat.bubbleMinWidth,
              maxWidth: maxWidth ?? double.infinity,
            ),
            child: Container(
              decoration: paint.decoration.copyWith(borderRadius: radius),
              child: content,
            ),
          ),
        ),
      ],
    );
  }
}

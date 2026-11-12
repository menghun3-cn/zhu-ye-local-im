import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/core.dart';
import 'theme.dart';

/// The widest a user-picked skin picture is decoded at, in pixels.
///
/// A bubble is at most [WeChat.bubbleMaxWidthFactor] of the chat area — a
/// few hundred logical pixels even on a large window — so decoding a
/// four-thousand-pixel photograph at full size would spend megabytes of image
/// cache on detail no bubble can ever show. The cap is deliberately generous
/// rather than exact: it bounds the waste without needing the bubble's own
/// width, which varies per message and per window size.
const int bubbleSkinDecodeWidth = 1024;

/// What one bubble is painted with: its fill, the ink on top of it, and an
/// optional scrim between the two.
///
/// The unit [MessageBubble] hands to [MessageBubbleShape] and to everything
/// inside the bubble that needs to know what colour its words are. Before
/// skins existed the answer was always "the theme's two bubble colours"; now
/// it is whatever [bubblePaintFor] resolved — which for a plain message is
/// still exactly that.
class BubblePaint {
  /// A bubble painted [decoration], with content in [ink].
  ///
  /// [scrim] is a translucent black laid over the fill and under the
  /// content — how an image skin keeps its text legible on a busy picture.
  /// Null for every fill that does not need one.
  const BubblePaint({required this.decoration, required this.ink, this.scrim});

  /// The bubble's fill — colour, gradient or image — without a corner radius.
  ///
  /// The radius is the shape's business, not the paint's: which corner tucks
  /// depends on which side the message came from, and that is
  /// [MessageBubbleShape]'s decision to make. The caller's decoration is
  /// merged with the radius there.
  final BoxDecoration decoration;

  /// The colour the bubble's text, icons and progress track are drawn in.
  final Color ink;

  /// A translucent black over the fill and under the content, or null.
  final Color? scrim;
}

/// Resolves what a bubble on [outgoing]'s side is painted with.
///
/// [skin] is the user's choice for that side, or null for the theme's own
/// colours — which is also what an image skin whose file has gone missing
/// falls back to, because a bubble that cannot paint its picture is better
/// drawn as the ordinary bubble than as a blank rectangle with white text on
/// the conversation's background.
///
/// Only call this for a bubble that may wear a skin: the caller decides
/// which message kinds are eligible (text and emoji; files and in-flight
/// images keep the theme), because the eligibility is a fact about the
/// *message*, not about the paint.
BubblePaint bubblePaintFor({
  required WeChatColors colors,
  required bool outgoing,
  BubbleSkin? skin,
}) {
  final fallback = _themePaint(colors, outgoing);
  if (skin == null) return fallback;
  switch (skin) {
    case GradientBubbleSkin():
      final axis = _gradientAxis(skin.direction);
      return BubblePaint(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [for (final color in skin.colors) Color(color)],
            stops: skin.stops.isEmpty ? null : skin.stops,
            begin: axis.begin,
            end: axis.end,
          ),
        ),
        ink: _inkFor(skin.ink, colors),
      );
    case ImageBubbleSkin():
      final provider = _imageProvider(skin);
      if (provider == null) return fallback;
      return BubblePaint(
        decoration: BoxDecoration(
          image: DecorationImage(image: provider, fit: BoxFit.cover),
        ),
        ink: _inkFor(skin.ink, colors),
        scrim: skin.scrim > 0
            ? Colors.black.withValues(alpha: skin.scrim)
            : null,
      );
  }
}

/// The paint every bubble wore before skins existed: the theme's fill for
/// this side, its ink, and — on the receiving side only — the hairline that
/// separates a white bubble from the white board it sits on.
BubblePaint _themePaint(WeChatColors colors, bool outgoing) => BubblePaint(
  decoration: BoxDecoration(
    color: outgoing ? colors.bubbleOut : colors.bubbleIn,
    border: outgoing ? null : Border.all(color: colors.divider),
  ),
  ink: outgoing ? colors.bubbleOutText : colors.bubbleText,
);

/// The ink a skin's content is drawn in.
///
/// Dark resolves to the theme's body text colour rather than a fixed black:
/// on the dark theme that colour is the light one, which is exactly what
/// "dark ink" cannot mean there — but a dark-ink skin is a *light* fill by
/// definition, so the near-black the light theme uses is still the right
/// answer, and `bubbleText` is the token that says "the colour words are
/// normally drawn in". White needs no token: it is white on both themes.
Color _inkFor(BubbleSkinInk ink, WeChatColors colors) =>
    ink == BubbleSkinInk.dark ? colors.bubbleText : Colors.white;

/// Where a gradient's colours start and end, per [BubbleGradientDirection].
({Alignment begin, Alignment end}) _gradientAxis(
  BubbleGradientDirection direction,
) => switch (direction) {
  BubbleGradientDirection.horizontal => (
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  ),
  BubbleGradientDirection.vertical => (
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),
  BubbleGradientDirection.diagonal => (
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
};

/// The image an [ImageBubbleSkin] paints, or null when it cannot be had.
///
/// Null is the missing-file case and only that: an asset that is not bundled
/// is a build error rather than a runtime state, so it is not checked here —
/// the preset table is the only writer of asset names and a typo in it fails
/// loudly at publish time, not silently at runtime. A *file* skin whose copy
/// has been deleted does happen — app data gets cleaned — and the answer to
/// it is the ordinary bubble, not an error the user has to fix.
ImageProvider? _imageProvider(ImageBubbleSkin skin) {
  switch (skin.source) {
    case BubbleSkinImageSource.asset:
      return AssetImage('assets/bubble_skins/${skin.name}');
    case BubbleSkinImageSource.file:
      final file = File(skin.name);
      if (!file.existsSync()) return null;
      return ResizeImage(FileImage(file), width: bubbleSkinDecodeWidth);
  }
}

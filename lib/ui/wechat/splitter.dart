import 'package:flutter/material.dart';

import 'theme.dart';

/// The divider between two panes, which the user drags to move it.
///
/// A splitter is a **line you can grab**, not a line you can see. The two
/// are different sizes on purpose: what is drawn is a hairline, the same
/// hairline the pane boundary was drawn with before this widget existed, and
/// what is *catchable* is a band around it — a hairline is one pixel wide and
/// a mouse cannot reliably find a one-pixel target.
///
/// The band is centred on the line, so the line the user aims at and the
/// line they see are the same place. The band is wider than the hairline on
/// purpose, and the hairline stays the width it always was: a wide visible
/// divider would be a stripe through the interface, and a messenger's
/// conversation reads as one continuous surface, not as two boxes.
///
/// The cursor says what the drag will do — `resizeColumn` — because the
/// gesture is not obvious otherwise, and a user who does not know a line can
/// be dragged will never try.
class PaneSplitter extends StatefulWidget {
  /// Draws a splitter that drags [onDrag] by the number of pixels it moves.
  const PaneSplitter({super.key, required this.onDrag, this.enabled = true});

  /// Called with the number of pixels the pointer moved, horizontally.
  ///
  /// A delta rather than an absolute position: the caller owns the pane's
  /// width and its bounds, and a delta keeps the splitter from having to
  /// know where in the window it sits. Negative when the pointer moves left.
  final ValueChanged<double> onDrag;

  /// Whether the splitter can be dragged.
  ///
  /// False in a layout with no room to give: the splitter is still drawn, so
  /// the boundary still reads as one, but it does not pretend to be
  /// draggable.
  final bool enabled;

  @override
  State<PaneSplitter> createState() => _PaneSplitterState();
}

class _PaneSplitterState extends State<PaneSplitter> {
  /// Whether the pointer is over the splitter right now.
  ///
  /// The hover look is a lighter tint of the line's own colour; the held
  /// look is the brand green. Two states rather than one, because "this can
  /// be dragged" and "this *is* being dragged" are different things to say
  /// to a user, and a line that only changed on the press would tell them
  /// the first only after they had already found it.
  bool _hovered = false;

  /// Whether the pointer is down on the splitter right now.
  ///
  /// Separate from the hover, and the reason the two are separate: a drag
  /// that leaves the band must still be a drag, so the *held* look has to
  /// survive the pointer going off it. Ending the drag on exit would drop
  /// the pane the moment the pointer outran the splitter.
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final enabled = widget.enabled;
    final line = _held
        ? colors.brand
        : (_hovered && enabled
              ? Color.lerp(colors.divider, colors.brand, 0.45)!
              : colors.divider);
    return MouseRegion(
      cursor: enabled ? WeChat.splitterCursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: enabled ? (_) => _start() : null,
        onHorizontalDragUpdate: enabled ? _update : null,
        onHorizontalDragEnd: enabled ? (_) => _end() : null,
        onHorizontalDragCancel: enabled ? _end : null,
        child: SizedBox(
          width: WeChat.splitterWidth,
          // Full height: the boundary between the panes runs the whole
          // height of the window, so the whole of it is catchable. A handle
          // in the middle would be a thing to hunt for.
          child: Center(
            // The line is one pixel and stays one pixel: a wide visible
            // divider would be a stripe through the interface, and a
            // messenger's conversation reads as one surface, not as two
            // boxes. What the pointer is over is the band around it, and
            // what the user sees is the line inside it. Only the *colour*
            // changes, so the splitter announces itself by becoming the
            // brand colour rather than by becoming wider.
            child: SizedBox(
              width: 1,
              height: double.infinity,
              child: ColoredBox(color: enabled ? line : colors.divider),
            ),
          ),
        ),
      ),
    );
  }

  void _start() {
    setState(() => _held = true);
  }

  void _update(DragUpdateDetails details) {
    widget.onDrag(details.primaryDelta ?? 0);
  }

  void _end() {
    setState(() => _held = false);
  }
}

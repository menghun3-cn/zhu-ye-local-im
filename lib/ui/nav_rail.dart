import 'package:flutter/material.dart';

import 'wechat/theme.dart';

/// One entry of the rail: a glyph, a word, and a count worth interrupting for.
///
/// The rail's own type rather than [NavigationRailDestination], because the
/// rail's destinations are not Material's any more — there is one glyph (the
/// rail does not swap it for a filled one when the entry becomes current) and
/// there is a count, which Material's type has no slot for.
class NavRailDestination {
  const NavRailDestination({
    required this.icon,
    required this.label,
    this.badge = 0,
  });

  /// The glyph above the word.
  final IconData icon;

  /// The word under the glyph.
  final String label;

  /// How many Transfers are waiting for an answer, or zero for none.
  final int badge;
}

/// The way between the six surfaces, drawn here rather than borrowed.
///
/// [NavigationRail] cannot be told this design's current-surface marker, and the
/// rest follows from that. The component draws the marker as a 56 × 32 stadium
/// behind the *icon* alone, where the design
/// (`design-preview/conversation.html`) makes the current entry one block with
/// its word inside it — `indicatorShape` swaps the shape but not the size, and
/// the size is a private constant of the component
/// (`_kCircularIndicatorDiameter`, `_kIndicatorHeight`). A marker that belongs
/// to the whole entry has to be painted over the entry, so the entries have to
/// be ours; and a column of our own entries is also what puts the product's mark
/// above the six and the space between the four surfaces and the two tools. The
/// component's own slots are no way out: `leading` and `trailing` hold widgets
/// rather than destinations, and its `destinations` is one run with no break in
/// the middle.
///
/// So this file draws the rail. The price is a column, a spacer, and a
/// [Material] per entry; what it buys is that the rail in the window and the
/// rail in the draft are the same picture, which is the one thing a screenshot
/// comparison can check.
///
/// The entries arrive as one ordered list from the shell, which hands the same
/// list to a narrow window's [NavigationBar] — so the order has one source and
/// the two layouts cannot drift apart.
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.pinnedCount = 0,
    this.status,
    this.trailing,
  });

  /// Which destination is the current surface: an index into [destinations].
  final int selectedIndex;

  /// What pressing destination [index] does.
  final ValueChanged<int> onDestinationSelected;

  /// The entries, in the order they are drawn.
  final List<NavRailDestination> destinations;

  /// How many of the trailing entries hang at the foot of the rail.
  ///
  /// The design splits the six into the four surfaces and the two tools
  /// (设置 / 关于) with nothing between them but space: the tools are what a
  /// visitor does once, and a rail that runs them straight on from the surfaces
  /// gives "where the app ends" and "how to configure it" one position in one
  /// list. Counting from the end, rather than being handed a second list, keeps
  /// the shell's single ordered list single.
  final int pinnedCount;

  /// A compact status block below the brand mark.
  ///
  /// It is not a destination: it reports the network's presence and hands the
  /// press to the shell, which opens the Devices surface. Null keeps the rail
  /// usable in a test or a caller that has nothing to report.
  final Widget? status;

  /// An entry below even the pinned ones — today, the update entry.
  ///
  /// Not a destination: pressing it hands a job to a surface instead of becoming
  /// one, which is why it is a widget here and not a seventh item. Null when
  /// there is nothing to say — null rather than an empty box, because the
  /// column's gap would be charged to the box.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    // The pinned entries are counted off the end. A rail asked to pin more than
    // it has pins all of them rather than failing: the list and the count come
    // from one caller, and that pair disagreeing is not a state worth a crash in
    // a paint callback.
    final pinned = pinnedCount < destinations.length
        ? pinnedCount
        : destinations.length;
    final firstPinned = destinations.length - pinned;
    return SizedBox(
      width: WeChat.railWidth,
      height: double.infinity,
      child: ColoredBox(
        color: colors.sidebarBackground,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WeChat.railHPadding,
            vertical: WeChat.railVPadding,
          ),
          child: Column(
            // Stretch, so every entry is as wide as the rail's inside: an entry
            // is a block, and a block that sized itself to its label would make
            // six blocks of three widths.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WeChat.railItemGap,
            children: [
              const _BrandMark(),
              ?status,
              for (var index = 0; index < firstPinned; index++) _entry(index),
              // The space between the surfaces and the tools. It goes to the
              // gap rather than to the entries, which is what makes the tools
              // read as a foot rather than as items four and five.
              const Spacer(),
              for (
                var index = firstPinned;
                index < destinations.length;
                index++
              )
                _entry(index),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  /// Destination [index], as the rail draws it.
  Widget _entry(int index) {
    final destination = destinations[index];
    return RailItem(
      icon: destination.icon,
      label: destination.label,
      badge: destination.badge,
      selected: index == selectedIndex,
      onTap: () => onDestinationSelected(index),
    );
  }
}

/// One entry of the rail: a glyph over a word, in one block that can be pressed.
///
/// Public, and found by its [label], so a test can name one entry and not its
/// neighbours: the shell keeps all six surfaces alive, and several of these
/// words are also headings inside the pages below. [ConversationRow] is public
/// for the same reason.
class RailItem extends StatefulWidget {
  const RailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  /// The glyph above the word.
  final IconData icon;

  /// The word under the glyph.
  final String label;

  /// Whether this entry is the surface on screen.
  final bool selected;

  /// How many Transfers are waiting for an answer, or zero for none.
  final int badge;

  /// What pressing it does.
  final VoidCallback onTap;

  @override
  State<RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<RailItem> {
  /// Whether the pointer is over this entry.
  ///
  /// Held here rather than left to an [InkWell]'s hover colour, because in this
  /// design the hover *is* the fill — [`listHover`], the same grey the
  /// conversation list uses — and it lifts the label's ink as well. An entry
  /// that is already current keeps its green under the pointer rather than
  /// turning grey: the draft's `[aria-current]` rule outranks its `:hover` rule,
  /// and neither an overlay nor a colour already chosen could say that.
  bool _hovered = false;

  /// Where the keyboard is, when it is here.
  ///
  /// A node of our own rather than the [InkWell]'s internal one, because the
  /// focus ring below is painted from it — see [_ring].
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Nothing else in the entry reads the node, so gaining and losing focus has
    // to ask for the repaint that draws the ring.
    _focus.addListener(_repaint);
  }

  void _repaint() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_repaint);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final fill = widget.selected
        ? colors.listSelected
        : _hovered
        ? colors.listHover
        : Colors.transparent;
    // The current entry wears the action green; every other one the same grey its
    // neighbours in the lists wear, darkening to the primary ink while the
    // pointer is on it.
    final ink = widget.selected
        ? colors.brandStrong
        : _hovered
        ? colors.bubbleText
        : colors.secondaryText;
    return Semantics(
      container: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          // The fill belongs to the `Material` rather than to a `Container`
          // above the ink: a splash is painted on the nearest `Material`, and an
          // opaque layer between the two would hide the press.
          color: fill,
          borderRadius: BorderRadius.circular(WeChat.railItemRadius),
          child: InkWell(
            focusNode: _focus,
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(WeChat.railItemRadius),
            // Both of Material's own pointer and keyboard answers are off,
            // because this design answers with the fill (above) and the ring
            // below instead of with an overlay.
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            splashColor: colors.listHover,
            highlightColor: colors.listHover,
            child: Container(
              // A foreground decoration, so the ring is painted *over* the
              // block without taking part in its layout: as a `border` in the
              // decoration below it would also become padding, and the glyph and
              // the word would shift two pixels the moment the keyboard arrived.
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(WeChat.railItemRadius),
                border: _focus.hasFocus
                    ? Border.all(color: colors.brandStrong, width: 2)
                    : null,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: WeChat.railItemPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The count rides on the glyph, as it does in the bar: a
                  // Transfer waiting for an answer is the one thing on this rail
                  // worth interrupting for, and it now has two places to be
                  // answered from.
                  Badge.count(
                    count: widget.badge,
                    isLabelVisible: widget.badge > 0,
                    child: Icon(
                      widget.icon,
                      size: WeChat.railIconSize,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: WeChat.railIconLabelGap),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: WeChat.railLabelSize,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark at the head of the rail: the bamboo-leaf talk bubble.
///
/// A `CustomPaint` rather than an `Icon`, because the glyph is this product's
/// rather than Material's: the nearest Material stand-in (`Icons.eco`) is a leaf
/// without the bubble, which is a different picture at the one size where a
/// reader sees it right under the window's own icon. The path below is the
/// draft's, transcribed command for command out of its 24 × 24 drawing box
/// (`design-preview/index.html`, the same mark its title bar and rail carry).
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: WeChat.railBrandGap),
      child: SizedBox(
        height: WeChat.railBrandBox,
        child: Center(
          child: SizedBox.square(
            dimension: WeChat.railBrandMark,
            child: CustomPaint(
              painter: _BrandMarkPainter(color: colors.brandStrong),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints [_BrandMark]'s glyph, scaled from the 24 × 24 box it was drawn in.
///
/// The stroke scales with the box, which is what the draft does: its mark is the
/// same path at 26 pixels, not a path redrawn for 26.
class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({required this.color});

  final Color color;

  /// The width of the line, measured in the 24 × 24 box the path was drawn in —
  /// the draft's own `stroke-width`.
  static const double strokeWidth = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(12, 3)
      ..relativeCubicTo(5, 0, 9, 3, 9, 7)
      ..relativeCubicTo(0, 4, -4, 7, -9, 7)
      ..relativeCubicTo(-1.2, 0, -2.4, -0.12, -3.5, -0.35)
      ..lineTo(4, 20)
      ..relativeLineTo(1.2, -3.2)
      ..cubicTo(3.8, 15.5, 3, 13.8, 3, 12)
      ..relativeCubicTo(0, -4, 4, -9, 9, -9)
      ..close();
    canvas
      ..save()
      ..scale(size.width / 24)
      ..drawPath(path, paint)
      ..drawLine(const Offset(8.5, 10.5), const Offset(15.5, 10.5), paint)
      ..drawLine(const Offset(8.5, 13.5), const Offset(12.5, 13.5), paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

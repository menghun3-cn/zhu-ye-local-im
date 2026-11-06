import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/nav_rail.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// The rail itself: the picture, rather than what a press does.
///
/// [AppNavRail] is drawn here instead of borrowed from Material, so the three
/// things it has to get right are three things no theme assertion could reach:
/// the two groups the design splits the six entries into, the whole-entry block
/// that marks the current surface, and the pointer and keyboard answers an entry
/// gives. Each is held to the draft's own numbers
/// (`design-preview/styles.css`), mirrored as [WeChat]'s rail tokens — a token
/// that drifts from the draft fails here rather than in a screenshot nobody
/// compares.
///
/// What pressing the update entry *does* is a different question and lives in
/// `update_rail_test.dart`.
void main() {
  /// The rail in the one window under test.
  Finder rail() => windowA.within(find.byType(AppNavRail));

  /// [matching], restricted to the rail.
  ///
  /// Scoped, and it has to be: every label on the rail is also a heading inside
  /// the surface below it — 「关于」 is both the last destination and the About
  /// card's own title.
  Finder inRail(Finder matching) =>
      find.descendant(of: rail(), matching: matching);

  /// The one entry labelled [label], as the block that can be pressed.
  Finder item(String label) => find.ancestor(
    of: inRail(find.text(label)),
    matching: find.byType(RailItem),
  );

  /// The block behind [label] — the `Material` whose fill is the entry's colour.
  Material block(WidgetTester tester, String label) => tester.widget<Material>(
    find.descendant(of: item(label), matching: find.byType(Material)).first,
  );

  /// The ink [label]'s glyph is drawn in.
  Color? ink(WidgetTester tester, String label) => tester
      .widget<Icon>(
        find.descendant(of: item(label), matching: find.byType(Icon)),
      )
      .color;

  /// Whether the keyboard's ring is on [label]'s entry.
  bool focused(WidgetTester tester, String label) => tester
      .widget<InkWell>(
        find.descendant(of: item(label), matching: find.byType(InkWell)),
      )
      .focusNode!
      .hasFocus;

  testWidgets("is the app's own rail, with the three surfaces", (tester) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpWindow(tester, device);
    final colors = WeChatColors.light;

    // Nothing Material's is drawing this: the whole point of the file under test
    // is that the rail is the draft's picture rather than the component's. The
    // rail also paints the sidebar grey itself, having no theme slot left to
    // read it from.
    expect(windowA.within(find.byType(NavigationRail)), findsNothing);
    final background = tester.widget<ColoredBox>(
      find.descendant(of: rail(), matching: find.byType(ColoredBox)).first,
    );
    expect(background.color, colors.sidebarBackground);

    // The three surfaces are laid out in order with consistent spacing.
    double y(String label) => tester.getCenter(inRail(find.text(label))).dy;
    final pitch = y(l10n.tabTransfers) - y(l10n.tabConversation);
    expect(y(l10n.tabMy) - y(l10n.tabTransfers), closeTo(pitch, 0.01));

    // The last entry is visible and has some space below it.
    final railBox = tester.getRect(rail());
    final myBox = tester.getRect(item(l10n.tabMy));
    expect(myBox.bottom, lessThan(railBox.bottom));

    // Above the first entry sits the product's own mark, not an icon: it is the
    // rail's first `CustomPaint`, it is the draft's 26 pixels square, and it is
    // clear of the entries below it.
    final marker = inRail(find.byType(CustomPaint)).first;
    expect(
      tester.getSize(marker),
      const Size(WeChat.railBrandMark, WeChat.railBrandMark),
    );
    expect(
      tester.getRect(marker).bottom,
      lessThan(tester.getRect(item(l10n.tabConversation)).top),
    );

    await shutdown(tester, [device]);
  });

  testWidgets(
    'marks the current surface with the whole entry, not a pill behind the glyph',
    (tester) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      final colors = WeChatColors.light;

      // The current entry is filled with the soft green the lists use, and its
      // ink is the action green; every other entry is unfilled.
      expect(block(tester, l10n.tabConversation).color, colors.listSelected);
      expect(ink(tester, l10n.tabConversation), colors.brandStrong);
      expect(block(tester, l10n.tabTransfers).color, Colors.transparent);
      expect(ink(tester, l10n.tabTransfers), colors.secondaryText);

      // The block is the rail's whole inside width ...
      final blockRect = tester.getRect(item(l10n.tabConversation));
      expect(
        blockRect.width,
        closeTo(WeChat.railWidth - 2 * WeChat.railHPadding, 0.01),
      );
      // ... and it holds both halves of the entry. Material's own rail marks the
      // current destination with a 56 × 32 stadium behind the glyph alone — the
      // size its `_kCircularIndicatorDiameter` and `_kIndicatorHeight` fix — which
      // would leave the word outside the marker. This is the assertion that it
      // does not.
      expect(
        blockRect.contains(
          tester.getCenter(inRail(find.byIcon(Icons.forum_outlined))),
        ),
        isTrue,
        reason: 'the glyph is inside the block',
      );
      expect(
        blockRect.contains(
          tester.getCenter(inRail(find.text(l10n.tabConversation))),
        ),
        isTrue,
        reason: 'and so is the word',
      );

      await shutdown(tester, [device]);
    },
  );

  testWidgets(
    'lifts the entry under the pointer, and leaves the current one green',
    (tester) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      final colors = WeChatColors.light;

      // One pointer for the whole walk. A second `addPointer` in the same test
      // is a second pointer the tracker was never told to forget, and it
      // asserts.
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await tester.pump();

      // Onto an entry that is not the current one: the fill is the list's hover
      // grey and the ink lifts to the primary. Both halves matter — a hover that
      // only filled the block would leave the word washed out on top of it.
      await pointer.moveTo(
        tester.getCenter(inRail(find.text(l10n.tabTransfers))),
      );
      await tester.pump();
      expect(block(tester, l10n.tabTransfers).color, colors.listHover);
      expect(ink(tester, l10n.tabTransfers), colors.bubbleText);

      // Onto the current one: it keeps the green it already had rather than
      // taking the grey. The draft's `[aria-current]` rule outranks its `:hover`
      // one, and this is the only place that ordering can be seen.
      await pointer.moveTo(
        tester.getCenter(inRail(find.text(l10n.tabConversation))),
      );
      await tester.pump();
      expect(block(tester, l10n.tabConversation).color, colors.listSelected);
      expect(ink(tester, l10n.tabConversation), colors.brandStrong);

      // And the entry the pointer left goes back to being nothing at all.
      expect(block(tester, l10n.tabTransfers).color, Colors.transparent);
      expect(ink(tester, l10n.tabTransfers), colors.secondaryText);

      await shutdown(tester, [device]);
    },
  );

  testWidgets('is reachable by Tab, and Enter presses what the ring is on', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpWindow(tester, device);

    // The rail is the first thing in the window, so the walk in from nothing
    // lands on its first entry — and the ring is drawn from the entry's own
    // focus node, which is what makes this a test of that node rather than of
    // whatever `InkWell` does by itself.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused(tester, l10n.tabConversation), isTrue);

    // One step further, and the ring is on the second entry; Enter is a press.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused(tester, l10n.tabTransfers), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleRoute(tester);
    expect(selectedSurface(tester, window: windowA), transfersSurface);

    await shutdown(tester, [device]);
  });
}

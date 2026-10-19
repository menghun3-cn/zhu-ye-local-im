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

  testWidgets("is the app's own rail, with the tools hung at its foot", (
    tester,
  ) async {
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

    double y(String label) => tester.getCenter(inRail(find.text(label))).dy;
    final pitch = y(l10n.tabDevices) - y(l10n.tabConversation);

    // The four surfaces run on from one another at one pitch ...
    for (final pair in [
      [l10n.tabDevices, l10n.tabTransfers],
      [l10n.tabTransfers, l10n.tabClipboard],
    ]) {
      expect(
        y(pair[1]) - y(pair[0]),
        closeTo(pitch, 0.01),
        reason: '${pair[0]} → ${pair[1]} is one step, like the rest',
      );
    }
    // ... the two tools run on from one another at that same pitch ...
    expect(y(l10n.tabAbout) - y(l10n.tabSettings), closeTo(pitch, 0.01));
    // ... and the space between the two groups is more than one step of it. This
    // is the whole reason the rail is drawn rather than borrowed: Material packs
    // every destination into one top-aligned group and has no property that
    // separates two runs of them.
    expect(y(l10n.tabSettings) - y(l10n.tabClipboard), greaterThan(2 * pitch));

    // The tools hang off the foot: the last entry leaves the rail's own vertical
    // padding below it.
    final railBox = tester.getRect(rail());
    expect(
      railBox.bottom - tester.getRect(item(l10n.tabAbout)).bottom,
      closeTo(WeChat.railVPadding, 0.01),
    );

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
      expect(block(tester, l10n.tabDevices).color, Colors.transparent);
      expect(ink(tester, l10n.tabDevices), colors.secondaryText);

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
        tester.getCenter(inRail(find.text(l10n.tabClipboard))),
      );
      await tester.pump();
      expect(block(tester, l10n.tabClipboard).color, colors.listHover);
      expect(ink(tester, l10n.tabClipboard), colors.bubbleText);

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
      expect(block(tester, l10n.tabClipboard).color, Colors.transparent);
      expect(ink(tester, l10n.tabClipboard), colors.secondaryText);

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
    expect(focused(tester, l10n.tabDevices), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleRoute(tester);
    expect(selectedSurface(tester, window: windowA), devicesSurface);

    await shutdown(tester, [device]);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

void main() {
  group('the WeChat theme', () {
    test('names the slots Material would otherwise fill in itself', () {
      final theme = WeChat.theme();
      final scheme = theme.colorScheme;
      // Material's own light scheme, to compare against. Every assertion below
      // is "this is not merely what Material would have chosen": a slot left at
      // its default is a slot that renders in Material's palette, and one
      // lavender chip in an otherwise grey list is worse than a whole page of
      // the wrong theme.
      const material = ColorScheme.light();

      expect(
        scheme.secondaryContainer,
        isNot(material.secondaryContainer),
        reason: 'a tonal button would come out lavender',
      );
      expect(
        scheme.onSurfaceVariant,
        isNot(material.onSurfaceVariant),
        reason: 'every secondary label would come out purple-grey',
      );
      expect(
        scheme.outline,
        isNot(material.outline),
        reason: 'dividers and borders would come out purple-grey',
      );
      // A tinted surface would wash every flat white card towards the seed.
      expect(scheme.surfaceTint, Colors.transparent);
      expect(scheme.secondaryContainer, WeChat.listHover);
      expect(scheme.onSurfaceVariant, WeChat.secondaryText);

      expect(theme.cardTheme.color, WeChat.surface);
      // The scale's first shadow step: a card sitting perfectly flush on the
      // page reads as a table row, and one step is what lifts it off.
      expect(theme.cardTheme.elevation, 1);
      expect(theme.scaffoldBackgroundColor, WeChat.pageBackground);
      expect(theme.dividerColor, WeChat.divider);
      // The Chinese-first stack: Material's Roboto carries no Han glyphs, so
      // without this the font is whatever Windows happens to substitute.
      // `ThemeData.fontFamily` is a constructor parameter applied onto the
      // default text theme, not a readable field — so the assertion reads the
      // family off the body style that every page's text ends up inheriting.
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Microsoft YaHei UI');
    });

    test('a received bubble is the board\'s white, told apart by its line', () {
      // The board and a received bubble used to take each other's fills: a
      // white board, a grey bubble. The redesign gives the bubble the board's
      // own white and draws a hairline around it instead — a grey fill reads
      // as *disabled*, while a bordered white card is what a message looks
      // like. What is asserted is the new relationship, so that a later tweak
      // cannot leave a white bubble on a white board with nothing to see.
      expect(
        WeChat.conversationBackground,
        WeChat.surface,
        reason: 'the board is the same white as every other panel',
      );
      expect(
        WeChat.bubbleIn,
        WeChat.conversationBackground,
        reason: 'a received bubble is the board\'s own white now',
      );
      expect(
        WeChat.divider,
        isNot(WeChat.bubbleIn),
        reason: 'the hairline is the only thing keeping the bubble visible',
      );

      // A panel is still a panel: the bubble's fill must not have leaked into
      // the card, the dialog or the scheme's surface, which is what would
      // happen if the two roles still shared one token.
      final theme = WeChat.theme();
      expect(theme.cardTheme.color, WeChat.surface);
      expect(theme.dialogTheme.backgroundColor, WeChat.surface);
      expect(theme.colorScheme.surface, WeChat.surface);
    });

    test('paints the navigation surfaces in the WeChat greys', () {
      final theme = WeChat.theme();

      final rail = theme.navigationRailTheme;
      expect(rail.backgroundColor, WeChat.sidebarBackground);
      // The current surface wears the *action* green, the one every pressable
      // control uses, on a soft green pill.
      expect(rail.selectedIconTheme?.color, WeChat.brandStrong);
      expect(rail.indicatorColor, WeChat.brandSoft);
      expect(rail.unselectedIconTheme?.color, WeChat.secondaryText);

      final bar = theme.navigationBarTheme;
      expect(bar.backgroundColor, WeChat.toolbarBackground);
      expect(
        bar.indicatorColor,
        Colors.transparent,
        reason: 'the WeChat bar marks the current tab by tint, not by a pill',
      );
    });
  });

  group('the shell', () {
    testWidgets('a wide window offers the six surfaces and switches', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      // The window branch is a real decision the shell makes from its width,
      // so the wide branch is asserted rather than assumed.
      expect(
        windowA.within(find.byType(NavigationRail)),
        findsOneWidget,
        reason: 'a ${wideWindow.width}px window is a wide one',
      );
      expect(windowA.within(find.byType(NavigationBar)), findsNothing);

      await openTab(tester, l10n.tabTransfers, window: windowA);
      expect(selectedSurface(tester, window: windowA), transfersSurface);

      await openTab(tester, l10n.tabClipboard, window: windowA);
      expect(selectedSurface(tester, window: windowA), clipboardSurface);

      await openTab(tester, l10n.tabSettings, window: windowA);
      expect(selectedSurface(tester, window: windowA), settingsSurface);

      // Devices is second now, behind Conversations: talking to somebody is
      // what the app is for, and this surface is where that is set up.
      await openTab(tester, l10n.tabDevices, window: windowA);
      expect(selectedSurface(tester, window: windowA), devicesSurface);

      await openTab(tester, l10n.tabConversation, window: windowA);
      expect(selectedSurface(tester, window: windowA), conversationsSurface);

      await shutdown(tester, [device]);
    });

    testWidgets('a narrow window offers the same four as a bottom bar', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device, size: narrowWindow);

      expect(
        windowA.within(find.byType(NavigationBar)),
        findsOneWidget,
        reason: 'a ${narrowWindow.width}px window is a narrow one',
      );
      expect(windowA.within(find.byType(NavigationRail)), findsNothing);

      final bar = windowA.within(find.byType(NavigationBar));
      final labels = [
        // All six, Conversations first: a narrow window has no rail, so the
        // bar is the only way to reach a surface and a missing entry is a
        // surface with no way in at all.
        l10n.tabConversation,
        l10n.tabDevices,
        l10n.tabTransfers,
        l10n.tabClipboard,
        l10n.tabSettings,
        l10n.tabAbout,
      ];
      for (final label in labels) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
          reason: '$label has to be reachable from a narrow window too',
        );
      }

      await openTab(tester, l10n.tabSettings, window: windowA);
      expect(selectedSurface(tester, window: windowA), settingsSurface);

      await openTab(tester, l10n.tabConversation, window: windowA);
      expect(selectedSurface(tester, window: windowA), conversationsSurface);

      await shutdown(tester, [device]);
    });

    testWidgets('puts no title bar above the surfaces', (tester) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      // The window's own title bar carries the application's name, and this
      // Device's name belongs on the Devices surface with the rest of what this
      // Device says about itself. What used to be an `AppBar` holding those two
      // was a strip of chrome doing no work above six pages that had nothing to
      // do with either.
      expect(
        windowA.within(find.byType(AppBar)),
        findsNothing,
        reason: 'the shell draws no app bar at all',
      );
      expect(
        windowA.within(find.text(l10n.appTitle)),
        findsNothing,
        reason: 'the product name is in the title bar, not in the window',
      );

      // The Device's own name still has somewhere to be: the Devices surface,
      // which is where everything about this Device already lives.
      await openTab(tester, l10n.tabDevices, window: windowA);
      expect(windowA.within(find.text('Alice')), findsWidgets);

      // Renaming publishes a new descriptor and re-saves the profile, both of
      // which go through the real event loop, so this waits like the rest.
      await tester.runAsync(() => device.controller.rename('Alice the laptop'));
      await pumpUntil(
        tester,
        () =>
            windowA.within(find.text('Alice the laptop')).evaluate().isNotEmpty,
        description: 'the new name to reach the window',
      );

      await shutdown(tester, [device]);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

void main() {
  group('the WeChat theme', () {
    test('names the slots Material would otherwise fill in itself', () {
      final theme = WeChat.theme(WeChatColors.light);
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
      expect(scheme.secondaryContainer, WeChatColors.light.listHover);
      expect(scheme.onSurfaceVariant, WeChatColors.light.secondaryText);

      expect(theme.cardTheme.color, WeChatColors.light.surface);
      // The scale's first shadow step: a card sitting perfectly flush on the
      // page reads as a table row, and one step is what lifts it off.
      expect(theme.cardTheme.elevation, 1);
      expect(theme.scaffoldBackgroundColor, WeChatColors.light.pageBackground);
      expect(theme.dividerColor, WeChatColors.light.divider);
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
        WeChatColors.light.conversationBackground,
        WeChatColors.light.surface,
        reason: 'the board is the same white as every other panel',
      );
      expect(
        WeChatColors.light.bubbleIn,
        WeChatColors.light.conversationBackground,
        reason: 'a received bubble is the board\'s own white now',
      );
      expect(
        WeChatColors.light.divider,
        isNot(WeChatColors.light.bubbleIn),
        reason: 'the hairline is the only thing keeping the bubble visible',
      );

      // A panel is still a panel: the bubble's fill must not have leaked into
      // the card, the dialog or the scheme's surface, which is what would
      // happen if the two roles still shared one token.
      final theme = WeChat.theme(WeChatColors.light);
      expect(theme.cardTheme.color, WeChatColors.light.surface);
      expect(theme.dialogTheme.backgroundColor, WeChatColors.light.surface);
      expect(theme.colorScheme.surface, WeChatColors.light.surface);
    });

    test('paints the navigation surfaces in the WeChat greys', () {
      final theme = WeChat.theme(WeChatColors.light);

      final rail = theme.navigationRailTheme;
      expect(rail.backgroundColor, WeChatColors.light.sidebarBackground);
      // The current surface wears the *action* green, the one every pressable
      // control uses, on a soft green pill.
      expect(rail.selectedIconTheme?.color, WeChatColors.light.brandStrong);
      expect(rail.indicatorColor, WeChatColors.light.brandSoft);
      expect(rail.unselectedIconTheme?.color, WeChatColors.light.secondaryText);

      final bar = theme.navigationBarTheme;
      expect(bar.backgroundColor, WeChatColors.light.toolbarBackground);
      expect(
        bar.indicatorColor,
        Colors.transparent,
        reason: 'the WeChat bar marks the current tab by tint, not by a pill',
      );
    });
  });

  group('the dark palette', () {
    test('is a palette, not an inversion', () {
      const dark = WeChatColors.dark;

      // The identifying green is lifted until it holds against near-black
      // paper, and the *action* green catches up to it: on a bright green that
      // can be read, the two roles converge.
      expect(dark.brand, const Color(0xFF12D06C));
      expect(dark.brandStrong, dark.brand);

      // The same relationships as the light page, not the same values: the
      // panel is still *lighter* than the page it is raised above, and the
      // sidebar still sits between the two.
      expect(
        dark.pageBackground.computeLuminance(),
        lessThan(dark.sidebarBackground.computeLuminance()),
        reason: 'the sidebar is a step above the page, as it is in light mode',
      );
      expect(
        dark.sidebarBackground.computeLuminance(),
        lessThan(dark.conversationBackground.computeLuminance()),
        reason: 'the board is a step above the sidebar',
      );
      expect(
        dark.pageBackground.computeLuminance(),
        lessThan(dark.surface.computeLuminance()),
        reason: 'a card is a panel, and a panel is lighter than the page',
      );
      expect(
        dark.conversationBackground,
        dark.surface,
        reason: 'the board keeps the panel fill it has in light mode',
      );
    });

    test('flips the bubble rule: the board is lighter than its page', () {
      const dark = WeChatColors.dark;
      const light = WeChatColors.light;

      // A received bubble is *brighter* than the board under it in dark mode —
      // the opposite of the light page, where the white bubble needs a hairline
      // to be seen on a white board. The fill does the work here instead.
      expect(
        dark.bubbleIn.computeLuminance(),
        greaterThan(dark.conversationBackground.computeLuminance()),
        reason: 'a received bubble is a notch brighter than the board',
      );
      expect(
        dark.divider,
        isNot(dark.bubbleIn),
        reason: 'the hairline is still a line, not the bubble itself',
      );
      expect(
        light.bubbleIn.computeLuminance(),
        equals(light.conversationBackground.computeLuminance()),
        reason: 'in light mode the two are the same white, told apart by line',
      );
    });

    test('the ink on the bright green flips with the paper', () {
      // White on `#0A7E43` is fine; white on the dark theme's `#12D06C` is not.
      // The *same slot* therefore carries two inks, and a widget that named one
      // of them by hand would be unreadable in the other theme.
      expect(WeChatColors.light.onBrandStrong, Colors.white);
      expect(WeChatColors.dark.onBrandStrong, const Color(0xFF04220F));
      expect(
        WeChatColors.light.bubbleOutText,
        isNot(WeChatColors.dark.bubbleOutText),
        reason: 'the outgoing bubble is a different green on dark paper',
      );
    });

    test('builds a dark ColorScheme from the dark palette', () {
      final theme = WeChat.theme(WeChatColors.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.colorScheme.surface, WeChatColors.dark.surface);
      expect(theme.scaffoldBackgroundColor, WeChatColors.dark.pageBackground);
      expect(theme.dividerColor, WeChatColors.dark.divider);
      // The palette reaches every widget through the theme, not through a
      // constant: without the extension the lookup below would fall back to
      // the light page and half the app would stay white.
      expect(theme.extension<WeChatColors>(), WeChatColors.dark);
    });

    testWidgets('WeChatColors.of resolves to whichever theme is running', (
      tester,
    ) async {
      late WeChatColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeChat.theme(WeChatColors.light),
          darkTheme: WeChat.theme(WeChatColors.dark),
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              resolved = WeChatColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.brightness, Brightness.dark);
      expect(resolved, WeChatColors.dark);

      await tester.pumpWidget(
        MaterialApp(
          theme: WeChat.theme(WeChatColors.light),
          darkTheme: WeChat.theme(WeChatColors.dark),
          themeMode: ThemeMode.light,
          home: Builder(
            builder: (context) {
              resolved = WeChatColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.brightness, Brightness.light);
      expect(resolved, WeChatColors.light);
    });

    test('the halfway point of a theme change flips the brightness once', () {
      const light = WeChatColors.light;
      const dark = WeChatColors.dark;

      expect(light.lerp(dark, 0).brightness, Brightness.light);
      expect(light.lerp(dark, 0.49).brightness, Brightness.light);
      expect(light.lerp(dark, 0.5).brightness, Brightness.dark);
      expect(light.lerp(dark, 1).brightness, Brightness.dark);
      // The colours themselves fade rather than snap, so a window switching
      // themes does not flash.
      expect(light.lerp(dark, 0.5).surface, isNot(light.surface));
      expect(light.lerp(dark, 0.5).surface, isNot(dark.surface));
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/nav_rail.dart';
import 'package:local_transfer/ui/presence.dart';
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

    test('the colour face comes before the monochrome one', () {
      // The chain is a list, and its order is the whole mechanism: the first
      // font that has a glyph wins. `Segoe UI Symbol` covers every emoji code
      // point as a plain outline, so putting it in front turns every face
      // in the picker grey — a defect that no amount of looking at this
      // repository's diff would explain.
      const chain = WeChat.fontFamilyFallback;
      const colour = 'Segoe UI Emoji';
      const mono = 'Segoe UI Symbol';

      expect(
        chain,
        contains(colour),
        reason: 'the colour face is on the chain',
      );
      expect(chain, contains(mono), reason: 'the symbol face is on the chain');
      expect(
        chain.indexOf(colour),
        lessThan(chain.indexOf(mono)),
        reason: 'the colour face has to win the race',
      );
    });

    test('the styles Material builds for itself name the font too', () {
      final theme = WeChat.theme(WeChatColors.light);
      // `ThemeData.fontFamily` reaches the *default text theme* and nothing
      // else: a component style such as a button's own `textStyle` is a
      // standalone `TextStyle` that names no family, and
      // `AnimatedDefaultTextStyle` replaces the ambient style rather than
      // merging into it. A style that names no family therefore does not
      // inherit the theme's — it falls back to the platform's, which is a
      // different face with different Chinese coverage.
      final styles = <String, TextStyle?>{
        'a filled button': theme.filledButtonTheme.style?.textStyle?.resolve(
          <WidgetState>{},
        ),
        'a text button': theme.textButtonTheme.style?.textStyle?.resolve(
          <WidgetState>{},
        ),
        'a segmented button': theme.segmentedButtonTheme.style?.textStyle
            ?.resolve(<WidgetState>{}),
        'a list tile subtitle': theme.listTileTheme.subtitleTextStyle,
        'a chip label': theme.chipTheme.labelStyle,
        'a navigation label': theme.navigationBarTheme.labelTextStyle?.resolve(
          <WidgetState>{},
        ),
        'a field label': theme.inputDecorationTheme.labelStyle,
        'a field hint': theme.inputDecorationTheme.hintStyle,
      };
      styles.forEach((what, style) {
        expect(
          style?.fontFamily,
          WeChat.fontFamily,
          reason:
              '$what would draw in the platform default rather than in '
              'the theme\'s own face',
        );
        expect(
          style?.fontFamilyFallback,
          WeChat.fontFamilyFallback,
          reason: '$what needs the chain for the glyphs the first face lacks',
        );
      });
    });

    test('a received bubble is a soft grey on the board\'s white', () {
      // The two fills were the same white once, told apart by a hairline only —
      // which in a real window read as an outlined empty box rather than as a
      // message. The bubble now takes the palette's sunken step, so the fill
      // sets it off from the board on its own and the hairline is an edge
      // rather than the only evidence there is a bubble here. What is asserted
      // is the *relationship*, not the hex, so a later tweak cannot quietly put
      // the bubble back onto the board's own white.
      expect(
        WeChatColors.light.conversationBackground,
        WeChatColors.light.surface,
        reason: 'the board is the same white as every other panel',
      );
      expect(
        WeChatColors.light.bubbleIn,
        isNot(WeChatColors.light.conversationBackground),
        reason: 'a received bubble is no longer the board\'s own white',
      );
      expect(
        WeChatColors.light.bubbleIn.computeLuminance(),
        lessThan(WeChatColors.light.conversationBackground.computeLuminance()),
        reason: 'against a white board the bubble sits a step below it',
      );
      expect(
        WeChatColors.light.bubbleIn,
        isNot(WeChatColors.light.pageBackground),
        reason:
            'nor is it the page\'s grey, which is the alias that was tried '
            'and read as disabled',
      );
      expect(
        WeChatColors.light.divider,
        isNot(WeChatColors.light.bubbleIn),
        reason: 'the hairline is still an edge, not the bubble itself',
      );

      // A panel is still a panel: the bubble's fill must not have leaked into
      // the card, the dialog or the scheme's surface, which is what would
      // happen if the two roles still shared one token.
      final theme = WeChat.theme(WeChatColors.light);
      expect(theme.cardTheme.color, WeChatColors.light.surface);
      expect(theme.dialogTheme.backgroundColor, WeChatColors.light.surface);
      expect(theme.colorScheme.surface, WeChatColors.light.surface);
    });

    test('paints the navigation bar in the WeChat greys', () {
      // The rail is not here: it is drawn by the app rather than by Material, so
      // it takes its colours from the palette directly and has no theme slot to
      // pin. What is left in this theme is the bar a narrow window wears.
      final theme = WeChat.theme(WeChatColors.light);

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

    test('flips the bubble rule: set off from the board, either way', () {
      const dark = WeChatColors.dark;
      const light = WeChatColors.light;

      // The same job done in opposite directions, because the paper differs. On
      // dark paper a received bubble is *brighter* than the board under it; on
      // light paper it is *darker*, since the board is already the brightest
      // value the palette has and a bubble that matched it would be left to its
      // hairline. In both themes the fill is what separates the two.
      expect(
        dark.bubbleIn.computeLuminance(),
        greaterThan(dark.conversationBackground.computeLuminance()),
        reason: 'on dark paper the bubble is a notch brighter than the board',
      );
      expect(
        light.bubbleIn.computeLuminance(),
        lessThan(light.conversationBackground.computeLuminance()),
        reason: 'on white paper the bubble is a step darker than the board',
      );
      expect(
        dark.divider,
        isNot(dark.bubbleIn),
        reason: 'the hairline is still a line, not the bubble itself',
      );
    });

    test('a progress track is legible on every bubble it is drawn on', () {
      // The in-bubble track is the bubble's *own ink*, thinned, and this is why:
      // it lands on four different fills — the received and outgoing bubble in
      // each theme — and no single palette grey survives all four. The received
      // bubble simply *is* `surfaceSunken` in the light palette, so a track in
      // that colour disappears inside one, and on the dark page `surfaceSunken`
      // is within a step of `bubbleIn`, which is the same bug in a form nobody
      // had noticed. Derived from the ink, the track is a fixed distance from
      // whatever the bubble happens to be.
      for (final colors in [WeChatColors.light, WeChatColors.dark]) {
        final fills = {
          colors.bubbleIn: colors.bubbleText,
          colors.bubbleOut: colors.bubbleOutText,
        };
        fills.forEach((fill, ink) {
          final track = Color.alphaBlend(
            ink.withValues(alpha: WeChat.progressTrackAlpha),
            fill,
          );
          expect(
            (track.computeLuminance() - fill.computeLuminance()).abs(),
            greaterThan(0.02),
            reason: 'a track composited over $fill has to be visible on it',
          );
        });
      }
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
      // `MaterialApp` cross-fades one theme into the next, so the frame drawn
      // *on* the flip still carries the palette it is coming from — the lerp
      // the test above pins. Waiting the animation out is what makes this a
      // test of the lookup rather than of the interpolation.
      await tester.pump(const Duration(milliseconds: 400));

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
        windowA.within(find.byType(AppNavRail)),
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

    testWidgets('a narrow window offers the same six as a bottom bar', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device, size: narrowWindow);

      expect(
        windowA.within(find.byType(NavigationBar)),
        findsOneWidget,
        reason: 'a ${narrowWindow.width}px window is a narrow one',
      );
      expect(windowA.within(find.byType(AppNavRail)), findsNothing);

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

    testWidgets('the rail summarises presence and opens Devices', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      final summary = windowA.within(find.byType(ConnectionSummary));
      expect(summary, findsOneWidget);
      expect(
        windowA.within(find.text(l10n.presenceOnlineCount(1))),
        findsOneWidget,
      );
      expect(
        windowA.within(find.text(l10n.presenceOfflineCount(0))),
        findsOneWidget,
      );

      await tester.tap(summary);
      await settleRoute(tester);
      expect(selectedSurface(tester, window: windowA), devicesSurface);

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a narrow window puts presence above the bottom bar', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device, size: narrowWindow);

      final summary = windowA.within(find.byType(ConnectionSummary));
      final bar = windowA.within(find.byType(NavigationBar));
      expect(summary, findsOneWidget);
      expect(bar, findsOneWidget);
      expect(
        windowA.within(find.text(l10n.presenceSummaryEmpty)),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(summary).dy,
        lessThanOrEqualTo(tester.getTopLeft(bar).dy),
        reason: 'the summary belongs above the bar, not over the page',
      );

      await tester.tap(summary);
      await settleRoute(tester);
      expect(selectedSurface(tester, window: windowA), devicesSurface);

      await shutdown(tester, [device]);
    });

    testWidgets(
      'a narrow conversation keeps its back button below the system inset',
      (tester) async {
        const statusBar = EdgeInsets.only(top: 28);
        final hub = MemoryBeaconHub();
        final alice = await startUiDevice(tester, hub.a, 'Alice');
        final bob = await startUiDevice(tester, hub.b, 'Bob');
        await pairDevices(tester, alice, bob);
        await connectDevices(tester, alice, bob);
        await pumpWindow(tester, alice, size: narrowWindow, padding: statusBar);

        await openTab(tester, l10n.tabConversation, window: windowA);
        await pumpUntil(
          tester,
          () => conversationListed(windowA, 'Bob'),
          description: 'Bob to appear in the conversation list',
        );
        await openConversation(tester, windowA, name: 'Bob');

        final back = windowA.within(find.byIcon(Icons.arrow_back));
        expect(back, findsOneWidget);
        expect(
          tester.getTopLeft(back).dy,
          greaterThanOrEqualTo(statusBar.top),
          reason:
              'the shell has no AppBar, so its body must reserve the status '
              'bar before drawing the conversation header',
        );

        await tester.tap(back);
        await settleRoute(tester);
        expect(conversationListed(windowA, 'Bob'), isTrue);

        await shutdown(tester, [alice, bob]);
      },
    );

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

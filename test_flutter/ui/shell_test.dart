import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';

import '../support/ui_harness.dart';

void main() {
  group('the shell', () {
    testWidgets('a wide window offers the four surfaces and switches', (
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
        // All five, Conversations first: a narrow window has no rail, so the
        // bar is the only way to reach a surface and a missing entry is a
        // surface with no way in at all.
        l10n.tabConversation,
        l10n.tabDevices,
        l10n.tabTransfers,
        l10n.tabClipboard,
        l10n.tabSettings,
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

    testWidgets('names this Device and says it is unpaired', (tester) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      expect(windowA.within(find.text(l10n.appTitle)), findsOneWidget);
      expect(windowA.within(find.text('Alice')), findsWidgets);
      // The unpaired marker is what tells a user why nothing is reachable.
      expect(windowA.within(find.byTooltip(l10n.notPairedYet)), findsOneWidget);

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

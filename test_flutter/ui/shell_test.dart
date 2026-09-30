import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';

import '../support/ui_harness.dart';

void main() {
  group('the shell', () {
    testWidgets('a wide window offers the four surfaces and switches', (
      tester,
    ) async {
      final device = await startUiDevice(MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      // The window branch is a real decision the shell makes from its width,
      // so the wide branch is asserted rather than assumed.
      expect(
        windowA.within(find.byType(NavigationRail)),
        findsOneWidget,
        reason: 'a ${wideWindow.width}px window is a wide one',
      );
      expect(windowA.within(find.byType(NavigationBar)), findsNothing);

      await openTab(tester, 'Transfers', window: windowA);
      expect(selectedSurface(tester, window: windowA), transfersSurface);

      await openTab(tester, 'Clipboard', window: windowA);
      expect(selectedSurface(tester, window: windowA), clipboardSurface);

      await openTab(tester, 'Settings', window: windowA);
      expect(selectedSurface(tester, window: windowA), settingsSurface);

      await openTab(tester, 'Devices', window: windowA);
      expect(selectedSurface(tester, window: windowA), devicesSurface);

      await shutdown(tester, [device]);
    });

    testWidgets('a narrow window offers the same four as a bottom bar', (
      tester,
    ) async {
      final device = await startUiDevice(MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device, size: narrowWindow);

      expect(
        windowA.within(find.byType(NavigationBar)),
        findsOneWidget,
        reason: 'a ${narrowWindow.width}px window is a narrow one',
      );
      expect(windowA.within(find.byType(NavigationRail)), findsNothing);

      final bar = windowA.within(find.byType(NavigationBar));
      for (final label in ['Devices', 'Transfers', 'Clipboard', 'Settings']) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
          reason: '$label has to be reachable from a narrow window too',
        );
      }

      await openTab(tester, 'Settings', window: windowA);
      expect(selectedSurface(tester, window: windowA), settingsSurface);

      await shutdown(tester, [device]);
    });

    testWidgets('names this Device and says it is unpaired', (tester) async {
      final device = await startUiDevice(MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      expect(windowA.within(find.text('Local Transfer')), findsOneWidget);
      expect(windowA.within(find.text('Alice')), findsWidgets);
      // The unpaired marker is what tells a user why nothing is reachable.
      expect(
        windowA.within(find.byTooltip('Not paired with any Device yet')),
        findsOneWidget,
      );

      await device.controller.rename('Alice the laptop');
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

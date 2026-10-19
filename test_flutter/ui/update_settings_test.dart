import 'package:flutter/material.dart';
// `flutter_test` has a `TestWindow` of its own — an unrelated handle on the
// test's window — and the harness has one meaning a window under test. Only
// the harness's is used here, so the other is hidden rather than renamed.
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/settings_page.dart';

import '../support/ui_harness.dart';

/// What a restart would read for the update-check interval.
///
/// The stored JSON rather than the live profile the controller is holding: the
/// claim being checked is that the choice outlives the process, and the only
/// thing that outlives it is the file.
Future<Object?> _storedInterval(UiDevice device) async {
  final profile = (await device.store.load())?['profile'];
  return profile is Map<Object?, Object?>
      ? profile['updateCheckInterval']
      : null;
}

void main() {
  group('the update-check settings', () {
    testWidgets('offer the cadence, showing the hourly default the app ships', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsUpdate)),
        findsOneWidget,
      );
      expect(device.controller.updateCheckInterval, UpdateCheckInterval.hourly);
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(l10n.settingsPeriodicUpdateTitle),
        ),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsPeriodicUpdateOn)),
        findsOneWidget,
      );
      for (final label in [
        l10n.updateIntervalHourly,
        l10n.updateIntervalSixHours,
        l10n.updateIntervalDaily,
        l10n.updateIntervalThreeDays,
      ]) {
        expect(
          onPage(windowA, SettingsPage, find.text(label)),
          findsOneWidget,
          reason: '$label has to be offered',
        );
      }

      await shutdown(tester, [device]);
    });

    testWidgets('turn periodic checking off, and persist the choice', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      // Off is the user opting out of the background question: the switch is
      // the whole choice, and the cadence segment row goes with it.
      final periodicSwitch = onPage(
        windowA,
        SettingsPage,
        find.ancestor(
          of: find.text(l10n.settingsPeriodicUpdateTitle),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(periodicSwitch, findsOneWidget);
      await tester.tap(periodicSwitch);
      await pumpUntil(
        tester,
        () => device.controller.updateCheckInterval == UpdateCheckInterval.off,
        description: 'the periodic check to be turned off',
      );

      expect(device.controller.updateCheckInterval, UpdateCheckInterval.off);
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(l10n.settingsPeriodicUpdateOff),
        ),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.updateIntervalThreeDays)),
        findsNothing,
        reason: 'the cadence row is gone while the switch is off',
      );
      expect(
        await _storedInterval(device),
        UpdateCheckInterval.off.wireName,
        reason: 'the choice has to survive a restart',
      );

      await shutdown(tester, [device]);
    });

    testWidgets('let the cadence be changed and persist the choice', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      await tester.tap(
        onPage(windowA, SettingsPage, find.text(l10n.updateIntervalThreeDays)),
      );
      await pumpUntil(
        tester,
        () =>
            device.controller.updateCheckInterval ==
            UpdateCheckInterval.everyThreeDays,
        description: 'the cadence to reach the controller',
      );

      expect(
        device.controller.updateCheckInterval,
        UpdateCheckInterval.everyThreeDays,
      );
      expect(
        await _storedInterval(device),
        UpdateCheckInterval.everyThreeDays.wireName,
      );

      // And back to the shipped default, so that the choice is a choice rather
      // than a one-way door.
      await tester.tap(
        onPage(windowA, SettingsPage, find.text(l10n.updateIntervalHourly)),
      );
      await pumpUntil(
        tester,
        () =>
            device.controller.updateCheckInterval == UpdateCheckInterval.hourly,
        description: 'the cadence to be put back',
      );
      expect(
        await _storedInterval(device),
        UpdateCheckInterval.hourly.wireName,
      );

      await shutdown(tester, [device]);
    });
  });
}

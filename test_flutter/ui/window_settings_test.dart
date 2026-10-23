import 'package:flutter/material.dart';
// `flutter_test` has a `TestWindow` of its own — an unrelated handle on the
// test's window — and the harness has one meaning a window under test. Only the
// harness's is used here, so the other is hidden rather than renamed.
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/settings_page.dart';

import '../support/ui_harness.dart';

/// What a restart would read for the close button.
///
/// The stored JSON rather than the live profile the controller is holding: the
/// claim being checked is that the choice outlives the process, and the only
/// thing that outlives it is the file.
Future<Object?> _storedCloseBehaviour(UiDevice device) async {
  final profile = (await device.store.load())?['profile'];
  return profile is Map<Object?, Object?> ? profile['closeBehaviour'] : null;
}

/// The start-with-Windows switch, scoped to the window section.
///
/// The page also carries the update-check switch, so `find.byType` alone would
/// match two. The window's switch is the one whose title names the system.
Finder _startWithWindowsSwitch() => onPage(
  windowA,
  SettingsPage,
  find.ancestor(
    of: find.text(l10n.settingsStartWithWindows),
    matching: find.byType(SwitchListTile),
  ),
);

void main() {
  group('the window and startup settings', () {
    testWidgets('are absent on a platform that has no window of its own', (
      tester,
    ) async {
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        platform: DevicePlatform.android,
        controlsWindow: false,
      );
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      // Android has no notification area and no close button to give a meaning
      // to, so both controls would be rows with nothing behind them. Absent
      // rather than disabled: a surface that lists what a platform cannot do is
      // a surface that reads as broken.
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsWindowAndStartup)),
        findsNothing,
      );
      expect(_startWithWindowsSwitch(), findsNothing);
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.byType(SegmentedButton<CloseBehaviour>),
        ),
        findsNothing,
      );
      // The update-check section is a preference this platform *can* honour,
      // so it stays on the page alongside the rest of Settings.
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsUpdate)),
        findsOneWidget,
      );
      // The rest of the surface is still there, so this is an absence and not a
      // page that failed to build.
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsWhereThingsGo)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsNotices)),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('offer the close choice, showing the default the app ships', (
      tester,
    ) async {
      final host = ScriptedHostShell();
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        hostShell: host,
      );
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsWindowAndStartup)),
        findsOneWidget,
      );
      // The default is to keep running in the notification area, and it is the
      // window that has to be told so: the runner starts out hiding the window,
      // and a Device whose profile says otherwise says so before anything
      // slower happens.
      expect(device.controller.closeBehaviour, CloseBehaviour.minimiseToTray);
      expect(
        host.closeToTray,
        [true],
        reason:
            'the window is told what the close button means exactly once, '
            'as the Device comes up',
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsCloseToTrayHint)),
        findsOneWidget,
      );
      for (final label in [l10n.settingsCloseToTray, l10n.settingsCloseQuit]) {
        expect(
          onPage(windowA, SettingsPage, find.text(label)),
          findsOneWidget,
          reason: '$label has to be offered',
        );
      }

      await shutdown(tester, [device]);
    });

    testWidgets('carry the close choice to the window as well as the profile', (
      tester,
    ) async {
      final host = ScriptedHostShell();
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        hostShell: host,
      );
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      await tester.tap(
        onPage(windowA, SettingsPage, find.text(l10n.settingsCloseQuit)),
      );
      await pumpUntil(
        tester,
        () => device.controller.closeBehaviour == CloseBehaviour.quit,
        description: 'the chosen close behaviour to reach the controller',
      );

      // Both halves, in that order: the running window first, because that is
      // what the user is looking at, and the profile second, because that is
      // what a restart reads. A setter that wrote one and not the other would
      // leave the setting describing a window other than the one on screen.
      expect(host.closeToTrayNow, isFalse);
      expect(
        await _storedCloseBehaviour(device),
        CloseBehaviour.quit.wireName,
        reason: 'the choice has to survive a restart',
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsCloseQuitHint)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsCloseToTrayHint)),
        findsNothing,
        reason: 'the line under the choice describes one behaviour, not both',
      );

      // And back again, so that the choice is a choice rather than a one-way
      // door.
      await tester.tap(
        onPage(windowA, SettingsPage, find.text(l10n.settingsCloseToTray)),
      );
      await pumpUntil(
        tester,
        () => device.controller.closeBehaviour == CloseBehaviour.minimiseToTray,
        description: 'the close behaviour to be put back',
      );
      expect(host.closeToTray, [true, false, true]);
      expect(
        await _storedCloseBehaviour(device),
        CloseBehaviour.minimiseToTray.wireName,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('report what the host says about starting with the system', (
      tester,
    ) async {
      // A host that already starts with the system, put there by the user at
      // some point when the app was not running.
      final host = ScriptedHostShell(autostart: true);
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        hostShell: host,
      );
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      expect(device.controller.autostartEnabled, isTrue);
      expect(
        tester.widget<SwitchListTile>(_startWithWindowsSwitch()).value,
        isTrue,
      );
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(l10n.settingsStartWithWindowsOn),
        ),
        findsOneWidget,
      );
      // Nothing was asked: the answer was read off the operating system, which
      // is the only place that fact lives.
      expect(host.autostartRequests, isEmpty);

      await shutdown(tester, [device]);
    });

    testWidgets('turning starting-with-the-system on asks the host for it', (
      tester,
    ) async {
      final host = ScriptedHostShell();
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        hostShell: host,
      );
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      expect(host.autostart, isFalse);
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(l10n.settingsStartWithWindowsOff),
        ),
        findsOneWidget,
      );

      await tester.tap(_startWithWindowsSwitch());
      await pumpUntil(
        tester,
        () => device.controller.autostartEnabled,
        description: 'the switch to follow what the host now says',
      );

      expect(host.autostart, isTrue);
      expect(host.autostartRequests, [true]);
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(l10n.settingsStartWithWindowsOn),
        ),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('a write that does not take leaves the switch where it was', (
      tester,
    ) async {
      // A host whose write is refused — a locked-down registry key, or a second
      // copy of the app putting the entry back. It records the request and
      // keeps its own answer.
      final host = ScriptedHostShell()..refusesAutostartWrites = true;
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        hostShell: host,
      );
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      await tester.tap(_startWithWindowsSwitch());
      await pumpUntil(
        tester,
        () => host.autostartRequests.isNotEmpty,
        description: 'the host to be asked to start with the system',
      );
      // Give the read-back its turn: the switch must not stay on until the
      // host says it is on.
      await tester.pump();

      expect(host.autostart, isFalse);
      expect(
        device.controller.autostartEnabled,
        isFalse,
        reason: 'the switch reports what will happen, not what was asked for',
      );
      expect(
        tester.widget<SwitchListTile>(_startWithWindowsSwitch()).value,
        isFalse,
        reason:
            'an on switch that nothing is behind is the one lie this '
            'control could tell',
      );
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(l10n.settingsStartWithWindowsOff),
        ),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });
  });
}

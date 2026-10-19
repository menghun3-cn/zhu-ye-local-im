import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/update_notice.dart';

import '../support/ui_harness.dart';

/// The scheduled side of the update question: after the startup check the
/// notice asks again on the interval the Settings surface chose, and stops
/// when that choice is off.
///
/// The interval lives in the profile, so the notice is handed the controller
/// that read it — the same `attach` the application calls once the controller
/// has started. Asking again is counted through [ScriptedUpdateChecker], which
/// is the same seam the rest of the update tests use.
void main() {
  testWidgets('asks again on the profile interval, and not when it is off', (
    tester,
  ) async {
    final checker = ScriptedUpdateChecker.install(
      const UpdateCheck(UpdateOutcome.upToDate),
    );
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    final notice = UpdateNotice();
    addTearDown(notice.dispose);
    // The application asks once as it comes up, and then hands the notice the
    // controller whose profile says how often to ask again.
    await notice.check();
    notice.attach(device.controller);
    await tester.pump();

    expect(checker.asked, 1);

    // An hour is the shipped default: an hour minus a minute is still the one
    // startup answer, and crossing the hour is the first scheduled one.
    await tester.pump(const Duration(minutes: 59));
    expect(checker.asked, 1);
    await tester.pump(const Duration(minutes: 2));
    expect(checker.asked, 2);

    // Turning the background question off cancels the timer: two hours later
    // the count is unchanged.
    await device.controller.setUpdateCheckInterval(UpdateCheckInterval.off);
    await tester.pump();
    await tester.pump(const Duration(hours: 2));
    expect(checker.asked, 2);

    // A longer interval is a new cadence from the change, not a remainder of
    // the old one: nearly six hours pass quietly, and the sixth hour asks.
    await device.controller.setUpdateCheckInterval(
      UpdateCheckInterval.everySixHours,
    );
    await tester.pump();
    await tester.pump(const Duration(hours: 5, minutes: 59));
    expect(checker.asked, 2);
    await tester.pump(const Duration(minutes: 2));
    expect(checker.asked, 3);

    // Leave the timer stopped: a cadence still armed at the end of the test is
    // a timer the framework will fail the test for.
    await device.controller.setUpdateCheckInterval(UpdateCheckInterval.off);
    await tester.pump();
    await shutdown(tester, [device]);
  });
}

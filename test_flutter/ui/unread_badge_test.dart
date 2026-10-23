import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';

import '../support/ui_harness.dart';

void main() {
  testWidgets('unread messages raise and clear the taskbar marker', (
    tester,
  ) async {
    final hub = MemoryBeaconHub();
    final alice = await startUiDevice(tester, hub.a, 'Alice');
    final bob = await startUiDevice(tester, hub.b, 'Bob');
    await pairDevices(tester, alice, bob);
    await connectDevices(tester, alice, bob);
    await pumpWindow(tester, bob);

    bob.hostShell.emitWindowActivity(false);
    await tester.pump();
    await tester.pump();

    await sendText(tester, alice, 'message while hidden', to: bob.fingerprint);
    await pumpUntil(
      tester,
      () => bob.hostShell.unreadRequests.contains(true),
      description: 'the taskbar marker to appear for the unread message',
    );

    bob.hostShell.emitWindowActivity(true);
    await pumpUntil(
      tester,
      () =>
          bob.hostShell.unreadRequests.isNotEmpty &&
          bob.hostShell.unreadRequests.last == false,
      description: 'the taskbar marker to clear when the window is opened',
    );

    await shutdown(tester, [alice, bob]);
  });
}

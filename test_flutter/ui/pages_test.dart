import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/clipboard_page.dart';
import 'package:local_transfer/ui/pages/devices_page.dart';
import 'package:local_transfer/ui/pages/settings_page.dart';
import 'package:local_transfer/ui/pages/transfers_page.dart';

import '../support/ui_harness.dart';

void main() {
  group('the Devices surface', () {
    testWidgets('tells an unpaired Device why it can reach nobody', (
      tester,
    ) async {
      final device = await startUiDevice(MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      expect(
        onPage(
          windowA,
          DevicesPage,
          find.text('Pair this Device to send anything'),
        ),
        findsOneWidget,
      );
      expect(
        onPage(
          windowA,
          DevicesPage,
          find.textContaining('Nothing has been discovered yet'),
        ),
        findsOneWidget,
      );
      // The listening fact is the honest answer to "can anything reach me":
      // an unpaired Device binds no port and says so.
      expect(
        onPage(windowA, DevicesPage, find.text('not accepting Sessions')),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text('1 Device(s)')),
        findsOneWidget,
        reason: 'an unpaired Device is alone in its group',
      );
      // All three ways to pair, or to reach a Device without pairing.
      for (final label in ['Show a code', 'Enter a code', 'By address']) {
        expect(
          onPage(windowA, DevicesPage, find.text(label)),
          findsOneWidget,
          reason: '$label has to be offered',
        );
      }

      await shutdown(tester, [device]);
    });

    testWidgets('a paired Device shows its port and who it can reach', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(hub.a, 'Alice');
      final bob = await startUiDevice(hub.b, 'Bob');
      await pumpWindow(tester, alice);
      await pairDevices(alice, bob);

      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.text('Pair another Device'),
        ).evaluate().isNotEmpty,
        description: 'the pairing card to flip to its paired wording',
      );
      final port = alice.controller.listenPort!;
      expect(
        onPage(windowA, DevicesPage, find.text('on port $port')),
        findsOneWidget,
      );

      // Discovery has to have placed Bob with a port before he can be dialled,
      // and the card is where that shows up.
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.text('Connect'),
        ).evaluate().isNotEmpty,
        description: 'Bob to be offered as diallable',
      );
      expect(onPage(windowA, DevicesPage, find.text('Bob')), findsOneWidget);
      expect(
        onPage(windowA, DevicesPage, find.textContaining('Session open')),
        findsNothing,
        reason: 'nothing is connected yet',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('an open Session replaces Connect with the things to do', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(hub.a, 'Alice');
      final bob = await startUiDevice(hub.b, 'Bob');
      await pumpWindow(tester, alice);
      await pairDevices(alice, bob);
      await connectDevices(alice, bob);

      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.textContaining('Session open'),
        ).evaluate().isNotEmpty,
        description: 'the open Session to show on the peer card',
      );
      expect(
        onPage(windowA, DevicesPage, find.text('Connect')),
        findsNothing,
        reason: 'there is nothing left to connect',
      );
      expect(
        onPage(windowA, DevicesPage, find.byTooltip('Send')),
        findsOneWidget,
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('the Transfers surface', () {
    testWidgets('says nothing has moved yet', (tester) async {
      final device = await startUiDevice(MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, 'Transfers', window: windowA);

      expect(
        onPage(
          windowA,
          TransfersPage,
          find.text('Nothing has been sent or received yet.'),
        ),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('an outgoing Transfer shows the answer it waits for', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(hub.a, 'Alice');
      final bob = await startUiDevice(hub.b, 'Bob');
      await pumpWindow(tester, alice);
      await pairDevices(alice, bob);
      await connectDevices(alice, bob);

      await alice.controller.sendText('hello from Alice');
      await openTab(tester, 'Transfers', window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.text('Waiting for an answer'),
        ).evaluate().isNotEmpty,
        description: 'the Transfer to render with its state',
      );
      // Nothing has answered it, and the row says both what it is and who it
      // is with.
      expect(
        onPage(windowA, TransfersPage, find.text('To Bob · Text')),
        findsOneWidget,
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('an incoming offer is answered from this surface', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(hub.a, 'Alice');
      // The window is Bob's: he is the one who has to answer.
      final bob = await startUiDevice(hub.b, 'Bob');
      await pumpWindow(tester, bob);
      await pairDevices(alice, bob);
      await connectDevices(alice, bob);

      await alice.controller.sendText('answer me');
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the text',
      );
      await openTab(tester, 'Transfers', window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.text('Accept'),
        ).evaluate().isNotEmpty,
        description: 'the offer to render with its two answers',
      );
      expect(
        onPage(windowA, TransfersPage, find.text('Refuse')),
        findsOneWidget,
      );

      await tapButton(tester, 'Accept', window: windowA);
      // Accepting is not enough on its own: the folder has to be chosen.
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the folder dialog to open',
      );
      final incoming = tempDirectory('local-transfer-ui-in-');
      await fillField(tester, 'Folder', incoming.path, window: windowA);
      await tapDialogButton(tester, 'Accept into this folder', window: windowA);

      await pumpUntil(
        tester,
        () => bob.offers.single.state == TransferState.completed,
        description: 'the Transfer to complete',
      );
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.text('Done'),
        ).evaluate().isNotEmpty,
        description: 'the row to settle as done',
      );
      expect(
        onPage(windowA, TransfersPage, find.text('Accept')),
        findsNothing,
        reason: 'an answered offer offers its answers once',
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('the Clipboard surface', () {
    testWidgets('offers the three modes and follows the choice', (
      tester,
    ) async {
      final device = await startUiDevice(MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, 'Clipboard', window: windowA);

      for (final label in ['Off', 'Ask me', 'Mirror']) {
        expect(
          onPage(windowA, ClipboardPage, find.text(label)),
          findsOneWidget,
          reason: '$label has to be offered',
        );
      }
      // An unpaired Device is told where to go rather than left guessing.
      expect(
        onPage(windowA, ClipboardPage, find.textContaining('not in one yet')),
        findsOneWidget,
      );

      await tester.tap(onPage(windowA, ClipboardPage, find.text('Mirror')));
      await tester.pump();
      expect(device.controller.clipboardMode, ClipboardMode.mirror);
      expect(
        onPage(
          windowA,
          ClipboardPage,
          find.textContaining('replace this clipboard on their own'),
        ),
        findsOneWidget,
        reason: 'the line under the choice has to describe the new one',
      );

      await shutdown(tester, [device]);
    });

    testWidgets('a staged entry appears and is applied by hand', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(hub.a, 'Alice');
      // The window is Bob's: staging is what he has to answer.
      final bob = await startUiDevice(hub.b, 'Bob');
      await pumpWindow(tester, bob);
      await pairDevices(alice, bob);
      await connectDevices(alice, bob);
      alice.controller.setClipboardMode(ClipboardMode.mirror);
      bob.controller.setClipboardMode(ClipboardMode.stage);
      await openTab(tester, 'Clipboard', window: windowA);

      expect(
        onPage(
          windowA,
          ClipboardPage,
          find.text('Nothing is waiting to be applied.'),
        ),
        findsOneWidget,
      );

      alice.clipboard.copy('review me');
      // This is the whole point of the surface: an entry that has arrived turns
      // up on its own, without the user navigating away and back to refresh it.
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ClipboardPage,
          find.text('review me'),
        ).evaluate().isNotEmpty,
        description: 'the staged entry to appear unaided',
      );
      expect(
        onPage(windowA, ClipboardPage, find.text('Apply')),
        findsOneWidget,
      );

      await tester.tap(onPage(windowA, ClipboardPage, find.text('Apply')));
      await pumpUntil(
        tester,
        () => bob.clipboard.applied.contains('review me'),
        description: 'Bob to put the entry on his clipboard',
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('the Settings surface', () {
    testWidgets('reports what this Device is and where things go', (
      tester,
    ) async {
      final device = await startUiDevice(
        MemoryBeaconHub().a,
        'Alice',
        profilePath: 'C:/profiles/alice/profile.json',
        defaultIncomingDirectory: 'C:/downloads/LocalTransfer',
      );
      await pumpWindow(tester, device);
      await openTab(tester, 'Settings', window: windowA);

      expect(
        onPage(windowA, SettingsPage, find.text('This Device')),
        findsOneWidget,
      );
      expect(onPage(windowA, SettingsPage, find.text('Alice')), findsOneWidget);
      // The full Fingerprint, because it is the one thing a user can read out
      // loud to tell two Devices apart.
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(device.controller.self.fingerprint.hex),
        ),
        findsOneWidget,
      );
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text('C:/profiles/alice/profile.json'),
        ),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text('C:/downloads/LocalTransfer')),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text('Nothing has gone wrong.')),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('says so when there is nowhere to keep an identity', (
      tester,
    ) async {
      final device = await startUiDevice(MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, 'Settings', window: windowA);

      expect(
        onPage(windowA, SettingsPage, find.text('not stored on this Device')),
        findsOneWidget,
      );
      // A Device that will forget its pairing on restart has to say so, rather
      // than let the user find out the hard way.
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.textContaining('nowhere to keep its identity'),
        ),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text('no default folder')),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });
  });
}

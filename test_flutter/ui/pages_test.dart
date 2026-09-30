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
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      expect(
        onPage(windowA, DevicesPage, find.text(l10n.pairingCardUnpairedTitle)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.devicesEmptyHint)),
        findsOneWidget,
      );
      // The listening fact is the honest answer to "can anything reach me":
      // an unpaired Device binds no port and says so.
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.notAcceptingSessions)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.groupDevices(1))),
        findsOneWidget,
        reason: 'an unpaired Device is alone in its group',
      );
      // Both ways to pair — receiving, and reaching a Device without pairing.
      // There is no code to type anywhere: pairing is two taps.
      for (final label in [l10n.receiveAConnection, l10n.byAddress]) {
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
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, alice);
      await pairDevices(tester, alice, bob);

      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.text(l10n.pairingCardPairedTitle),
        ).evaluate().isNotEmpty,
        description: 'the pairing card to flip to its paired wording',
      );
      final port = alice.controller.listenPort!;
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.onPort(port))),
        findsOneWidget,
      );

      // Discovery has to have placed Bob with a port before he can be dialled,
      // and the card is where that shows up.
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.text(l10n.connect),
        ).evaluate().isNotEmpty,
        description: 'Bob to be offered as diallable',
      );
      expect(onPage(windowA, DevicesPage, find.text('Bob')), findsOneWidget);
      expect(
        onPage(windowA, DevicesPage, find.textContaining(l10n.sessionOpen)),
        findsNothing,
        reason: 'nothing is connected yet',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('an open Session replaces Connect with the things to do', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, alice);
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.textContaining(l10n.sessionOpen),
        ).evaluate().isNotEmpty,
        description: 'the open Session to show on the peer card',
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.connect)),
        findsNothing,
        reason: 'there is nothing left to connect',
      );
      expect(
        onPage(windowA, DevicesPage, find.byTooltip(l10n.send)),
        findsOneWidget,
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('the Transfers surface', () {
    testWidgets('says nothing has moved yet', (tester) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabTransfers, window: windowA);

      expect(
        onPage(windowA, TransfersPage, find.text(l10n.transfersEmptyHint)),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('an outgoing Transfer shows the answer it waits for', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, alice);
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      // Sending writes to a real socket, so it waits on the real event loop.
      await tester.runAsync(
        () => alice.controller.sendText('hello from Alice'),
      );
      await openTab(tester, l10n.tabTransfers, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.text(l10n.stateAwaitingDecision),
        ).evaluate().isNotEmpty,
        description: 'the Transfer to render with its state',
      );
      // Nothing has answered it, and the row says both what it is and who it
      // is with.
      expect(
        onPage(
          windowA,
          TransfersPage,
          find.text('${l10n.transferTo('Bob')} · ${l10n.kindText}'),
        ),
        findsOneWidget,
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('an incoming offer is answered from this surface', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      // The window is Bob's: he is the one who has to answer.
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, bob);
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      await tester.runAsync(() => alice.controller.sendText('answer me'));
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the text',
      );
      await openTab(tester, l10n.tabTransfers, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.text(l10n.accept),
        ).evaluate().isNotEmpty,
        description: 'the offer to render with its two answers',
      );
      expect(
        onPage(windowA, TransfersPage, find.text(l10n.refuse)),
        findsOneWidget,
      );

      await tapButton(tester, l10n.accept, window: windowA);
      // Accepting is not enough on its own: the folder has to be chosen.
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the folder dialog to open',
      );
      final incoming = tempDirectory('local-transfer-ui-in-');
      await fillField(tester, l10n.fieldFolder, incoming.path, window: windowA);
      await tapDialogButton(tester, l10n.acceptIntoFolder, window: windowA);

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
          find.text(l10n.stateCompleted),
        ).evaluate().isNotEmpty,
        description: 'the row to settle as done',
      );
      expect(
        onPage(windowA, TransfersPage, find.text(l10n.accept)),
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
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabClipboard, window: windowA);

      final modes = [
        l10n.clipboardModeOff,
        l10n.clipboardModeStage,
        l10n.clipboardModeMirror,
      ];
      for (final label in modes) {
        expect(
          onPage(windowA, ClipboardPage, find.text(label)),
          findsOneWidget,
          reason: '$label has to be offered',
        );
      }
      // An unpaired Device is told where to go rather than left guessing.
      expect(
        onPage(windowA, ClipboardPage, find.text(l10n.clipboardNeedsGroup)),
        findsOneWidget,
      );

      await tester.tap(
        onPage(windowA, ClipboardPage, find.text(l10n.clipboardModeMirror)),
      );
      await tester.pump();
      expect(device.controller.clipboardMode, ClipboardMode.mirror);
      expect(
        onPage(
          windowA,
          ClipboardPage,
          find.text(l10n.clipboardModeMirrorMeans),
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
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      // The window is Bob's: staging is what he has to answer.
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, bob);
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      alice.controller.setClipboardMode(ClipboardMode.mirror);
      bob.controller.setClipboardMode(ClipboardMode.stage);
      await openTab(tester, l10n.tabClipboard, window: windowA);

      expect(
        onPage(windowA, ClipboardPage, find.text(l10n.clipboardNothingStaged)),
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
        onPage(windowA, ClipboardPage, find.text(l10n.apply)),
        findsOneWidget,
      );

      await tester.tap(onPage(windowA, ClipboardPage, find.text(l10n.apply)));
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
        tester,
        MemoryBeaconHub().a,
        'Alice',
        profilePath: 'C:/profiles/alice/profile.json',
        defaultIncomingDirectory: 'C:/downloads/LocalTransfer',
      );
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabSettings, window: windowA);

      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsThisDevice)),
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
        onPage(windowA, SettingsPage, find.text(l10n.nothingWentWrong)),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('says so when there is nowhere to keep an identity', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabSettings, window: windowA);

      expect(
        onPage(windowA, SettingsPage, find.text(l10n.notStoredOnThisDevice)),
        findsOneWidget,
      );
      // A Device that will forget its pairing on restart has to say so, rather
      // than let the user find out the hard way.
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.noIdentityHint)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.noDefaultFolder)),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });
  });
}

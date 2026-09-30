import 'dart:io';

import 'package:flutter/material.dart';
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
      // Both ways to pair: answering requests, which is a standing state rather
      // than a step, and reaching a Device without pairing. There is no code to
      // type anywhere.
      for (final label in [l10n.acceptPairingRequests, l10n.byAddress]) {
        expect(
          onPage(windowA, DevicesPage, find.text(label)),
          findsOneWidget,
          reason: '$label has to be offered',
        );
      }
      // An unpaired Device that answers requests is already listening, and says
      // so: it is the answer to "can the other Device pair with me right now",
      // and it no longer depends on anybody opening a window.
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.pairingListening)),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('a paired Device shows its port and who it can reach', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      // Paired before either window exists: see [pairDevices], which answers the
      // request through the controller and would otherwise leave the question
      // sitting on Alice's screen.
      await pairDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      expect(
        onPage(windowA, DevicesPage, find.text(l10n.pairingCardPairedTitle)),
        findsOneWidget,
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
      // Set up before the window exists, so the request the Pairing starts is
      // answered by this test rather than left on Alice's screen; see
      // [pairDevices].
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

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

  group('answering Pairing requests', () {
    testWidgets('the switch takes the listener down and brings it back', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);

      // On from the moment the Device comes up: answering is a standing state,
      // not a step, so there is nothing to open.
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.text(l10n.pairingListening),
        ).evaluate().isNotEmpty,
        description: 'the card to report the listener',
      );
      final firstPort = device.controller.pairingPort;
      expect(firstPort, isNotNull);

      final switchTile = onPage(
        windowA,
        DevicesPage,
        find.byType(SwitchListTile),
      );
      await tester.tap(switchTile);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.text(l10n.pairingNotListening),
        ).evaluate().isNotEmpty,
        description: 'the card to report the listener going away',
      );
      // The port is what the other Device dials, so "off" has to mean gone
      // rather than merely unadvertised.
      expect(device.controller.acceptsPairingRequests, isFalse);
      expect(device.controller.pairingPort, isNull);

      await tester.tap(switchTile);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          DevicesPage,
          find.text(l10n.pairingListening),
        ).evaluate().isNotEmpty,
        description: 'the card to report the listener coming back',
      );
      expect(device.controller.acceptsPairingRequests, isTrue);
      expect(device.controller.pairingPort, isNotNull);

      await shutdown(tester, [device]);
    });

    testWidgets('the digits are not shown until the request is allowed', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, alice);

      // The dial is setup, so it goes through the controller — what is under
      // test is Alice's screen. It dials the port Alice actually bound rather
      // than the well-known one: a window's Pair button can only reach the
      // default port, and binding that here would collide with the other test
      // file that does, which `flutter test` runs alongside this one.
      late final Future<Object?> bobSaw;
      await tester.runAsync(() async {
        await untilTrue(
          () => alice.controller.isAcceptingPairings,
          'Alice to answer Pairing requests',
        );
        bobSaw = bob.controller
            .pairWith(
              host: InternetAddress.loopbackIPv4.address,
              port: alice.controller.pairingPort,
            )
            // Settled into a value here so the failure this test is waiting for
            // is never an unhandled error in the meantime.
            .then<Object?>((_) => null, onError: (Object error) => error);
      });

      // Alice is asked, and the question is the only thing she is shown: the
      // comparison is behind it, which is what keeps an unattended Device from
      // handing its group secret to whoever dialled it.
      await pumpUntil(
        tester,
        () => hasButton(tester, l10n.continuePairing, window: windowA),
        description: 'Alice to be asked about the request',
      );
      expect(
        hasButton(tester, l10n.theyMatch, window: windowA),
        isFalse,
        reason: 'the digits are behind the question',
      );

      await tapDialogButton(tester, l10n.refuse, window: windowA);

      await tester.runAsync(() async {
        expect(await bobSaw, isA<PairingException>());
      });
      expect(alice.controller.isPaired, isFalse);
      expect(bob.controller.isPaired, isFalse);
      // And Alice is still answering: refusing one request is not the same as
      // turning the listener off.
      expect(alice.controller.isAcceptingPairings, isTrue);

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
      // Set up before the window exists; see [pairDevices].
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

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

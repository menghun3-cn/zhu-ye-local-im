import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/clipboard_page.dart';
import 'package:local_transfer/ui/pages/devices_page.dart';
import 'package:local_transfer/ui/pages/transfers_page.dart';

import '../support/ui_harness.dart';

/// Two windows, two Devices, one machine, and nothing stubbed in between.
///
/// The widget tree is the real one, the controller is the real one, the Session
/// is a real loopback `ServerSocket` with a real handshake and real sealed
/// records, and the file that moves is a real file on disk. What is *not* real
/// is the network Discovery would use: two Devices on one host cannot share one
/// UDP broadcast port, which is a property of the machine rather than of the
/// product, so the beacon pair is an in-process hub. Everything downstream of
/// "these two Devices know about each other" is the shipping code path.
void main() {
  group('two windows on one machine', () {
    testWidgets('pair by a typed code, then move a file across', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      // Alice listens where the join dialog looks by default, which is what a
      // Device showing a code does in the shipped configuration. Bob is a
      // guest and can take any free port.
      final alice = await startUiDevice(
        tester,
        hub.a,
        'Alice',
        pairingPort: defaultPairingPort,
      );
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpTwoWindows(tester, alice, bob);

      await pairThroughWindows(
        tester,
        windowA,
        windowB,
        hostDevice: alice,
        guestDevice: bob,
      );

      // Both windows now say they are in a group, which is the user-visible
      // proof that the typed code did what it promised.
      for (final window in [windowA, windowB]) {
        await pumpUntil(
          tester,
          () => onPage(
            window,
            DevicesPage,
            find.text('Pair another Device'),
          ).evaluate().isNotEmpty,
          description: 'the pairing card to show a group in place',
        );
      }

      await connectThroughWindows(
        tester,
        windowA,
        windowB,
        fromDevice: alice,
        toDevice: bob,
      );

      // A file big enough to cross several chunks, so framing and reassembly
      // are on the path rather than one message that happens to fit.
      final home = tempDirectory('local-transfer-ui-out-');
      final source = File('${home.path}${Platform.pathSeparator}payload.bin');
      final bytes = Uint8List.fromList(
        List.generate(200 * 1024, (index) => (index * 31) % 256),
      );
      source.writeAsBytesSync(bytes);

      // Send it from Alice's window, through the menu a user would use.
      await openTab(tester, 'Devices', window: windowA);
      // The Session is up at the controller, but the peer card is a rendering
      // of it and the frame that opened the tab does not have to be the one
      // that carries it. Waiting for the card to offer Send is what a user
      // does — they look at the panel until the button is there.
      await pumpUntil(
        tester,
        () => windowA.within(find.byTooltip('Send')).evaluate().isNotEmpty,
        description: 'the connected peer card to offer Send',
      );
      await tester.tap(windowA.within(find.byTooltip('Send')));
      await settleRoute(tester);
      await tester.tap(windowA.within(find.text('Send a file')));
      await settleRoute(tester);
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the send-a-file dialog to open',
      );
      await fillField(tester, 'Path', source.path, window: windowA);
      await tapDialogButton(tester, 'Send', window: windowA);

      // Bob is offered it, and has to answer.
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      await openTab(tester, 'Transfers', window: windowB);
      await pumpUntil(
        tester,
        () => onPage(
          windowB,
          TransfersPage,
          find.text('Accept'),
        ).evaluate().isNotEmpty,
        description: 'the offer to reach Bob\u2019s window',
      );
      await tapButton(tester, 'Accept', window: windowB);
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowB),
        description: 'the folder dialog to open',
      );
      final incoming = tempDirectory('local-transfer-ui-in-');
      await fillField(tester, 'Folder', incoming.path, window: windowB);
      await tapDialogButton(tester, 'Accept into this folder', window: windowB);

      await pumpUntil(
        tester,
        () => bob.offers.single.state == TransferState.completed,
        description: 'the Transfer to complete',
      );
      await pumpUntil(
        tester,
        () => onPage(
          windowB,
          TransfersPage,
          find.text('Done'),
        ).evaluate().isNotEmpty,
        description: 'Bob\u2019s row to settle as done',
      );

      // The assertion that matters: the bytes that arrived are the bytes that
      // left, on the other side of a real socket.
      final written = File(
        '${incoming.path}${Platform.pathSeparator}payload.bin',
      );
      expect(written.existsSync(), isTrue);
      expect(written.readAsBytesSync(), bytes);

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a copy made in one window reaches the other clipboard', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(
        tester,
        hub.a,
        'Alice',
        pairingPort: defaultPairingPort,
      );
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpTwoWindows(tester, alice, bob);

      await pairThroughWindows(
        tester,
        windowA,
        windowB,
        hostDevice: alice,
        guestDevice: bob,
      );
      await connectThroughWindows(
        tester,
        windowA,
        windowB,
        fromDevice: alice,
        toDevice: bob,
      );

      // Both users turn Mirroring on from the Clipboard surface.
      for (final window in [windowA, windowB]) {
        await openTab(tester, 'Clipboard', window: window);
        await tester.tap(onPage(window, ClipboardPage, find.text('Mirror')));
        await tester.pump();
      }
      expect(alice.controller.clipboardMode, ClipboardMode.mirror);
      expect(bob.controller.clipboardMode, ClipboardMode.mirror);

      alice.clipboard.copy('copied on Alice');

      // Bob's clipboard takes it without being asked, and his surface says so.
      await pumpUntil(
        tester,
        () => bob.clipboard.applied.contains('copied on Alice'),
        description: 'Bob\u2019s clipboard to take the copy',
      );
      await pumpUntil(
        tester,
        () => onPage(
          windowB,
          ClipboardPage,
          find.text('copied on Alice'),
        ).evaluate().isNotEmpty,
        description: 'Bob\u2019s Clipboard surface to show it',
      );
      expect(await bob.clipboard.read(), 'copied on Alice');

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a Device outside the group is refused at the door', (
      tester,
    ) async {
      // Two groups on one machine. Carol dials Bob's address — the only thing
      // the Manual Address path gives up, since nothing was discovered to pin —
      // so the handshake is what has to turn her away.
      final alice = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        pairingPort: defaultPairingPort,
      );
      final bob = await startUiDevice(tester, MemoryBeaconHub().a, 'Bob');
      await pairDevices(tester, alice, bob);
      final carol = await startUiDevice(tester, MemoryBeaconHub().a, 'Carol');
      final dave = await startUiDevice(tester, MemoryBeaconHub().a, 'Dave');
      await pairDevices(tester, carol, dave);

      await pumpWindow(tester, carol);
      await openTab(tester, 'Devices', window: windowA);
      await tapButton(tester, 'By address', window: windowA);
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the address dialog to open',
      );
      await fillField(
        tester,
        'Address',
        InternetAddress.loopbackIPv4.address,
        window: windowA,
      );
      await fillField(
        tester,
        'Port',
        '${bob.controller.listenPort}',
        window: windowA,
      );
      await tapDialogButton(tester, 'Connect', window: windowA);

      // The refusal is reported in the dialog rather than swallowed, and no
      // Session is opened on either side.
      await pumpUntil(
        tester,
        () => windowA
            .within(find.textContaining('Could not reach the Device'))
            .evaluate()
            .isNotEmpty,
        description: 'the refusal to be shown to Carol',
      );
      expect(carol.controller.sessions, isEmpty);
      expect(bob.controller.sessions, isEmpty);

      await shutdown(tester, [alice, bob, carol, dave]);
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/clipboard_page.dart';
import 'package:local_transfer/ui/pages/transfers_page.dart';
import 'package:local_transfer/ui/pickers.dart';

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
///
/// Every label a window is driven through comes from [l10n] rather than from a
/// literal in this file: these tests are the only place the two Devices' whole
/// flows are driven the way a person drives them, so they are also the place
/// that would notice the UI coming up in a language nobody asked for.
void main() {
  group('two windows on one machine', () {
    testWidgets('pair by clicking, then move a file across', (tester) async {
      // The picker seam is a static, so it is put back however this test ends.
      // `addTearDown` and not `tearDown`: the latter declares a hook and only
      // works while the suite is still being declared, so calling it from
      // inside a test body throws "Can't call tearDown() once tests have begun
      // running" — which fails the test before a single line of it runs.
      addTearDown(PickerResolution.reset);
      final picker = ScriptedPicker.install();
      final hub = MemoryBeaconHub();
      // Alice receives, so she listens where the guest's Pair tap dials by
      // default, which is what a receiving Device does in the shipped
      // configuration. Bob is a guest and can take any free port.
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
      // proof that the two clicks did what they promised — and the Session the
      // guest opened after confirming is already up on both sides, so there is
      // nothing to dial by hand before sending.

      // A file big enough to cross several chunks, so framing and reassembly
      // are on the path rather than one message that happens to fit.
      final home = tempDirectory('local-transfer-ui-out-');
      final source = File('${home.path}${Platform.pathSeparator}payload.bin');
      final bytes = Uint8List.fromList(
        List.generate(200 * 1024, (index) => (index * 31) % 256),
      );
      source.writeAsBytesSync(bytes);
      picker.willOffer([source.path]);

      // Send it from Alice's conversation with Bob. The conversation list is
      // the way in — tapping a connected Device's row opens its thread — and
      // the attach button beside the composer is where a file is picked.
      await openTab(tester, l10n.tabConversation, window: windowA);
      // The Session is up at the controller, but the list is a rendering of it
      // and the frame that opened the tab does not have to be the one that
      // carries it. Waiting for the row to appear is what a user does — they
      // look at the list until it is there.
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the connected Device to appear in the conversation list',
      );
      await openConversation(tester, windowA, name: 'Bob');
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.byTooltip(l10n.menuSendFile),
        ).evaluate().isNotEmpty,
        description: 'the conversation to offer its attach button',
      );
      // The attach button opens the operating system's own file dialog, which
      // lives outside Flutter's event loop and never returns to a
      // `testWidgets` body. The picker is resolved through a seam for exactly
      // this reason, so what is driven here is the button a user presses and
      // everything after it: the classification of what came back, the offer,
      // the wire, and the file landing on the other side.
      await tester.tap(attachButton(windowA));
      await settleRoute(tester);
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('payload.bin'),
        ).evaluate().isNotEmpty,
        description: 'the picked file to appear in Alice\u2019s composer',
      );
      // Choosing a file is composing, not sending: the file waits in the box
      // and 发送 is what puts it on the wire.
      await tester.tap(sendButton(windowA));

      // Bob is offered it, and has to answer.
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      await openTab(tester, l10n.tabTransfers, window: windowB);
      await pumpUntil(
        tester,
        () => onPage(
          windowB,
          TransfersPage,
          find.text(l10n.accept),
        ).evaluate().isNotEmpty,
        description: 'the offer to reach Bob\u2019s window',
      );
      await tapButton(tester, l10n.accept, window: windowB);
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowB),
        description: 'the folder dialog to open',
      );
      final incoming = tempDirectory('local-transfer-ui-in-');
      await fillField(tester, l10n.fieldFolder, incoming.path, window: windowB);
      await tapDialogButton(tester, l10n.acceptIntoFolder, window: windowB);

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
          find.text(l10n.stateCompleted),
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
      // The Session the guest opened after confirming is already up on both
      // sides, so there is nothing to dial by hand before mirroring.
      for (final window in [windowA, windowB]) {
        await openTab(tester, l10n.tabClipboard, window: window);
        await tester.tap(
          onPage(window, ClipboardPage, find.text(l10n.clipboardModeMirror)),
        );
        await tester.pump();
      }
      expect(alice.controller.clipboardMode, ClipboardMode.mirror);
      expect(bob.controller.clipboardMode, ClipboardMode.mirror);

      // Pairing got these two into one Owner Group, and that is as far as it
      // goes: the clipboard is shared only with the Devices each side has
      // added to the list on the Clipboard surface, and that list starts empty.
      // Each Device adds the other, which is what the two users would do — done
      // through the controller rather than by ticking the boxes, because what
      // is under test *here* is that a copy crosses a real socket once the
      // consent exists, and the boxes themselves are covered by the Clipboard
      // surface's own widget test.
      alice.controller.setClipboardPeer(bob.fingerprint, value: true);
      bob.controller.setClipboardPeer(alice.fingerprint, value: true);
      await tester.pump();
      expect(alice.controller.isClipboardPeer(bob.fingerprint), isTrue);
      expect(bob.controller.isClipboardPeer(alice.fingerprint), isTrue);

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
      await openTab(tester, l10n.tabDevices, window: windowA);
      await tapButton(tester, l10n.byAddress, window: windowA);
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the address dialog to open',
      );
      await fillField(
        tester,
        l10n.fieldAddress,
        InternetAddress.loopbackIPv4.address,
        window: windowA,
      );
      await fillField(
        tester,
        l10n.fieldPort,
        '${bob.controller.listenPort}',
        window: windowA,
      );
      await tapDialogButton(tester, l10n.connect, window: windowA);

      // The refusal is reported in the dialog rather than swallowed, and no
      // Session is opened on either side. Matched on the sentence's frame
      // rather than in full: what follows the colon is the network's own
      // message, which is the operating system's word and not this app's.
      await pumpUntil(
        tester,
        () => windowA
            .within(find.textContaining(l10n.failureUnreachable('')))
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

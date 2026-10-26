import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `flutter_test` has a `TestWindow` of its own — an unrelated handle on the
// test's window — and the harness has one meaning a window under test. Only
// the harness's is used here, so the other is hidden rather than renamed.
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/clipboard_paste.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/pages/clipboard_page.dart';
import 'package:local_transfer/ui/pages/conversations_page.dart';
import 'package:local_transfer/ui/pages/devices_page.dart';
import 'package:local_transfer/ui/pages/settings_page.dart';
import 'package:local_transfer/ui/pages/transfers_page.dart';
import 'package:local_transfer/ui/pickers.dart';
import 'package:local_transfer/ui/reveal.dart';
import 'package:local_transfer/ui/wechat/bubble.dart';
import 'package:local_transfer/ui/wechat/image_bubble.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

Finder _settingsIdentityField(TestWindow window) =>
    onPage(window, SettingsPage, find.byType(TextFormField));

Finder _settingsIncomingField(TestWindow window) => onPage(
  window,
  SettingsPage,
  find.ancestor(
    of: find.byTooltip(l10n.changeIncomingFolder),
    matching: find.byType(TextField),
  ),
);

void main() {
  group('the Devices surface', () {
    testWidgets('explains that discovered Devices connect automatically', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      // Conversations leads the shell now, so this surface is offstage until it
      // is asked for. Every other group already opens its tab; this one used to
      // be the surface a window started on and got away without saying so.
      await openTab(tester, l10n.tabDevices, window: windowA);

      expect(
        onPage(windowA, DevicesPage, find.text(l10n.automaticConnectionsTitle)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.devicesEmptyHint)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.automaticConnectionsBody)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.automaticConnectionsReady)),
        findsOneWidget,
      );
      expect(
        onPage(
          windowA,
          DevicesPage,
          find.text(l10n.sessionsAutoConnectPending),
        ),
        findsOneWidget,
        reason: 'a Device with no group secret has no incoming Session yet',
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.groupDevices(1))),
        findsOneWidget,
      );
      // The platform did not report an address in this test, so the card says
      // that rather than leaving a blank line where the address belongs.
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.localIpUnavailable)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.byAddress)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.byType(SwitchListTile)),
        findsNothing,
        reason: 'automatic connections have no opt-out switch',
      );

      await shutdown(tester, [device]);
    });

    testWidgets('shows every local address above the listening line', (
      tester,
    ) async {
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        localAddresses: const ['192.168.1.24', '10.0.0.24'],
      );
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabDevices, window: windowA);

      expect(
        onPage(windowA, DevicesPage, find.text(l10n.localIpAddress)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text('192.168.1.24 · 10.0.0.24')),
        findsOneWidget,
        reason: 'the user can read the address another Device should dial',
      );

      await shutdown(tester, [device]);
    });

    testWidgets('the address dialog is drawn with the app\'s own controls', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabDevices, window: windowA);
      await tapButton(tester, l10n.byAddress, window: windowA);
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the address dialog to open',
      );

      // The fields are drawn from the theme, not from nothing: a bare field
      // with no outline is a blank strip a user has to guess is where the
      // address goes, which is what the complaint was. Read off the widget's
      // own decoration, so a theme the dialog stopped reading would fail here.
      final fields = tester.widgetList<TextField>(
        windowA.within(find.byType(TextField)),
      );
      expect(fields, hasLength(2), reason: 'an address and a port');
      for (final field in fields) {
        expect(
          field.decoration?.border,
          isNull,
          reason: 'the dialog leaves the border to the theme',
        );
        expect(
          field.decoration?.enabledBorder,
          isNull,
          reason: 'and to the theme again when it is not focused',
        );
      }
      expect(
        Theme.of(tester.element(windowA.within(find.byType(TextField)).first))
            .inputDecorationTheme
            .border,
        isA<OutlineInputBorder>(),
        reason: 'the theme is what fills that in',
      );

      // Both actions are real buttons rather than words: Cancel and Connect sit
      // in a row at the foot of a dialog, where a narrow word-shaped control is
      // the size of a link rather than of a decision. Cancel is a `TextButton`
      // and Connect the `FilledButton` that leads, which is the pattern every
      // dialog in this app uses.
      final cancel = find.widgetWithText(TextButton, l10n.cancel);
      final connect = find.widgetWithText(FilledButton, l10n.connect);
      expect(cancel, findsOneWidget, reason: 'Cancel has to be a button');
      expect(connect, findsOneWidget, reason: 'Connect has to be a button');
      for (final button in [cancel, connect]) {
        expect(
          tester.getSize(windowA.within(button)).height,
          greaterThanOrEqualTo(WeChat.buttonHeight),
          reason: 'a dialog action is a standard-sized control',
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
      // Trust is established by Discovery before either window exists.
      await pairDevices(tester, alice, bob);
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabDevices, window: windowA);

      expect(
        onPage(windowA, DevicesPage, find.text(l10n.automaticConnectionsTitle)),
        findsOneWidget,
      );
      final port = alice.controller.listenPort!;
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.onPort(port))),
        findsOneWidget,
      );

      // Discovery has to have placed Bob with a port before he can be dialled.
      // The card here says where he is; the button that dials lives in the
      // conversation list, so this surface is read first and the tab is changed
      // before the button is looked for.
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.connect)),
        findsNothing,
        reason: 'connecting is not done from this surface any more',
      );
      expect(onPage(windowA, DevicesPage, find.text('Bob')), findsOneWidget);

      // Bob is paired and therefore in the Owner Group, so the two Devices
      // connect on their own the moment Discovery places him: this surface is
      // read without asking for anything, and there is no Connect here to ask
      // with. The conversation list is where that state shows, and the test
      // below covers it.
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to appear in the conversation list',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('an open Session replaces Connect with the things to do', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      // Set up before the window exists; Discovery establishes trust and opens
      // the Session without a user decision.
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabDevices, window: windowA);

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
        reason: 'a connected peer has nothing left to connect on this surface',
      );
      // A Device this one is talking to is a Device to talk *to*: the card
      // offers its conversation, and the whole row opens it.
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.openConversation)),
        findsOneWidget,
      );
      // And the card keeps saying where that Device is. Following a Session
      // rather than a beacon is the point: Discovery restarts when the Session
      // layer comes up, and a card that fell back to "never seen" every time
      // that happened would lose the one address a user needs.
      expect(
        onPage(
          windowA,
          DevicesPage,
          find.textContaining(InternetAddress.loopbackIPv4.address),
        ),
        findsOneWidget,
      );
      expect(
        onPage(windowA, DevicesPage, find.text(l10n.neverSeen)),
        findsNothing,
        reason: 'a Device that is connected has plainly been seen',
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('automatic discovery connections', () {
    testWidgets('trust and connect without a confirmation surface', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpTwoWindows(tester, alice, bob);

      await waitForAutomaticConnection(
        tester,
        windowA,
        windowB,
        leftDevice: alice,
        rightDevice: bob,
      );
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to appear after connecting automatically',
      );

      expect(alice.controller.isPaired, isTrue);
      expect(bob.controller.isPaired, isTrue);
      expect(
        conversationHasButton(windowA, button: l10n.connect, name: 'Bob'),
        isFalse,
        reason: 'an open Session needs no retry',
      );
      expect(dialogIsOpen(windowA), isFalse);
      expect(dialogIsOpen(windowB), isFalse);

      await openTab(tester, l10n.tabDevices, window: windowA);
      expect(
        onPage(windowA, DevicesPage, find.byType(SwitchListTile)),
        findsNothing,
        reason: 'there is no request-answering preference to change',
      );
      expect(windowAutomaticConnectionsReady(tester, windowA), isTrue);

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

      // A file, because a text no longer waits: it is accepted on arrival, so
      // there would be no answer to show. This is the surface a *question*
      // shows up on, and only a file is still a question.
      //
      // Waited for, because `runAsync` cannot be re-entered: with the send
      // outstanding, the plain waits below would throw
      // "Reentrant call to runAsync() denied" rather than wait, and the refusal
      // that lets the send finish could never be reached. See [offerFile].
      //
      // Awaiting a send whose answer arrives later and "unfinished" rows do not
      // actually conflict: Bob lives in this test's tree, so the offer lands
      // while the send is blocked on it, and `reject` below is what releases
      // the send — leaving the tracked Transfer behind in a state the row can
      // still show.
      final home = tempDirectory('local-transfer-ui-out-');
      final source = File('${home.path}${Platform.pathSeparator}payload.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      await offerFile(tester, alice, source);
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
      // Nothing has answered it yet, so the row names the Device it is waiting
      // on and says what kind of thing it is. The bytes behind it are nought
      // because a file moves only once it is taken.
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.textContaining(l10n.transferTo('Bob')),
        ).evaluate().isNotEmpty,
        description: 'the row to name the Device on the other end',
      );
      expect(
        onPage(windowA, TransfersPage, find.textContaining(l10n.kindFiles)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, TransfersPage, find.text(l10n.stateAwaitingDecision)),
        findsWidgets,
      );

      // Answered before the test ends, so this leaves no Transfer half-decided
      // for a later teardown to trip over — and so the send, which has been
      // blocked on this very answer, can finish. Bob does the refusing; nobody
      // here asserts the outcome.
      //
      // Waited for, because the offer reaches Bob's controller over the real
      // socket and this line is the first thing that needs it to have arrived.
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      await tester.runAsync(() => bob.controller.reject(bob.offers.single));

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

      // A file: the offer that still needs answering.
      final home = tempDirectory('local-transfer-ui-out-');
      final source = File('${home.path}${Platform.pathSeparator}answer-me.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      await tester.runAsync(() => alice.controller.sendFile(source));
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
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
      // Bob was started with no folder to receive into, so accepting is not
      // enough on its own: the folder is the one thing left to ask. The test
      // after this one covers the Device that already has a folder.
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

    testWidgets(
      'accepting a file asks no second question when there is a folder to receive into',
      (tester) async {
        final hub = MemoryBeaconHub();
        final alice = await startUiDevice(tester, hub.a, 'Alice');
        // Bob knows where received files go: the answer the folder dialog would
        // have collected is already on the Device, so pressing 接收 had better
        // be the whole answer.
        final inbox = tempDirectory('local-transfer-accept-in-');
        final bob = await startUiDevice(
          tester,
          hub.b,
          'Bob',
          defaultIncomingDirectory: inbox.path,
        );
        await pumpWindow(tester, bob);
        await pairDevices(tester, alice, bob);
        await connectDevices(tester, alice, bob);

        final home = tempDirectory('local-transfer-accept-out-');
        final source = File(
          '${home.path}${Platform.pathSeparator}straight-in.bin',
        );
        source.writeAsBytesSync([for (var i = 0; i < 32; i++) i]);
        await tester.runAsync(() => alice.controller.sendFile(source));
        await pumpUntil(
          tester,
          () => bob.offers.isNotEmpty,
          description: 'Bob to be offered the file',
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

        await tapButton(tester, l10n.accept, window: windowA);
        await tester.pump();
        expect(
          dialogIsOpen(windowA),
          isFalse,
          reason: 'the folder is already known; the click is the whole answer',
        );
        await pumpUntil(
          tester,
          () => bob.offers.single.state == TransferState.completed,
          description: 'the Transfer to complete',
        );
        // The bytes land *after* the Transfer reports itself complete (the sink
        // closes and the staged file is renamed then), so the file on disk is
        // the thing to wait for rather than the state.
        final written = File(
          '${inbox.path}${Platform.pathSeparator}straight-in.bin',
        );
        await pumpUntil(
          tester,
          () => written.existsSync(),
          description: 'the file to land in the receiving folder',
        );
        expect(written.lengthSync(), 32);

        await shutdown(tester, [alice, bob]);
      },
    );
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
      // Both sides have added the other, the way two users do on this very
      // surface: pairing alone shares no clipboard.
      alice.controller.setClipboardPeer(bob.fingerprint, value: true);
      bob.controller.setClipboardPeer(alice.fingerprint, value: true);
      alice.controller.setClipboardMode(ClipboardMode.mirror);
      bob.controller.setClipboardMode(ClipboardMode.stage);
      await openTab(tester, l10n.tabClipboard, window: windowA);

      expect(
        onPage(windowA, ClipboardPage, find.text(l10n.clipboardNothingStaged)),
        findsOneWidget,
      );

      alice.clipboard.copy('review me'); // This is the whole point of the surface: an entry that has arrived turns
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

    testWidgets('lists the group and shares nothing until a box is ticked', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, bob);
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await openTab(tester, l10n.tabClipboard, window: windowA);

      // The list is what the fourth gate is edited from, so it has to be on the
      // surface rather than inferred from the group: being paired is not the
      // same as being allowed to read this clipboard.
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ClipboardPage,
          find.text(l10n.clipboardPeersHeader),
        ).evaluate().isNotEmpty,
        description: 'the sharing list to be shown',
      );
      expect(
        onPage(windowA, ClipboardPage, find.text(l10n.clipboardPeersHint)),
        findsOneWidget,
      );
      final tile = onPage(
        windowA,
        ClipboardPage,
        find.widgetWithText(CheckboxListTile, 'Alice'),
      );
      expect(tile, findsOneWidget, reason: 'the paired peer has to be listed');
      expect(
        tester.widget<CheckboxListTile>(tile).value,
        isFalse,
        reason: 'pairing a Device does not volunteer this clipboard',
      );

      await tester.tap(tile);
      await pumpUntil(
        tester,
        () => bob.controller.isClipboardPeer(alice.fingerprint),
        description: 'the tick to reach the controller',
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('the Settings surface', () {
    testWidgets('reports where things go without repeating the Devices card', (
      tester,
    ) async {
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        profilePath: 'C:/profiles/alice/profile.json',
        defaultIncomingDirectory: 'C:/downloads/LocalTransfer',
      );
      // Tall, because the page is a lazy list and the last line under test —
      // what has gone wrong, which is nothing — is only built when the window
      // is tall enough to hold the cards above it.
      await pumpWindow(tester, device, size: tallWindow);
      await openTab(tester, l10n.tabSettings, window: windowA);

      // Identity belongs to the Devices surface. Repeating the name and
      // Fingerprint here only made two places that can disagree.
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.settingsThisDevice)),
        findsNothing,
      );
      expect(onPage(windowA, SettingsPage, find.text('Alice')), findsNothing);
      expect(
        onPage(
          windowA,
          SettingsPage,
          find.text(device.controller.self.fingerprint.hex),
        ),
        findsNothing,
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.factIdentity)),
        findsOneWidget,
      );
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.factReceivedFiles)),
        findsOneWidget,
      );

      final identity = tester.widget<TextFormField>(
        _settingsIdentityField(windowA),
      );
      final incoming = tester.widget<TextField>(
        _settingsIncomingField(windowA),
      );
      expect(identity.initialValue, 'C:/profiles/alice/profile.json');
      expect(incoming.readOnly, isFalse);
      expect(incoming.controller!.text, 'C:/downloads/LocalTransfer');

      // Both paths wear the same field: a readonly fact must not look like a
      // different kind of control from the folder the user can choose.
      final identityField = tester.widget<TextField>(
        find.descendant(
          of: _settingsIdentityField(windowA),
          matching: find.byType(TextField),
        ),
      );
      expect(identityField.readOnly, isTrue);
      expect(identityField.decoration!.filled, isTrue);
      expect(
        identityField.decoration!.fillColor,
        incoming.decoration!.fillColor,
      );
      expect(
        (identityField.decoration!.enabledBorder! as OutlineInputBorder)
            .borderRadius,
        (incoming.decoration!.enabledBorder! as OutlineInputBorder)
            .borderRadius,
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
        tester
            .widget<TextFormField>(_settingsIdentityField(windowA))
            .initialValue,
        l10n.notStoredOnThisDevice,
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

    testWidgets('the folder is typed on the page, or chosen from the platform', (
      tester,
    ) async {
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        defaultIncomingDirectory: 'C:/downloads/LocalTransfer',
      );
      await pumpWindow(tester, device);
      // The folder chooser is the operating system's own dialog, so a test
      // cannot drive the real one — it runs outside Flutter's event loop and
      // never returns to a `testWidgets` body. The stand-in drives the real
      // button, which is the half that can go wrong.
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      picker.willChooseDirectory(r'D:\shared\inbox');

      await openTab(tester, l10n.tabSettings, window: windowA);

      // The field belongs to the page rather than to a dialog: the path can be
      // read and edited without opening anything first.
      final field = _settingsIncomingField(windowA);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'C:/downloads/LocalTransfer',
        reason: 'the platform default is shown while nothing has been chosen',
      );

      // Typing decides nothing on its own, and the line under the box says so.
      await tester.enterText(field, r'D:\typed\by\hand');
      await tester.pump();
      expect(
        onPage(windowA, SettingsPage, find.text(l10n.folderNotSaved)),
        findsOneWidget,
        reason: 'a box holding something untaken has to admit it',
      );
      expect(device.controller.incomingDirectory, isNull);

      // Enter is the decision.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUntil(
        tester,
        () => device.controller.incomingDirectory == r'D:\typed\by\hand',
        description: 'the typed folder to reach the controller',
      );

      // And the platform's own chooser writes the same value, from the same box.
      await tester.tap(
        onPage(
          windowA,
          SettingsPage,
          find.byTooltip(l10n.changeIncomingFolder),
        ),
      );
      await pumpUntil(
        tester,
        () => picker.directoriesAsked == 1,
        description: 'the platform folder chooser to be asked',
      );
      await pumpUntil(
        tester,
        () => device.controller.incomingDirectory == r'D:\shared\inbox',
        description: 'the chosen folder to reach the controller',
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        r'D:\shared\inbox',
        reason: 'the chooser answers into the box the user is looking at',
      );
      // The line under the box is the last thing in its card and sits below the
      // fold in a short window, so it is read where the page keeps it rather
      // than where the viewport happens to end.
      await tester.pump();
      expect(
        find.descendant(
          of: windowA.within(find.byType(SettingsPage)),
          matching: find.text(l10n.incomingFolderHint, skipOffstage: false),
          skipOffstage: false,
        ),
        findsOneWidget,
        reason: 'a chosen folder says so rather than saying "you are asked"',
      );

      await shutdown(tester, [device]);
    });

    testWidgets('backing out of the folder chooser changes nothing', (
      tester,
    ) async {
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        defaultIncomingDirectory: 'C:/downloads/LocalTransfer',
      );
      await pumpWindow(tester, device);
      // A stand-in told nothing answers null, which is what backing out of the
      // platform's own chooser looks like from here.
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);

      await openTab(tester, l10n.tabSettings, window: windowA);
      await tester.tap(
        onPage(
          windowA,
          SettingsPage,
          find.byTooltip(l10n.changeIncomingFolder),
        ),
      );
      await pumpUntil(
        tester,
        () => picker.directoriesAsked == 1,
        description: 'the platform folder chooser to be asked',
      );

      // Nothing was chosen, so nothing is remembered: a cancelled chooser must
      // not clear a folder the user already has, nor take a name they did not
      // pick.
      expect(device.controller.incomingDirectory, isNull);
      expect(
        onPage(windowA, SettingsPage, find.text('C:/downloads/LocalTransfer')),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('the hourly update choice fits a narrow Android window', (
      tester,
    ) async {
      final device = await startUiDevice(
        tester,
        MemoryBeaconHub().a,
        'Alice',
        platform: DevicePlatform.android,
        controlsWindow: false,
      );
      await pumpWindow(tester, device, size: const Size(360, 800));
      await openTab(tester, l10n.tabSettings, window: windowA);

      expect(
        onPage(windowA, SettingsPage, find.text(l10n.updateIntervalHourly)),
        findsOneWidget,
      );
      final segments = tester.widget<SegmentedButton<UpdateCheckInterval>>(
        onPage(
          windowA,
          SettingsPage,
          find.byType(SegmentedButton<UpdateCheckInterval>),
        ),
      );
      expect(segments.selected, {UpdateCheckInterval.hourly});
      // Scrolling the choices sideways is the deliberate fallback for a narrow
      // phone: the control keeps its natural width instead of squeezing the
      // labels into a misaligned second line.
      final scroller = tester.widget<SingleChildScrollView>(
        onPage(
          windowA,
          SettingsPage,
          find.ancestor(
            of: find.byType(SegmentedButton<UpdateCheckInterval>),
            matching: find.byType(SingleChildScrollView),
          ),
        ),
      );
      expect(scroller.scrollDirection, Axis.horizontal);
      expect(tester.takeException(), isNull);

      await shutdown(tester, [device]);
    });
  });

  group('the Conversations surface', () {
    testWidgets('says where conversations come from when there are none', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabConversation, window: windowA);

      expect(
        onPage(
          windowA,
          ConversationsPage,
          find.text(l10n.conversationListEmpty),
        ),
        findsOneWidget,
      );

      await shutdown(tester, [device]);
    });

    testWidgets('searches message text and attachment names', (tester) async {
      final hub = MemoryBeaconHub();
      final inbox = tempDirectory('local-transfer-search-in-');
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(
        tester,
        hub.b,
        'Bob',
        defaultIncomingDirectory: inbox.path,
      );
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      await sendText(
        tester,
        alice,
        'a message with a searchable needle',
        to: bob.fingerprint,
      );
      final home = tempDirectory('local-transfer-search-out-');
      final picture = File(
        '${home.path}${Platform.pathSeparator}attachment-needle.png',
      );
      await writePng(tester, picture, width: 8, height: 8);
      await tester.runAsync(() => alice.controller.sendImage(picture));
      await pumpUntil(
        tester,
        () => bob.controller.transfers.any(
          (view) => view.names.contains('attachment-needle.png'),
        ),
        description: 'the named attachment to reach Bob',
      );

      await pumpWindow(tester, bob);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Alice'),
        description: 'Alice to appear in the conversation list',
      );
      final search = onPage(
        windowA,
        ConversationsPage,
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == l10n.searchConversations,
        ),
      );
      expect(search, findsOneWidget);

      await tester.enterText(search, 'searchable needle');
      await tester.pump();
      expect(
        conversationListed(windowA, 'Alice'),
        isTrue,
        reason: 'a conversation is found by what was said in it',
      );

      await tester.enterText(search, 'attachment-needle.png');
      await tester.pump();
      expect(
        conversationListed(windowA, 'Alice'),
        isTrue,
        reason: 'a conversation is also found by the name of a sent file',
      );

      await tester.enterText(search, 'nothing-matches-this');
      await tester.pump();
      expect(conversationListed(windowA, 'Alice'), isFalse);
      expect(find.text(l10n.conversationSearchEmpty), findsOneWidget);

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('clearing the open chat asks first and leaves it empty', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await sendText(tester, alice, 'remove this message', to: bob.fingerprint);

      await pumpWindow(tester, bob);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Alice'),
        description: 'Alice to appear in the conversation list',
      );
      await openConversation(tester, windowA, name: 'Alice');
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('remove this message'),
        ).evaluate().isNotEmpty,
        description: 'the message to be open in the conversation',
      );

      final menu = onPage(
        windowA,
        ConversationsPage,
        find.byIcon(Icons.more_horiz),
      );
      expect(menu, findsOneWidget);
      await tester.tap(menu);
      await pumpUntil(
        tester,
        () => windowA
            .within(find.text(l10n.clearConversation))
            .evaluate()
            .isNotEmpty,
        description: 'the conversation menu to open',
      );
      // The item is in the tree while the popup is still animating, and the
      // route ignores pointers until that animation is done.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(windowA.within(find.text(l10n.clearConversation)));
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the clearing confirmation to open',
      );
      expect(find.text(l10n.clearConversationConfirmTitle), findsOneWidget);

      await tapDialogButton(tester, l10n.cancel, window: windowA);
      await pumpUntil(
        tester,
        () => !dialogIsOpen(windowA),
        description: 'the cancellation to close',
      );
      expect(
        onConversation(windowA, find.text('remove this message')).evaluate(),
        isNotEmpty,
        reason: 'answering no must not delete anything',
      );

      await tester.tap(menu);
      await pumpUntil(
        tester,
        () => windowA
            .within(find.text(l10n.clearConversation))
            .evaluate()
            .isNotEmpty,
        description: 'the conversation menu to open again',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(windowA.within(find.text(l10n.clearConversation)));
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the clearing confirmation to open again',
      );
      await tester.tap(
        windowA.within(find.text(l10n.clearConversationConfirmAction)),
      );
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('remove this message'),
        ).evaluate().isEmpty,
        description: 'the confirmed clear to remove the message',
      );
      expect(
        onConversation(windowA, find.text(l10n.conversationEmpty)).evaluate(),
        isNotEmpty,
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('long-pressing a conversation asks first and clears it', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await sendText(tester, alice, 'long-press me', to: bob.fingerprint);

      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to appear in the conversation list',
      );

      // A long press is the mobile gesture that stands in for the desktop
      // right-click: it must offer the same delete confirmation.
      await tester.longPress(conversationRow(windowA, 'Bob'));
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the deleting confirmation to open',
      );
      expect(find.text(l10n.clearConversationConfirmTitle), findsOneWidget);

      await tapDialogButton(tester, l10n.cancel, window: windowA);
      await pumpUntil(
        tester,
        () => !dialogIsOpen(windowA),
        description: 'the cancellation to close',
      );
      expect(
        conversationListed(windowA, 'Bob'),
        isTrue,
        reason: 'answering no keeps the row and the messages',
      );

      await tester.longPress(conversationRow(windowA, 'Bob'));
      await pumpUntil(
        tester,
        () => dialogIsOpen(windowA),
        description: 'the deleting confirmation to open again',
      );
      await tapDialogButton(
        tester,
        l10n.clearConversationConfirmAction,
        window: windowA,
      );
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('long-press me'),
        ).evaluate().isEmpty,
        description: 'the confirmed clear to remove the message',
      );
      // The peer is still connected, so its row stays — only the history is
      // gone. Deleting a conversation is not the same as forgetting a Device.
      expect(
        conversationListed(windowA, 'Bob'),
        isTrue,
        reason: 'a connected conversation keeps its row',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets(
      'deleting an offline conversation removes its row until the peer returns',
      (tester) async {
        final hub = MemoryBeaconHub();
        final bobStore = MemoryProfileStore();
        final alice = await startUiDevice(tester, hub.a, 'Alice');
        final bob = await startUiDevice(
          tester,
          hub.b,
          'Bob',
          profileStore: bobStore,
        );
        await pairDevices(tester, alice, bob);
        await connectDevices(tester, alice, bob);
        await sendText(tester, alice, 'last words', to: bob.fingerprint);

        await pumpWindow(tester, alice);
        await openTab(tester, l10n.tabConversation, window: windowA);
        await pumpUntil(
          tester,
          () => conversationListed(windowA, 'Bob'),
          description: 'Bob to appear in the conversation list',
        );

        // Bob goes away, and with it the Session and the Discovery sighting.
        await tester.runAsync(bob.controller.close);
        await pumpUntil(tester, () {
          for (final peer in alice.controller.peers) {
            if (peer.fingerprint == bob.fingerprint) {
              return !peer.isConnected && !peer.isDiallable;
            }
          }
          return false;
        }, description: 'Bob to become unreachable');

        // The row shows its state without opening it. The label is offline when
        // the reconnect sweep has gone quiet, and connecting while a retry is
        // still being scheduled — either word answers the row's own question.
        final offlineOrConnecting = [
          windowA
              .within(
                find.descendant(
                  of: conversationRow(windowA, 'Bob'),
                  matching: find.textContaining(l10n.presenceOffline),
                ),
              )
              .evaluate(),
          windowA
              .within(
                find.descendant(
                  of: conversationRow(windowA, 'Bob'),
                  matching: find.text(l10n.presenceConnecting),
                ),
              )
              .evaluate(),
        ];
        expect(
          offlineOrConnecting.any((found) => found.isNotEmpty),
          isTrue,
          reason: 'the row shows a state before it is opened',
        );

        await tester.longPress(conversationRow(windowA, 'Bob'));
        await pumpUntil(
          tester,
          () => dialogIsOpen(windowA),
          description: 'the deleting confirmation to open',
        );
        await tapDialogButton(
          tester,
          l10n.clearConversationConfirmAction,
          window: windowA,
        );
        await pumpUntil(
          tester,
          () => !conversationListed(windowA, 'Bob'),
          description: 'the offline conversation to leave the list',
        );
        expect(
          onConversation(windowA, find.text('last words')).evaluate(),
          isEmpty,
          reason: 'deleting a conversation clears its history',
        );

        // Bob comes back on the network; Discovery places him again, and the
        // row the user deleted returns with the Device it belongs to.
        final bobAgain = await startUiDevice(
          tester,
          hub.b,
          'Bob',
          profileStore: bobStore,
        );
        await pumpUntil(
          tester,
          () => conversationListed(windowA, 'Bob'),
          description: 'the rediscovered peer to return to the list',
        );
        expect(
          windowA.within(
            find.descendant(
              of: conversationRow(windowA, 'Bob'),
              matching: find.text(l10n.presenceOnline),
            ),
          ),
          findsOneWidget,
          reason: 'the rediscovered Session reads online again',
        );

        await shutdown(tester, [alice, bobAgain]);
      },
    );

    testWidgets('a connected Device shows up without pressing anything', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      // The point of the surface: a live Session is a conversation, so it is
      // here on its own — no "open conversation" step, and nothing tapped on
      // the Devices surface first.
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the connected Device to appear in the list',
      );
      expect(
        windowA.within(
          find.descendant(
            of: conversationRow(windowA, 'Bob'),
            matching: find.text(l10n.presenceOnline),
          ),
        ),
        findsOneWidget,
        reason: 'the row says the peer is online before it is opened',
      );
      final bobView = alice.controller.peers.firstWhere(
        (peer) => peer.fingerprint == bob.fingerprint,
      );
      expect(bobView.address, isNotNull, reason: 'Discovery placed it');

      // Titled by its address, which is what tells two Machines claiming the
      // same name apart. The alias remains the row's finder key rather than
      // its visible line.
      expect(
        windowA.within(
          find.descendant(
            of: conversationRow(windowA, 'Bob'),
            matching: find.text(bobView.address!),
          ),
        ),
        findsOneWidget,
      );
      expect(
        windowA.within(
          find.descendant(
            of: conversationRow(windowA, 'Bob'),
            matching: find.text('Bob'),
          ),
        ),
        findsNothing,
        reason: 'the alias must not remain the row title',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('picking a conversation opens it beside the list', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      // The board a conversation is drawn on, found by the fill it is painted:
      // a conversation sits on white, and the one other thing that fill could
      // be is the page's grey — which is exactly what this rules out.
      Finder boardOver(Finder inner) => find.ancestor(
        of: inner,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox &&
              widget.color == WeChatColors.light.conversationBackground,
          description: 'the conversation board',
        ),
      );

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );

      // Before anything is picked the right-hand pane says what to do, rather
      // than showing a conversation the user did not ask for — and it is
      // already the conversation's white, because it is where one would go.
      expect(
        onPage(windowA, ConversationsPage, find.text(l10n.conversationPickOne)),
        findsOneWidget,
      );
      expect(
        boardOver(
          onPage(
            windowA,
            ConversationsPage,
            find.text(l10n.conversationPickOne),
          ),
        ),
        findsOneWidget,
      );

      await openConversation(tester, windowA, name: 'Bob');

      // The pane is a conversation: a composer to type in, and the empty-state
      // line the shared body draws.
      expect(
        onConversation(windowA, find.text(l10n.messageHint)),
        findsOneWidget,
      );
      expect(
        onConversation(windowA, find.text(l10n.conversationEmpty)),
        findsOneWidget,
      );
      // And the history sits on that same white board, rather than on the page
      // grey it inherited before the two fills traded places.
      expect(
        boardOver(onConversation(windowA, find.text(l10n.conversationEmpty))),
        findsOneWidget,
      );

      // Picking a row is choosing where to type: the caret is already in the
      // composer, with no second click spent on the box.
      await pumpUntil(
        tester,
        () =>
            tester
                .widget<TextField>(
                  onConversation(windowA, find.byType(TextField)),
                )
                .focusNode
                ?.hasFocus ??
            false,
        description: 'the composer to focus after picking a conversation',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a paired Device connects on its own, needing no tap', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      // Paired, so the peer is in the Owner Group. Discovery then places it,
      // and the connection follows without anybody asking for it: there is no
      // "found but not connected" state left for a paired peer to sit in, and
      // therefore no Connect button to look for. Connect is still offered for
      // a peer that has been found and *not* paired, which the Pairing tests
      // cover.
      await pairDevices(tester, alice, bob);
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);

      // The Device shows up here on its own, because Discovery placed it — no
      // trip to the Devices surface first.
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the found Device to appear in the conversation list',
      );
      // And it is a conversation rather than a row waiting for a tap: the
      // Session came up by itself.
      await pumpUntil(
        tester,
        () =>
            alice.controller.sessions.isNotEmpty &&
            bob.controller.sessions.isNotEmpty,
        description: 'the two Devices to connect with nobody asking',
      );
      expect(
        conversationHasButton(windowA, button: l10n.connect, name: 'Bob'),
        isFalse,
        reason: 'there is nothing left for a Connect button to do',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a Device that announced no name is listed by its address', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      // Bob's alias is the placeholder the wire substitutes for "no name at
      // all", so this is a Device that announced nothing.
      final bob = await startUiDevice(
        tester,
        hub.b,
        DeviceDescriptor.fallbackAlias,
      );
      await pairDevices(tester, alice, bob);
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);

      // What the row is called is the address Discovery placed it at: the one
      // fact that answers "which machine is this", and the same string a person
      // would type into a router or into the peer's firewall.
      final bobView = alice.controller.peers.firstWhere(
        (peer) => peer.fingerprint == bob.fingerprint,
      );
      expect(bobView.address, isNotNull, reason: 'Discovery placed it');
      expect(bobView.displayName, bobView.address);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, bobView.address!),
        description: 'the nameless Device to be listed by its address',
      );
      // Neither the placeholder nor the Fingerprint. The placeholder is the
      // absence of a name wearing one's clothes, and the Fingerprint is the
      // fallback for a peer that has no address either — which this one, having
      // been found, does have.
      expect(
        onPage(
          windowA,
          ConversationsPage,
          find.text(DeviceDescriptor.fallbackAlias),
        ),
        findsNothing,
        reason: 'the placeholder must never reach a screen',
      );
      expect(
        onPage(windowA, ConversationsPage, find.text(bob.fingerprint.short())),
        findsNothing,
        reason: 'the Fingerprint is the last resort, not the name',
      );

      // And the avatar says the same thing the row does, in the one form that
      // fits in a circle: the last octet. `1` is what every address in the list
      // starts with, so an avatar drawn from the first character would be the
      // same on every unnamed Device.
      final octet = bobView.address!.split('.').last;
      expect(
        windowA.within(
          find.descendant(
            of: find.widgetWithText(ConversationRow, bobView.address!),
            matching: find.text(octet),
          ),
        ),
        findsOneWidget,
        reason: 'the avatar carries $octet, not the leading digit',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a discovered Device is admitted and connected automatically', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpTwoWindows(tester, alice, bob);
      await waitForAutomaticConnection(
        tester,
        windowA,
        windowB,
        leftDevice: alice,
        rightDevice: bob,
      );
      await openTab(tester, l10n.tabConversation, window: windowA);

      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to be discovered and listed',
      );
      expect(
        conversationHasButton(windowA, button: l10n.connect, name: 'Bob'),
        isFalse,
        reason: 'Discovery already opened the Session',
      );
      expect(
        alice.controller.peers
            .singleWhere((peer) => peer.fingerprint == bob.fingerprint)
            .isConnected,
        isTrue,
      );
      expect(alice.controller.isPaired, isTrue);
      expect(bob.controller.isPaired, isTrue);
      expect(dialogIsOpen(windowA), isFalse);
      expect(dialogIsOpen(windowB), isFalse);

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('lost trust material is restored automatically', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);

      // Reproduce a one-sided membership: both profiles remember each other,
      // but Bob no longer holds the group secret. Discovery has to recover the
      // secret and open the Session without any user action.
      await shutdown(tester, [alice, bob]);
      await tester.runAsync(() async {
        final json = (await bob.store.load())!;
        final session = Map<String, Object?>.from(json['session']! as Map);
        session.remove('groupSecret');
        json['session'] = session;
        await bob.store.save(json);
      });
      final aliceAfterRestart = await startUiDevice(
        tester,
        hub.join(),
        'Alice',
        profileStore: alice.store,
      );
      final bobAfterRestart = await startUiDevice(
        tester,
        hub.join(),
        'Bob',
        profileStore: bob.store,
      );

      await pumpTwoWindows(tester, aliceAfterRestart, bobAfterRestart);
      await waitForAutomaticConnection(
        tester,
        windowA,
        windowB,
        leftDevice: aliceAfterRestart,
        rightDevice: bobAfterRestart,
      );
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to appear after automatic recovery',
      );

      expect(
        aliceAfterRestart.controller.isPaired,
        isTrue,
        reason: 'the remembered group must be restored',
      );
      expect(
        conversationHasButton(windowA, button: l10n.connect, name: 'Bob'),
        isFalse,
        reason: 'the recovered Session needs no retry',
      );
      expect(dialogIsOpen(windowA), isFalse);
      expect(dialogIsOpen(windowB), isFalse);

      await shutdown(tester, [aliceAfterRestart, bobAfterRestart]);
    });

    testWidgets('text sent from the pane arrives with no answer needed', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      // Typed into the composer and sent, the way a user does it.
      await tester.enterText(
        onConversation(windowA, find.byType(TextField)),
        'straight through',
      );
      await tester.tap(sendButton(windowA));
      await settleRoute(tester);

      // The bubble itself is the evidence the message settled: it carries the
      // text from the moment it is drawn, and a message that was still on its
      // way would be the same bubble, so the assertion is that the text is in
      // the thread rather than that the thread has a receipt on it. A text
      // message has no receipt to show — the kind-and-state line belongs to
      // files, which are the transfers that can be refused or fail.
      await pumpUntil(
        tester,
        () =>
            onConversation(
              windowA,
              find.text('straight through'),
            ).evaluate().isNotEmpty &&
            alice.controller.transfers.single.state.isSettled,
        description: 'the message to settle as sent',
      );
      // The receiver was never asked: text is not an offer, so nothing is
      // waiting on Bob to tap anything.
      expect(
        bob.offers,
        isEmpty,
        reason: 'text is not a question, so Bob is not offered one',
      );
      // And the sent text is in the thread, as a message.
      expect(
        onConversation(windowA, find.text('straight through')),
        findsOneWidget,
      );
      // Drawn in the outgoing fill. The two fills traded places, and this pins
      // the side that did *not* move, so that a later rearrangement of the two
      // cannot quietly take the sent message with it.
      expect(
        tester
            .widget<MessageBubbleShape>(
              onConversation(windowA, find.byType(MessageBubbleShape)),
            )
            .colour,
        WeChatColors.light.bubbleOut,
      );
      // A conversation is not a transfer. The "kind · state" line belongs to a
      // file, where it is the receipt the user reads; over a text bubble it
      // would read "text · completed", which is transfer bookkeeping nobody
      // asked for. What is asserted here is the absence of that line, not the
      // absence of the words: the word "text" must not appear beside the
      // message at all.
      expect(
        onConversation(
          windowA,
          find.text('${l10n.kindText} · ${l10n.stateCompleted}'),
        ),
        findsNothing,
        reason: 'a text message carries no transfer status line',
      );
      // And a sent text never flashes a transfer-in-progress card on the way
      // to becoming the message: the bubble is drawn with its words and no
      // progress bar. The settle is immediate because the body was already in
      // the Offer, so a bar under it would only measure the few frames of the
      // accept round trip the user sees as a flicker.
      expect(
        onConversation(windowA, find.byType(LinearProgressIndicator)),
        findsNothing,
        reason: 'a sent text has no in-flight progress to draw',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('an emoji sent from the picker arrives as a large face', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      // The emoji button sits beside the file button; opening it shows the
      // faces, and picking one puts it in the composer.
      await tester.tap(
        onConversation(windowA, find.byTooltip(l10n.menuSendEmoji)),
      );
      // The menu lives in the navigator's overlay, so the picker is found with
      // a plain finder rather than through the conversation subtree.
      await pumpUntil(
        tester,
        () => find.text(l10n.kindEmoji).evaluate().isNotEmpty,
        description: 'the picker to open',
      );
      // The menu fades in over an animation; a tap during it is swallowed by
      // the route's own IgnorePointer.
      await tester.pumpAndSettle();
      await tester.tap(find.text('😀').first);

      // The face is in the box and has not gone out on its own.
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.widgetWithText(TextField, '😀'),
        ).evaluate().isNotEmpty,
        description: 'the face to land in the composer',
      );
      expect(
        alice.controller.transfers,
        isEmpty,
        reason: 'picking a face does not send anything by itself',
      );

      // 发送 releases it, and it travels as the words of the message.
      await tester.tap(onConversation(windowA, find.text(l10n.send)));
      await pumpUntil(
        tester,
        () =>
            onConversation(windowA, find.text('😀')).evaluate().isNotEmpty &&
            alice.controller.transfers.single.state.isSettled,
        description: 'the face to arrive as a message',
      );

      // A face picked in the composer is a character in the message, so the
      // message is a text message and the face is drawn as its words.
      expect(
        alice.controller.transfers.single.kind,
        PayloadKind.text,
        reason: 'a face picked in the composer is part of the text',
      );
      expect(
        onConversation(
          windowA,
          find.text('${l10n.kindEmoji} · ${l10n.stateCompleted}'),
        ),
        findsNothing,
        reason: 'a text message carries no transfer receipt',
      );
      // And it was remembered for the next time the picker opens.
      expect(alice.controller.recentEmojis, ['😀']);

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a face sent as a payload of its own still arrives large', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      // v0.1.10 and v0.1.11 sent a face as a payload of its own, and a peer
      // running one of those still sends that. The kind stays on the wire and
      // on screen: the face is drawn large, the way it was when it arrived.
      await sendEmojiPayload(tester, alice, '😀', to: bob.fingerprint);
      await pumpUntil(
        tester,
        () =>
            onConversation(windowA, find.text('😀')).evaluate().isNotEmpty &&
            alice.controller.transfers.single.state.isSettled,
        description: 'the face to arrive as a message',
      );

      final face = tester.widget<Text>(
        onConversation(windowA, find.text('😀')).first,
      );
      expect(face.style?.fontSize, WeChat.emojiBubbleFontSize);
      expect(
        onConversation(
          windowA,
          find.text('${l10n.kindEmoji} · ${l10n.stateCompleted}'),
        ),
        findsNothing,
        reason: 'an emoji is a message, not a transfer with a receipt',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('Enter sends and leaves the caret in the box', (tester) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      final composer = onConversation(windowA, find.byType(TextField));
      await tester.tap(composer);
      await tester.enterText(composer, 'first');
      // Enter, not the send button: on desktop the key is what drops focus.
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pumpUntil(
        tester,
        () => alice.controller.transfers.length == 1,
        description: 'the first message to be handed over',
      );

      // The box is empty and still has the caret, so the next message can be
      // typed without reaching for the mouse. Waited for rather than asserted
      // outright: the caret comes back on the frame *after* the send, because
      // `_ConversationComposerState._send` re-requests focus from a post-frame
      // callback — the send rebuilds the field, and asking for focus before
      // that frame would ask a node the rebuild is about to replace.
      final field = tester.widget<TextField>(composer);
      expect(field.controller!.text, isEmpty);
      await pumpUntil(
        tester,
        () => field.focusNode!.hasFocus,
        description: 'the caret to come back to the box',
      );

      // And typing again lands in the same box rather than nowhere.
      await tester.enterText(composer, 'second');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pumpUntil(
        tester,
        () => alice.controller.transfers.length == 2,
        description: 'the second message to be handed over',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a row says when the conversation last moved', (tester) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);

      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to be discovered and listed',
      );
      // The clock in the row's top-right corner. Nothing has been said in this
      // conversation yet, so it falls back to when the Device was last heard
      // from — which is this instant, Discovery having just placed it. A row
      // with a blank corner would be the bug this asserts against.
      expect(
        find.descendant(
          of: conversationRow(windowA, 'Bob'),
          matching: find.text(l10n.timeJustNow),
        ),
        findsOneWidget,
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a row is parted from the next by an inset hairline', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);

      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to be discovered and listed',
      );
      final line = find.descendant(
        of: conversationRow(windowA, 'Bob'),
        matching: find.byType(Divider),
      );
      expect(line, findsOneWidget);
      expect(tester.widget<Divider>(line).color, WeChatColors.light.divider);

      // Inset to the avatar rather than to the row: a full-bleed line would cut
      // the list into blocks, and the row's own padding is what puts the avatar
      // where the line has to start. Read off every `Padding` above the line,
      // because which of them is the innermost is not this test's business.
      expect(
        tester
            .widgetList<Padding>(
              find.ancestor(of: line, matching: find.byType(Padding)),
            )
            .map((padding) => padding.padding),
        contains(const EdgeInsets.only(left: WeChat.conversationRowPadding)),
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a conversation nobody has opened counts its arrivals', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      // Said from Bob's side, so Alice has something she has not read. Her
      // window is up but the conversation has never been opened, which is the
      // state a Device that just came back from a restart is in.
      await sendText(tester, bob, 'first');
      await sendText(tester, bob, 'second');

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () =>
            conversationListed(windowA, 'Bob') &&
            alice.controller.unreadCount(bob.fingerprint) == 2,
        description: 'both arrivals to be counted as unread',
      );

      // The count leads the preview, so the eye lands on it before the words —
      // which is the whole point of putting it in front of the content rather
      // than beside the clock.
      expect(
        find.descendant(
          of: conversationRow(windowA, 'Bob'),
          matching: find.textContaining(l10n.conversationUnread(2)),
        ),
        findsOneWidget,
      );
      // And the preview is the last thing said, which is the second message.
      expect(
        find.descendant(
          of: conversationRow(windowA, 'Bob'),
          matching: find.textContaining('second'),
        ),
        findsOneWidget,
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets(
      'opening a conversation clears its count and keeps it cleared',
      (tester) async {
        final hub = MemoryBeaconHub();
        final alice = await startUiDevice(tester, hub.a, 'Alice');
        final bob = await startUiDevice(tester, hub.b, 'Bob');
        await pairDevices(tester, alice, bob);
        await connectDevices(tester, alice, bob);
        await pumpWindow(tester, alice);

        await sendText(tester, bob, 'hello');
        await openTab(tester, l10n.tabConversation, window: windowA);
        await pumpUntil(
          tester,
          () =>
              conversationListed(windowA, 'Bob') &&
              alice.controller.unreadCount(bob.fingerprint) == 1,
          description: 'the arrival to be counted',
        );

        await openConversation(tester, windowA, name: 'Bob');
        await pumpUntil(
          tester,
          () => alice.controller.unreadCount(bob.fingerprint) == 0,
          description: 'the count to clear on opening',
        );

        // And the row says so: the count is gone from the preview, and the
        // preview is what is left.
        await pumpUntil(
          tester,
          () => find
              .descendant(
                of: conversationRow(windowA, 'Bob'),
                matching: find.textContaining(l10n.conversationUnread(1)),
              )
              .evaluate()
              .isEmpty,
          description: 'the count to leave the row',
        );

        // Leaving does not bring it back. A count that came back on the way out
        // would be one the user has to clear twice.
        await openConversation(tester, windowA, name: 'Bob');
        await settleRoute(tester);
        expect(alice.controller.unreadCount(bob.fingerprint), 0);

        await shutdown(tester, [alice, bob]);
      },
    );

    testWidgets(
      'an open conversation clears a count without another tap on the row',
      (tester) async {
        final hub = MemoryBeaconHub();
        final alice = await startUiDevice(tester, hub.a, 'Alice');
        final bob = await startUiDevice(tester, hub.b, 'Bob');
        await pairDevices(tester, alice, bob);
        await connectDevices(tester, alice, bob);
        await pumpWindow(tester, alice);

        await openTab(tester, l10n.tabConversation, window: windowA);
        await pumpUntil(
          tester,
          () => conversationListed(windowA, 'Bob'),
          description: 'Bob to be listed',
        );
        // Open the conversation first, so it is the one remembered; then step
        // away and come back through the rail. The pane opens with it, without
        // tapping its row, and that is where the arrivals below land.
        await openConversation(tester, windowA, name: 'Bob');
        await pumpUntil(
          tester,
          () => alice.controller.lastConversation == bob.fingerprint,
          description: 'the conversation to be remembered',
        );
        await openTab(tester, l10n.tabDevices, window: windowA);
        await openTab(tester, l10n.tabConversation, window: windowA);
        await settleRoute(tester);

        // Said from Bob's side while Alice is looking at the open
        // conversation. Nothing about the selection changes, so the unread
        // count can only know about it from the surface being visibly open and
        // re-reading the current conversation — a tapped row is not involved.
        await sendText(tester, bob, 'hello', to: alice.fingerprint);
        await pumpUntil(
          tester,
          () =>
              onConversation(windowA, find.text('hello')).evaluate().isNotEmpty,
          description: 'the message to arrive in the open conversation',
        );
        expect(alice.controller.unreadCount(bob.fingerprint), 0);

        // The row has no unread count either, so the preview reads as read —
        // the "hello" line is what the row shows, not "[1] hello".
        await pumpUntil(
          tester,
          () => find
              .descendant(
                of: conversationRow(windowA, 'Bob'),
                matching: find.textContaining(l10n.conversationUnread(1)),
              )
              .evaluate()
              .isEmpty,
          description: 'the row to carry no unread count',
        );

        await shutdown(tester, [alice, bob]);
      },
    );

    testWidgets('the window comes back to the conversation last opened', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');
      await pumpUntil(
        tester,
        () => alice.controller.lastConversation == bob.fingerprint,
        description: 'the conversation to be remembered',
      );

      // Pumping the window again is the restart: the whole tree is built from
      // scratch, and the only thing that carries over is what the controller
      // kept. It opens on the conversation rather than on the pick-one hint.
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ConversationsPage,
          find.text(l10n.messageHint),
        ).evaluate().isNotEmpty,
        description: 'the remembered conversation to be open',
      );
      expect(
        onPage(windowA, ConversationsPage, find.text(l10n.conversationPickOne)),
        findsNothing,
        reason: 'there is an answer to "which conversation" already',
      );

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a tap after the remembered one is what the window keeps', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      final carol = await startUiDevice(tester, hub.join(), 'Carol');
      await pairDevices(tester, alice, bob);
      await pairDevices(tester, alice, carol);
      await connectDevices(tester, alice, bob);
      await connectDevices(tester, alice, carol);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () =>
            conversationListed(windowA, 'Bob') &&
            conversationListed(windowA, 'Carol'),
        description: 'both conversations to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');
      await pumpUntil(
        tester,
        () => alice.controller.lastConversation == bob.fingerprint,
        description: 'Bob to be remembered',
      );

      // Picking Carol is a deliberate act, and it has to outrank what was
      // remembered — otherwise the memory becomes a trap that keeps dragging
      // the window back to a conversation the user has moved on from.
      await openConversation(tester, windowA, name: 'Carol');
      await pumpUntil(
        tester,
        () => alice.controller.lastConversation == carol.fingerprint,
        description: 'Carol to take over as the remembered conversation',
      );

      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ConversationsPage,
          find.text(l10n.messageHint),
        ).evaluate().isNotEmpty,
        description: 'a conversation to be open',
      );
      // Carol's name is on the header, not Bob's: the window opens where the
      // user left off rather than where they first were.
      expect(
        windowA.within(
          find.descendant(
            of: find.byType(ConversationView),
            matching: find.text('Carol'),
          ),
        ),
        findsWidgets,
      );

      await shutdown(tester, [alice, bob, carol]);
    });

    testWidgets('coming back to the menu reopens the last conversation, '
        'ready to type in', (tester) async {
      // Two halves of one requirement. Arriving at the Conversations surface
      // is coming back to where you were — the row that was open is open again
      // — and it is arriving *to type*: a composer that waits to be clicked
      // first makes the user pay a click for something they already asked for.
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');
      await pumpUntil(
        tester,
        () => alice.controller.lastConversation == bob.fingerprint,
        description: 'Bob to be the remembered conversation',
      );

      // Somewhere else for a while — the whole point of the requirement is the
      // *return*, and a return from nowhere tests nothing.
      await openTab(tester, l10n.tabSettings, window: windowA);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ConversationsPage,
          find.text(l10n.messageHint),
        ).evaluate().isNotEmpty,
        description: 'the last conversation to be open again',
      );

      // The first half: it is *selected*, not merely rebuilt. A rebuilt row with
      // no selection would open the conversation while looking like none was
      // picked — and the requirement says the row is what comes back.
      //
      // Asserted on Bob's row specifically rather than on "some selected row":
      // the surface opens whatever was remembered, so a row that happened to be
      // first would satisfy a weaker assertion while the feature did nothing.
      final rows = tester
          .widgetList<ConversationRow>(
            onPage(
              windowA,
              ConversationsPage,
              find.byWidgetPredicate(
                (widget) => widget is ConversationRow && widget.selected,
              ),
            ),
          )
          .toList();
      expect(
        rows,
        hasLength(1),
        reason: 'exactly one row is selected, and it is the one that reopened',
      );
      expect(
        rows.single.peer,
        'Bob',
        reason: 'the selected row is the conversation that was open',
      );

      // The second half: the caret is already in the box, with no click spent
      // on it. Asserted through the focus node rather than by typing — typing
      // would itself give the field focus, and a test that did that would pass
      // whether or not the arrival ever asked.
      expect(
        onConversation(windowA, find.byType(TextField)),
        findsOneWidget,
        reason: 'there is one composer to be focused',
      );
      expect(
        tester
            .widget<TextField>(onConversation(windowA, find.byType(TextField)))
            .focusNode
            ?.hasFocus,
        isTrue,
        reason: 'the composer already holds focus on arrival',
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('pasting into the composer', () {
    testWidgets('a file on the clipboard waits in the composer', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      // Copying a file in Explorer puts the *file* on the clipboard, not its
      // contents — which is precisely what Flutter's own text-only `Clipboard`
      // cannot see, and why the composer reads through this seam instead.
      final clipboard = ScriptedClipboard.install();
      addTearDown(PasteResolution.reset);
      final home = tempDirectory('local-transfer-paste-');
      final source = File('${home.path}${Platform.pathSeparator}copied.bin');
      source.writeAsBytesSync([for (var i = 0; i < 32; i++) i]);
      clipboard.holdingFiles([source.path]);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      // Focus the box, then press the real chord: the shortcut table is part
      // of what is under test, not just what the shortcut does.
      await tester.tap(onConversation(windowA, find.byType(TextField)));
      await sendCtrlV(tester, windowA);

      // A paste is composing, not sending: the file waits in the box beside
      // whatever is typed next, and nothing crosses the wire until 发送.
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('copied.bin'),
        ).evaluate().isNotEmpty,
        description: 'the pasted file to appear in the composer',
      );
      expect(
        alice.controller.transfers,
        isEmpty,
        reason: 'a file in the box is not a message until it is sent',
      );

      await tester.tap(sendButton(windowA));
      await pumpUntil(
        tester,
        () => alice.controller.transfers.isNotEmpty,
        description: 'the staged file to be sent',
      );
      expect(alice.controller.transfers.single.kind, PayloadKind.file);
      expect(
        onConversation(windowA, find.text('copied.bin')),
        findsOneWidget,
        reason: 'the sent file is a message, named as it was staged',
      );

      // Answered before the test ends, so the send that is still waiting on it
      // does not outlive the window.
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      await tester.runAsync(() => bob.controller.reject(bob.offers.single));

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a screenshot on the clipboard waits as a picture', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      final clipboard = ScriptedClipboard.install();
      addTearDown(PasteResolution.reset);
      // A screenshot arrives with no name at all — only bytes — so the app has
      // to work out what it is from the bytes and write them somewhere the
      // engine can stream from.
      clipboard.holdingImage(onePixelPng);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      await tester.tap(onConversation(windowA, find.byType(TextField)));
      await sendCtrlV(tester, windowA);

      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          // The staged picture waits as a thumbnail, so its name lives on a
          // tooltip rather than in a Text: the tray shows the picture's own
          // bytes, not `pasted-179….png`.
          find.byWidgetPredicate(
            (w) =>
                w is Tooltip &&
                w.message != null &&
                w.message!.startsWith('pasted'),
          ),
        ).evaluate().isNotEmpty,
        description: 'the pasted picture to appear in the composer',
      );
      expect(alice.controller.transfers, isEmpty);

      await tester.tap(sendButton(windowA));
      await pumpUntil(
        tester,
        () => alice.controller.transfers.isNotEmpty,
        description: 'the staged picture to be sent',
      );
      expect(
        alice.controller.transfers.single.kind,
        PayloadKind.image,
        reason: 'the bytes, not the clipboard, decide what the message is',
      );

      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the picture',
      );
      await tester.runAsync(() => bob.controller.reject(bob.offers.single));

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a clipboard holding only text still pastes as text', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      final clipboard = ScriptedClipboard.install();
      addTearDown(PasteResolution.reset);
      clipboard.holdingNothing();
      fakeTextClipboard('from the clipboard');

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      final composer = onConversation(windowA, find.byType(TextField));
      await tester.tap(composer);
      await sendCtrlV(tester, windowA);

      // The composer answers Ctrl+V itself, so the field's own paste never
      // runs. Claiming the chord must not take ordinary text pasting away:
      // when the clipboard holds no file and no picture, the fallback has to
      // put the text in the box exactly as the field would have.
      await pumpUntil(
        tester,
        () => composerText(tester, windowA) == 'from the clipboard',
        description: 'the text to be pasted into the box',
      );
      expect(
        alice.controller.transfers,
        isEmpty,
        reason: 'text in the box is not a message until it is sent',
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('choosing a file for the composer', () {
    testWidgets('a picked file waits until 发送 is pressed', (tester) async {
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      final home = tempDirectory('local-transfer-pick-');
      final source = File('${home.path}${Platform.pathSeparator}notes.txt');
      source.writeAsBytesSync([for (var i = 0; i < 16; i++) i]);
      picker.willOffer([source.path]);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      await tester.tap(attachButton(windowA));
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('notes.txt'),
        ).evaluate().isNotEmpty,
        description: 'the chosen file to appear in the composer',
      );
      expect(picker.filesAsked, 1);
      expect(
        alice.controller.transfers,
        isEmpty,
        reason: 'choosing a file is not sending one',
      );

      await tester.tap(sendButton(windowA));
      await pumpUntil(
        tester,
        () => alice.controller.transfers.length == 1,
        description: 'the staged file to be sent',
      );
      expect(alice.controller.transfers.single.kind, PayloadKind.file);

      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      await tester.runAsync(() => bob.controller.reject(bob.offers.single));

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a picture picked through the file dialog waits as a picture', (
      tester,
    ) async {
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      final home = tempDirectory('local-transfer-pick-image-');
      final source = File('${home.path}${Platform.pathSeparator}holiday.png');
      await writePng(tester, source, width: 1200, height: 300);
      // There is one dialog, and the picture is chosen from it as a `.png` in a
      // file list — there is no second, picture-only button any more.
      picker.willOffer([source.path]);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      await tester.tap(attachButton(windowA));
      await pumpUntil(
        tester,
        // By its name, which for a picture is on the tooltip rather than on the
        // face: the tray previews a picture with its own bytes, so the name is
        // the thing the tile keeps but does not draw.
        () => onConversation(
          windowA,
          find.byTooltip('holiday.png'),
        ).evaluate().isNotEmpty,
        description: 'the chosen picture to appear in the composer',
      );
      expect(picker.filesAsked, 1, reason: 'the one attach button, one dialog');
      expect(alice.controller.transfers, isEmpty);

      await tester.tap(sendButton(windowA));
      await pumpUntil(
        tester,
        () => alice.controller.transfers.length == 1,
        description: 'the staged picture to be sent',
      );
      expect(
        alice.controller.transfers.single.kind,
        PayloadKind.image,
        reason:
            'its extension is what makes it a picture, not which door it came '
            'in through',
      );

      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the picture',
      );
      await tester.runAsync(() => bob.controller.reject(bob.offers.single));

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('one dialog sends a picture and a file each its own way', (
      tester,
    ) async {
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      final hub = MemoryBeaconHub();
      final inbox = tempDirectory('local-transfer-pick-mixed-in-');
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      // Bob is told where things go, so the picture has an answer already and
      // the file does not — which is exactly the difference the one dialog has
      // to keep.
      final bob = await startUiDevice(
        tester,
        hub.b,
        'Bob',
        defaultIncomingDirectory: inbox.path,
      );
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      final home = tempDirectory('local-transfer-pick-mixed-');
      final note = File('${home.path}${Platform.pathSeparator}notes.txt');
      note.writeAsBytesSync([for (var i = 0; i < 16; i++) i]);
      final picture = File('${home.path}${Platform.pathSeparator}holiday.png');
      await writePng(tester, picture, width: 40, height: 20);
      // Both chosen in one go, in the order a multi-select dialog hands them
      // back.
      picker.willOffer([picture.path, note.path]);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      await tester.tap(attachButton(windowA));
      await pumpUntil(
        tester,
        // Both, not just the one with a name on its face: the picture is a
        // thumbnail and says what it is only on its tooltip.
        () =>
            onConversation(
              windowA,
              find.text('notes.txt'),
            ).evaluate().isNotEmpty &&
            onConversation(
              windowA,
              find.byTooltip('holiday.png'),
            ).evaluate().isNotEmpty,
        description: 'both choices to appear in the composer',
      );
      expect(picker.filesAsked, 1, reason: 'one dialog for the two of them');
      expect(alice.controller.transfers, isEmpty);

      await tester.tap(sendButton(windowA));
      await pumpUntil(
        tester,
        () => alice.controller.transfers.length == 2,
        description: 'both to be sent',
      );
      expect(
        // Oldest first, so that the assertion reads in the order the two were
        // chosen. The list itself is newest first, because that is how the
        // conversation draws it.
        [
          for (final transfer in alice.controller.transfers.reversed)
            transfer.kind,
        ],
        [PayloadKind.image, PayloadKind.file],
        reason: 'the picture travels as a picture and the file as a file',
      );

      await pumpUntil(
        tester,
        () =>
            bob.controller.transfers.length == 2 &&
            bob.controller.transfers.any(
              (view) =>
                  view.kind == PayloadKind.image && view.localPath != null,
            ),
        description: 'the picture to land with nobody answering anything',
      );
      expect(
        bob.controller.transfers.any(
          (view) => view.kind == PayloadKind.file && view.localPath != null,
        ),
        isFalse,
        reason: 'the file is not written until Bob says yes',
      );
      expect(
        bob.offers.single.kind,
        PayloadKind.file,
        reason: 'the picture was never a question and the file still is',
      );

      await tester.runAsync(() => bob.controller.reject(bob.offers.single));

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a staged file can be taken back out', (tester) async {
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      final home = tempDirectory('local-transfer-unpick-');
      final source = File('${home.path}${Platform.pathSeparator}wrong.txt');
      source.writeAsBytesSync([1, 2, 3]);
      picker.willOffer([source.path]);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      await tester.tap(attachButton(windowA));
      final staged = onConversation(
        windowA,
        find.byTooltip(l10n.removeAttachment),
      );
      await pumpUntil(
        tester,
        () => staged.evaluate().isNotEmpty,
        description: 'the staged file to appear with a way to take it out',
      );

      await tester.tap(staged);
      await pumpUntil(
        tester,
        () =>
            onConversation(windowA, find.text('wrong.txt')).evaluate().isEmpty,
        description: 'the staged file to be taken back out',
      );

      // And 发送 with an empty box sends nothing at all, which is what makes
      // taking a file back out worth doing.
      await tester.tap(sendButton(windowA));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        alice.controller.transfers,
        isEmpty,
        reason: 'nothing was staged by the time 发送 was pressed',
      );

      await shutdown(tester, [alice, bob]);
    });
  });

  group('showing a landed file in its folder', () {
    testWidgets('a completed file offers its folder from the card and a menu', (
      tester,
    ) async {
      // The real revealer hands over to Explorer, so the seam stands in for it:
      // what is under test is that the menu appears and the *path* it carries is
      // the file that landed, not that this machine can open a window.
      final revealer = ScriptedRevealer.install();
      addTearDown(RevealResolution.reset);
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      final home = tempDirectory('local-transfer-reveal-out-');
      final source = File('${home.path}${Platform.pathSeparator}report.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      final inbox = tempDirectory('local-transfer-reveal-in-');

      await offerFile(tester, alice, source);
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      // Answered through the controller rather than the dialog: what this test
      // needs is a Transfer that has *landed*, and the folder question is the
      // subject of its own test elsewhere.
      await tester.runAsync(
        () => bob.controller.acceptInto(bob.offers.single, inbox),
      );
      await pumpUntil(
        tester,
        () => bob.controller.transfers.any((view) => view.localPath != null),
        description: 'the file to land on Bob',
      );
      // The path the action will be handed: the file the user received, in the
      // folder they chose.
      final landed = bob.controller.transfers.single.localPath;
      expect(landed, isNotNull);
      expect(File(landed!).parent.path, inbox.path);

      await pumpWindow(tester, bob);
      await openTab(tester, l10n.tabTransfers, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.text('report.bin'),
        ).evaluate().isNotEmpty,
        description: 'the landed file to appear on the Transfers surface',
      );

      // The card itself carries the folder action at its trailing edge. This is
      // the direct route: no menu, no right-click, just the place the file went.
      final folderAction = onPage(
        windowA,
        TransfersPage,
        find.byTooltip(l10n.openContainingFolder),
      );
      expect(folderAction, findsOneWidget);
      await tester.tap(folderAction);
      await pumpUntil(
        tester,
        () => revealer.revealed.isNotEmpty,
        description: 'the card action to open the containing folder',
      );
      expect(revealer.revealed.single, landed);

      // The same action remains in the context menu, so a user who reaches for
      // the file name is not made to find the icon instead.
      await rightClick(
        tester,
        onPage(windowA, TransfersPage, find.text('report.bin')),
      );
      await pumpUntil(
        tester,
        () => windowA
            .within(find.text(l10n.openContainingFolder))
            .evaluate()
            .isNotEmpty,
        description: 'the context menu to open',
      );

      await tester.tap(windowA.within(find.text(l10n.openContainingFolder)));
      await pumpUntil(
        tester,
        () => revealer.revealed.length == 2,
        description: 'the folder to be opened',
      );
      expect(revealer.revealed.last, landed);

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('a picture arrives on its own and can show its folder', (
      tester,
    ) async {
      final revealer = ScriptedRevealer.install();
      addTearDown(RevealResolution.reset);
      final hub = MemoryBeaconHub();
      final inbox = tempDirectory('local-transfer-reveal-photo-in-');
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      // Told where things go, the way the Windows build is told Downloads. That
      // is the whole difference between an image and a file: the picture has an
      // answer already.
      final bob = await startUiDevice(
        tester,
        hub.b,
        'Bob',
        defaultIncomingDirectory: inbox.path,
      );
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      final home = tempDirectory('local-transfer-reveal-photo-out-');
      final source = File('${home.path}${Platform.pathSeparator}holiday.png');
      await writePng(tester, source, width: 8, height: 8);

      await tester.runAsync(() => alice.controller.sendImage(source));
      await pumpUntil(
        tester,
        () =>
            bob.controller.transfers.isNotEmpty &&
            bob.controller.transfers.single.localPath != null,
        description: 'the picture to land with nobody answering anything',
      );
      expect(
        bob.offers,
        isEmpty,
        reason: 'a picture with a folder to go in is not a question',
      );
      final landed = bob.controller.transfers.single.localPath;
      expect(landed, isNotNull);
      expect(File(landed!).parent.path, inbox.path);

      // Bob's window, on the conversation with Alice: the picture is a message,
      // so the conversation is where a user looks for it.
      await pumpWindow(tester, bob);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Alice'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Alice');
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.byType(ImageBubble),
        ).evaluate().isNotEmpty,
        description: 'the picture to be drawn in the conversation',
      );

      await rightClick(
        tester,
        onConversation(windowA, find.byType(ImageBubble)),
      );
      await pumpUntil(
        tester,
        () => windowA
            .within(find.text(l10n.openContainingFolder))
            .evaluate()
            .isNotEmpty,
        description: 'the bubble to offer its folder',
      );
      await tester.tap(windowA.within(find.text(l10n.openContainingFolder)));
      await pumpUntil(
        tester,
        () => revealer.revealed.isNotEmpty,
        description: 'the folder to be opened',
      );
      expect(revealer.revealed.single, landed);

      await shutdown(tester, [alice, bob]);
    });
  });

  group('a picture on a conversation', () {
    /// Alice sends Bob a picture, and Bob's window ends up looking at it.
    ///
    /// Everything all three tests below need before the thing each of them is
    /// about: a paired pair, a folder for Bob to file into — which is the whole
    /// difference between a picture and a file, and the reason this one arrives
    /// without a question — a picture that landed, and the conversation it
    /// landed in on screen. The source bytes come back so that a test can say
    /// what the clipboard should have been given.
    Future<({UiDevice alice, UiDevice bob, Uint8List bytes})> shownPicture(
      WidgetTester tester,
    ) async {
      final hub = MemoryBeaconHub();
      final inbox = tempDirectory('local-transfer-picture-in-');
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(
        tester,
        hub.b,
        'Bob',
        defaultIncomingDirectory: inbox.path,
      );
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      final home = tempDirectory('local-transfer-picture-out-');
      final source = File('${home.path}${Platform.pathSeparator}holiday.png');
      await writePng(tester, source, width: 24, height: 16);
      final bytes = source.readAsBytesSync();

      await tester.runAsync(() => alice.controller.sendImage(source));
      await pumpUntil(
        tester,
        () =>
            bob.controller.transfers.isNotEmpty &&
            bob.controller.transfers.single.localPath != null,
        description: 'the picture to land on Bob',
      );
      expect(
        File(bob.controller.transfers.single.localPath!).parent.path,
        inbox.path,
        reason: 'a picture with a folder to go in is filed, not asked about',
      );

      await pumpWindow(tester, bob);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Alice'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Alice');
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.byType(ImageBubble),
        ).evaluate().isNotEmpty,
        description: 'the picture to be drawn in the conversation',
      );
      return (alice: alice, bob: bob, bytes: bytes);
    }

    testWidgets('is drawn as itself, with no bubble around it', (tester) async {
      final sent = await shownPicture(tester);

      // The thumbnail is the picture. This is also the wait for the decode:
      // until it finishes there is a placeholder and no [Image] at all.
      await pumpUntil(
        tester,
        () => onConversation(windowA, find.byType(Image)).evaluate().isNotEmpty,
        description: 'the picture to be decoded and drawn',
      );
      expect(
        onConversation(windowA, find.byType(MessageBubbleShape)),
        findsNothing,
        reason:
            'a picture is put on a conversation as a picture, with no fill '
            'behind it and no tail — a green rectangle around one reads as a '
            'file that happens to have a preview',
      );

      // And it is still the picture that opens, not merely a smaller copy of
      // it: the thumbnail is a door into the full-size view, which is the part
      // of "a picture, not a bubble" that a user notices.
      await tester.tap(onConversation(windowA, find.byType(ImageBubble)));
      await pumpUntil(
        tester,
        () => find.byType(InteractiveViewer).evaluate().isNotEmpty,
        description: 'the full-size view to open over the conversation',
      );

      await shutdown(tester, [sent.alice, sent.bob]);
    });

    testWidgets('offers both of its actions on a right-click', (tester) async {
      final sent = await shownPicture(tester);
      await pumpUntil(
        tester,
        () => onConversation(windowA, find.byType(Image)).evaluate().isNotEmpty,
        description: 'the picture to be decoded and drawn',
      );

      await rightClick(
        tester,
        onConversation(windowA, find.byType(ImageBubble)),
      );
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.copyImage)).evaluate().isNotEmpty,
        description: 'the picture to offer its actions',
      );
      // Both, on one menu: a picture can be shown in its folder *and* put back
      // on the clipboard, and the two are not alternatives.
      expect(
        windowA.within(find.text(l10n.openContainingFolder)),
        findsOneWidget,
      );

      await shutdown(tester, [sent.alice, sent.bob]);
    });

    testWidgets('hands its bytes to the clipboard when Copy is chosen', (
      tester,
    ) async {
      final clipboard = ScriptedClipboard.install();
      addTearDown(PasteResolution.reset);
      final sent = await shownPicture(tester);
      await pumpUntil(
        tester,
        () => onConversation(windowA, find.byType(Image)).evaluate().isNotEmpty,
        description: 'the picture to be decoded and drawn',
      );

      await rightClick(
        tester,
        onConversation(windowA, find.byType(ImageBubble)),
      );
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.copyImage)).evaluate().isNotEmpty,
        description: 'the picture to offer its actions',
      );
      await tester.tap(windowA.within(find.text(l10n.copyImage)));
      await pumpUntil(
        tester,
        () => clipboard.copiedImages.isNotEmpty,
        description: 'the picture to reach the clipboard',
      );

      // The picture itself, byte for byte — not its path and not a re-encode.
      // What lands on the clipboard has to be pasteable into anything that
      // takes a picture, and that starts with it being the same picture.
      expect(clipboard.copiedImages.single, sent.bytes);
      expect(
        find.text(l10n.cannotCopyImage),
        findsNothing,
        reason: 'a copy that happened says nothing',
      );

      await shutdown(tester, [sent.alice, sent.bob]);
    });

    testWidgets('says so when the copy could not happen', (tester) async {
      final clipboard = ScriptedClipboard.install();
      addTearDown(PasteResolution.reset);
      // A platform that will not let the app write its own clipboard. That is
      // an ordinary answer rather than an error — Android gives it while the
      // window is not focused — and it must not be told as a success.
      clipboard.answersWrites = false;
      final sent = await shownPicture(tester);
      await pumpUntil(
        tester,
        () => onConversation(windowA, find.byType(Image)).evaluate().isNotEmpty,
        description: 'the picture to be decoded and drawn',
      );

      await rightClick(
        tester,
        onConversation(windowA, find.byType(ImageBubble)),
      );
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.copyImage)).evaluate().isNotEmpty,
        description: 'the picture to offer its actions',
      );
      await tester.tap(windowA.within(find.text(l10n.copyImage)));
      await pumpUntil(
        tester,
        () => find.text(l10n.cannotCopyImage).evaluate().isNotEmpty,
        description: 'the failure to be said out loud',
      );

      await shutdown(tester, [sent.alice, sent.bob]);
    });
  });
}

/// The text currently in [window]'s composer.
String composerText(WidgetTester tester, TestWindow window) => tester
    .widget<TextField>(onConversation(window, find.byType(TextField)))
    .controller!
    .text;

/// Puts [text] on the text clipboard Flutter's own `Clipboard` reads.
///
/// The composer's paste falls back to the field's own, which is
/// `Clipboard.getData` over a platform channel — and in a `testWidgets` body
/// there is no engine behind that channel, so the answer is faked here rather
/// than left to throw `MissingPluginException`.
void fakeTextClipboard(String text) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return <String, dynamic>{'text': text};
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

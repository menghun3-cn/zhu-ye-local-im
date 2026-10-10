import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `flutter_test` has a `TestWindow` of its own — an unrelated handle on the
// test's window — and the harness has one meaning a window under test. Only
// the harness's is used here, so the other is hidden rather than renamed.
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/clipboard_paste.dart';
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

void main() {
  group('the Devices surface', () {
    testWidgets('tells an unpaired Device why it can reach nobody', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      // Conversations leads the shell now, so this surface is offstage until it
      // is asked for. Every other group already opens its tab; this one used to
      // be the surface a window started on and got away without saying so.
      await openTab(tester, l10n.tabDevices, window: windowA);

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
      await openTab(tester, l10n.tabDevices, window: windowA);

      expect(
        onPage(windowA, DevicesPage, find.text(l10n.pairingCardPairedTitle)),
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
      // Set up before the window exists, so the request the Pairing starts is
      // answered by this test rather than left on Alice's screen; see
      // [pairDevices].
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

  group('answering Pairing requests', () {
    testWidgets('the switch takes the listener down and brings it back', (
      tester,
    ) async {
      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openTab(tester, l10n.tabDevices, window: windowA);

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

    testWidgets('allowing the request is the whole of the Pairing', (
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
      //
      // What the dial resolves to is read out of [joined] rather than awaited
      // further down. Alice's half of the exchange runs inside the widget
      // tree's zone, so it only advances while the test pumps, and a bare
      // `await` on this future would be waiting on work that cannot move.
      PairingAttempt? joined;
      await tester.runAsync(() async {
        await untilTrue(
          () => alice.controller.isAcceptingPairings,
          'Alice to answer Pairing requests',
        );
        unawaited(
          bob.controller
              .pairWith(
                host: InternetAddress.loopbackIPv4.address,
                port: alice.controller.pairingPort,
              )
              // Settled into a value here, so that a failure is never an
              // unhandled error and the test can read what happened later.
              .then<void>((attempt) {
                joined = attempt;
              }, onError: (Object _) {}),
        );
      });

      // Alice is asked, and the question is the only thing she is shown. There
      // is no second step behind it: the six digits the handshake derives are
      // never put on a screen, so the one tap is the whole decision.
      await pumpUntil(
        tester,
        () => hasButton(tester, l10n.acceptPairing, window: windowA),
        description: 'Alice to be asked about the request',
      );
      expect(hasButton(tester, l10n.refuse, window: windowA), isTrue);

      await tapDialogButton(tester, l10n.acceptPairing, window: windowA);
      await pumpUntil(
        tester,
        () => joined != null,
        description: 'the tap to let the caller through',
      );

      // Bob has no window, so his half of the confirmation is issued from his
      // controller — the way [pairDevices] does the whole exchange. Neither
      // side commits until both have, which is what stops a half-formed group.
      final attempt = joined!;
      await tester.runAsync(() async {
        unawaited(attempt.confirm().then<void>((_) {}, onError: (Object _) {}));
      });
      await pumpUntil(
        tester,
        () => alice.controller.isPaired && bob.controller.isPaired,
        description: 'allowing the request to pair both Devices',
      );

      // Alice's window is free again — the question was answered, not left
      // open — and she is still answering the next one. Waited for rather than
      // asserted outright: the window is popped from inside Alice's own half of
      // the exchange, so it is still fading out for a frame or two after both
      // Devices report the group.
      await pumpUntil(
        tester,
        () => !dialogIsOpen(windowA),
        description: 'Alice\u2019s question to close once it has been answered',
      );
      expect(alice.controller.isAcceptingPairings, isTrue);

      await shutdown(tester, [alice, bob]);
    });

    testWidgets('refusing the request pairs nobody', (tester) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pumpWindow(tester, alice);

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

      await pumpUntil(
        tester,
        () => hasButton(tester, l10n.acceptPairing, window: windowA),
        description: 'Alice to be asked about the request',
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
      final field = onPage(windowA, SettingsPage, find.byType(TextField));
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
        () => onPage(
          windowA,
          ConversationsPage,
          find.text('Bob'),
        ).evaluate().isNotEmpty,
        description: 'the connected Device to appear in the list',
      );
      // Named by its address as well as its name, which is what tells two
      // Machines claiming the same name apart.
      expect(
        onPage(
          windowA,
          ConversationsPage,
          find.textContaining(InternetAddress.loopbackIPv4.address),
        ),
        findsWidgets,
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
        () => onPage(
          windowA,
          ConversationsPage,
          find.text('Bob'),
        ).evaluate().isNotEmpty,
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

      await tester.tap(onPage(windowA, ConversationsPage, find.text('Bob')));
      await settleRoute(tester);

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
        () => onPage(
          windowA,
          ConversationsPage,
          find.text('Bob'),
        ).evaluate().isNotEmpty,
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

    testWidgets('a found Device that is not paired is offered as Pair', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      // Unpaired on purpose. A paired peer is connected to on its own, so the
      // only row that still carries a button is one for a Device that has been
      // found and not yet admitted — and there the action is Pair, because
      // there is no secret to dial with.
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);

      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'Bob to be discovered and listed',
      );
      expect(
        conversationHasButton(windowA, button: l10n.pair, name: 'Bob'),
        isTrue,
        reason: 'the one action for a Device that is not paired is Pair',
      );
      expect(
        conversationHasButton(windowA, button: l10n.connect, name: 'Bob'),
        isFalse,
        reason: 'Connect needs a secret, and a Pairing is what gives it one',
      );
      expect(
        alice.controller.sessions,
        isEmpty,
        reason: 'an unpaired Device is not connected to behind its user',
      );

      await shutdown(tester, [alice, bob]);
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
        () => onPage(
          windowA,
          ConversationsPage,
          find.text('Bob'),
        ).evaluate().isNotEmpty,
        description: 'the conversation to be listed',
      );
      await tester.tap(onPage(windowA, ConversationsPage, find.text('Bob')));
      await settleRoute(tester);

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
        () => onPage(
          windowA,
          ConversationsPage,
          find.text('Bob'),
        ).evaluate().isNotEmpty,
        description: 'the conversation to be listed',
      );
      await tester.tap(onPage(windowA, ConversationsPage, find.text('Bob')));
      await settleRoute(tester);

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

    testWidgets('the way in is a word, not a filled button', (tester) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      // Unpaired on purpose: that is the one row that still carries an action,
      // and the action is what has to look like WeChat's rather than like
      // Material's.
      await pumpWindow(tester, alice);
      await openTab(tester, l10n.tabConversation, window: windowA);

      await pumpUntil(
        tester,
        () => conversationHasButton(windowA, button: l10n.pair, name: 'Bob'),
        description: 'the found Device to be offered as Pair',
      );
      final style = tester
          .widget<TextButton>(
            find.descendant(
              of: conversationRow(windowA, 'Bob'),
              matching: find.widgetWithText(TextButton, l10n.pair),
            ),
          )
          .style!;

      // No fill. A filled button is the loudest thing Material draws, and a
      // list of found Devices would be a column of them.
      expect(
        style.backgroundColor?.resolve(const <WidgetState>{}),
        Colors.transparent,
      );
      expect(
        style.foregroundColor?.resolve(const <WidgetState>{}),
        WeChatColors.light.secondaryText,
      );
      // And the dot in front of the word, which is the mark the desktop client
      // uses for "you can act here".
      expect(
        tester
            .widgetList<Container>(
              find.descendant(
                of: conversationRow(windowA, 'Bob'),
                matching: find.byType(Container),
              ),
            )
            .where((container) {
              final decoration = container.decoration;
              return decoration is BoxDecoration &&
                  decoration.shape == BoxShape.circle;
            }),
        isNotEmpty,
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

    testWidgets('a picked image waits as a picture', (tester) async {
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
      picker.willOfferImage(source.path);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');

      await tester.tap(imageButton(windowA));
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('holiday.png'),
        ).evaluate().isNotEmpty,
        description: 'the chosen picture to appear in the composer',
      );
      expect(picker.imagesAsked, 1);
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
        reason: 'an image picked as an image travels as one',
      );

      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the picture',
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
    testWidgets('a received file offers its folder on a right-click', (
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

      // Nothing is offered while the file is still a question, and this one is
      // not — so the only menu a right-click can raise is the folder action.
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
        () => revealer.revealed.isNotEmpty,
        description: 'the folder to be opened',
      );
      expect(revealer.revealed.single, landed);

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

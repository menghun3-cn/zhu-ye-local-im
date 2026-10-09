import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/clipboard_page.dart';
import 'package:local_transfer/ui/pages/conversations_page.dart';
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
      // than showing a conversation the user did not ask for.
      expect(
        onPage(windowA, ConversationsPage, find.text(l10n.conversationPickOne)),
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

    testWidgets('a Device that announced no name is listed by Fingerprint', (
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

      await pumpUntil(
        tester,
        () => conversationListed(windowA, bob.fingerprint.short()),
        description: 'the nameless Device to be listed',
      );
      // Not the placeholder: a Device with no name is told apart from every
      // other nameless Device by the Fingerprint it proved it holds, and the
      // placeholder is not a name — it is the absence of one.
      expect(
        onPage(
          windowA,
          ConversationsPage,
          find.text(DeviceDescriptor.fallbackAlias),
        ),
        findsNothing,
        reason: 'the placeholder must never reach a screen',
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
      // typed without reaching for the mouse.
      final field = tester.widget<TextField>(composer);
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);

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
  });
}

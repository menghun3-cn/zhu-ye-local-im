import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';

import '../support/ui_harness.dart';

/// What an unsent message looks like and what its marker does.
///
/// The queueing itself — that a refused send becomes a draft rather than a
/// toast — is answered by `test/app/app_controller_test.dart` against the
/// controller. What is under test here is the surface: the red marker on the
/// bubble, the dialog a tap on it opens, and that 取消 leaves the draft owed
/// while 重发 attempts the delivery again.
void main() {
  /// Two Devices that trust each other but cannot reach each other.
  ///
  /// Separate beacon hubs is what keeps them from ever meeting on their own:
  /// paired through the Pairing port the way `pairDirectly` does in the plain
  /// Dart suite, on networks that never carry a beacon to the other side.
  /// The result is the state a send is refused in — known peer, no Session.
  Future<({UiDevice alice, UiDevice bob})> pairedButOffline(
    WidgetTester tester,
  ) async {
    final alice = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    final bob = await startUiDevice(tester, MemoryBeaconHub().a, 'Bob');
    await tester.runAsync(() async {
      final port = bob.controller.pairingPort;
      expect(port, isNotNull, reason: 'the receiving Device answers Pairing');
      final attempt = await alice.controller.pairWith(
        host: InternetAddress.loopbackIPv4.address,
        port: port,
      );
      await attempt.confirm();
      await untilTrue(
        () =>
            alice.controller.isPaired &&
            bob.controller.isPaired &&
            alice.controller.isServing &&
            bob.controller.isServing,
        'both Devices to finish the direct Pairing and serve',
      );
    });
    await pumpWindow(tester, alice);
    await openTab(tester, l10n.tabConversation, window: windowA);
    await pumpUntil(
      tester,
      () => conversationListed(windowA, 'Bob'),
      description: 'the offline peer to be listed',
    );
    await openConversation(tester, windowA, name: 'Bob');
    return (alice: alice, bob: bob);
  }

  /// Queues [text] as Alice's draft to Bob, through the controller the way
  /// the composer's offline path does.
  Future<void> queueDraft(
    WidgetTester tester,
    UiDevice alice,
    UiDevice bob,
    String text,
  ) async {
    await tester.runAsync(
      () => alice.controller.queueUnsentMessage(
        peer: bob.fingerprint,
        kind: PayloadKind.text,
        text: text,
      ),
    );
    await pumpUntil(
      tester,
      () => onConversation(windowA, find.text(text)).evaluate().isNotEmpty,
      description: 'the draft to appear in the conversation',
    );
  }

  Finder theMarker() =>
      onConversation(windowA, find.byIcon(Icons.error_outline));

  testWidgets('a draft wears the marker and cancel leaves it owed', (
    tester,
  ) async {
    final devices = await pairedButOffline(tester);
    await queueDraft(tester, devices.alice, devices.bob, 'are you there?');

    expect(theMarker(), findsOneWidget);
    expect(
      onConversation(windowA, find.text('are you there?')),
      findsOneWidget,
    );

    await tester.tap(theMarker());
    await settleRoute(tester);
    await pumpUntil(
      tester,
      () => windowA
          .within(find.text(l10n.resendMessageTitle))
          .evaluate()
          .isNotEmpty,
      description: 'the resend dialog to open',
    );
    // The dialog shows what is being resent, so 取消 is an informed answer.
    expect(
      windowA.within(find.text('are you there?')),
      findsWidgets,
      reason: 'the bubble and the dialog preview both carry the words',
    );

    await tester.tap(windowA.dialogButton(l10n.cancel));
    await settleRoute(tester);
    await pumpUntil(
      tester,
      () => !dialogIsOpen(windowA),
      description: 'the dialog to close',
    );

    expect(
      theMarker(),
      findsOneWidget,
      reason: 'cancel is not a delete: the draft is still owed',
    );
    expect(
      devices.alice.controller.transfers.singleWhere((view) => view.unsent),
      isNotNull,
    );
    expect(devices.bob.controller.transfers, isEmpty);

    await shutdown(tester, [devices.alice, devices.bob]);
  });

  testWidgets('resend while the peer is still offline keeps the draft', (
    tester,
  ) async {
    final devices = await pairedButOffline(tester);
    await queueDraft(tester, devices.alice, devices.bob, 'still here?');

    await tester.tap(theMarker());
    await settleRoute(tester);
    await pumpUntil(
      tester,
      () => windowA.within(find.text(l10n.resend)).evaluate().isNotEmpty,
      description: 'the resend dialog to open',
    );
    await tester.tap(windowA.dialogButton(l10n.resend));
    await settleRoute(tester);

    // The send was attempted and refused the same way the first was: the
    // draft goes back on screen marked, and nothing reached Bob.
    await pumpUntil(
      tester,
      () =>
          devices.alice.controller.transfers.any((view) => view.unsent) &&
          devices.bob.controller.transfers.isEmpty,
      description: 'the draft to be restored after the refused resend',
    );
    expect(theMarker(), findsOneWidget);
    expect(devices.bob.controller.transfers, isEmpty);

    await shutdown(tester, [devices.alice, devices.bob]);
  });

  testWidgets('a queued file names itself in the conversation', (tester) async {
    final devices = await pairedButOffline(tester);
    final home = tempDirectory('local-transfer-unsent-ui-');
    final source = File('${home.path}${Platform.pathSeparator}report.bin')
      ..writeAsBytesSync([1, 2, 3]);

    await tester.runAsync(
      () => devices.alice.controller.queueUnsentMessage(
        peer: devices.bob.fingerprint,
        kind: PayloadKind.file,
        file: source,
      ),
    );
    await pumpUntil(
      tester,
      () => onConversation(
        windowA,
        find.text('report.bin'),
      ).evaluate().isNotEmpty,
      description: 'the file draft to appear in the conversation',
    );

    expect(theMarker(), findsOneWidget);
    await tester.tap(theMarker());
    await settleRoute(tester);
    // The file's name is the preview: a file has no words to show.
    await pumpUntil(
      tester,
      () => windowA
          .within(find.text(l10n.resendMessageTitle))
          .evaluate()
          .isNotEmpty,
      description: 'the resend dialog to open',
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('report.bin'),
      ),
      findsOneWidget,
    );

    await shutdown(tester, [devices.alice, devices.bob]);
  });
}

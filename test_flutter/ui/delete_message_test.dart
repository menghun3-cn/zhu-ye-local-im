import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/transfers_page.dart';
import 'package:local_transfer/ui/reveal.dart';

import '../support/ui_harness.dart';

/// What a right-click on a message offers.
///
/// Two things are being pinned here, and neither is the delete itself — that is
/// answered by `test/app/app_controller_test.dart` against the store.
///
///  * The right-click is *always* intercepted now. A message with nothing on
///    disk behind it used to be given no menu at all, and the guard that made
///    that happen also swallowed the gesture. The first test is the case that
///    guard used to own: a text message, whose words are the whole of it.
///  * Every line sits *beside* the others rather than instead of them. A menu
///    that traded "show me that file" for "delete" would lose an action to gain
///    one, so the second and third tests keep what each kind offers whole.
void main() {
  /// Captures what the app puts on the text clipboard.
  ///
  /// `Clipboard.setData` is a platform channel and a `testWidgets` body has no
  /// engine behind one, so the write is caught here rather than left to throw
  /// `MissingPluginException` — which would fail the test for the wrong reason
  /// and assert nothing about the words.
  List<String> captureClipboardWrites() {
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return copied;
  }

  group('a message on a right-click', () {
    /// Alice sends Bob a text message, and Alice's window ends up looking at the
    /// conversation that holds it.
    ///
    /// The message is typed into the composer and sent the way a user does it,
    /// rather than pushed through the controller: what is under test is what the
    /// bubble offers once the message is really there, and a message driven in
    /// from the side would not have proved the bubble is the one a user gets.
    Future<({UiDevice alice, UiDevice bob})> shownText(
      WidgetTester tester,
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

      await tester.enterText(
        onConversation(windowA, find.byType(TextField)),
        'see you at six',
      );
      await tester.tap(sendButton(windowA));
      await settleRoute(tester);
      await pumpUntil(
        tester,
        () =>
            onConversation(
              windowA,
              find.text('see you at six'),
            ).evaluate().isNotEmpty &&
            alice.controller.transfers.single.state.isSettled,
        description: 'the message to settle as sent',
      );
      return (alice: alice, bob: bob);
    }

    testWidgets('a text message offers Delete and Copy text, and no more', (
      tester,
    ) async {
      final sent = await shownText(tester);

      await rightClick(
        tester,
        onConversation(windowA, find.text('see you at six')),
      );
      await pumpUntil(
        tester,
        () =>
            windowA.within(find.text(l10n.deleteMessage)).evaluate().isNotEmpty,
        description: 'the message to offer its actions',
      );
      // The whole point of the case: the words of a message carry no file to
      // show and no picture to copy, and a menu with nothing in it would have
      // been a right-click that did nothing while still eating the gesture.
      //
      // Copy text is here rather than on a selectable bubble because Flutter
      // gives a secondary click to the innermost handler, and a selectable body
      // would therefore own this gesture alone — Delete would be unreachable on
      // the one kind of message a person sends most.
      expect(windowA.within(find.text(l10n.deleteMessage)), findsOneWidget);
      expect(windowA.within(find.text(l10n.copyText)), findsOneWidget);
      expect(
        windowA.within(find.text(l10n.openContainingFolder)),
        findsNothing,
        reason: 'text is not a file, so there is no folder to open',
      );
      expect(
        windowA.within(find.text(l10n.copyImage)),
        findsNothing,
        reason: 'text is not a picture, so there is nothing to copy as one',
      );

      await tester.tap(windowA.within(find.text(l10n.deleteMessage)));
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('see you at six'),
        ).evaluate().isEmpty,
        description: 'the message to leave the conversation',
      );
      expect(
        sent.alice.controller.transfers,
        isEmpty,
        reason: 'the menu is not the only thing the message left',
      );

      await shutdown(tester, [sent.alice, sent.bob]);
    });

    testWidgets('Copy text hands the whole message to the clipboard', (
      tester,
    ) async {
      final copied = captureClipboardWrites();
      final sent = await shownText(tester);

      await rightClick(
        tester,
        onConversation(windowA, find.text('see you at six')),
      );
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.copyText)).evaluate().isNotEmpty,
        description: 'the message to offer its actions',
      );
      await tester.tap(windowA.within(find.text(l10n.copyText)));
      await pumpUntil(
        tester,
        () => copied.isNotEmpty,
        description: 'the words to reach the clipboard',
      );

      // The message itself, as text — not its path, not a summary of it, and
      // not whichever words the pointer happened to be over.
      expect(copied.single, 'see you at six');
      expect(
        find.text(l10n.cannotCopyText),
        findsNothing,
        reason: 'a copy that happened says nothing',
      );

      await shutdown(tester, [sent.alice, sent.bob]);
    });

    testWidgets('a landed file offers Delete beside the folder action', (
      tester,
    ) async {
      // Installed so the folder action, if it were reached, would not open an
      // Explorer window on the machine running this suite. Nothing asserts on
      // it: this test deletes the message instead of revealing it.
      ScriptedRevealer.install();
      addTearDown(RevealResolution.reset);
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      final home = tempDirectory('local-transfer-delete-out-');
      final source = File('${home.path}${Platform.pathSeparator}report.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      final inbox = tempDirectory('local-transfer-delete-in-');

      await offerFile(tester, alice, source);
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      await tester.runAsync(
        () => bob.controller.acceptInto(bob.offers.single, inbox),
      );
      await pumpUntil(
        tester,
        () => bob.controller.transfers.any((view) => view.localPath != null),
        description: 'the file to land on Bob',
      );

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

      // The Transfers surface draws the same menu as the conversation, so this
      // is also the assertion that the two did not drift: one right-click, both
      // lines — the file's own action and the one every message has.
      await rightClick(
        tester,
        onPage(windowA, TransfersPage, find.text('report.bin')),
      );
      await pumpUntil(
        tester,
        () =>
            windowA.within(find.text(l10n.deleteMessage)).evaluate().isNotEmpty,
        description: 'the context menu to open',
      );
      expect(
        windowA.within(find.text(l10n.openContainingFolder)),
        findsOneWidget,
        reason: 'deleting the message must not take the folder action with it',
      );
      expect(
        windowA.within(find.text(l10n.copyText)),
        findsNothing,
        reason: 'a file is not a sentence',
      );

      await tester.tap(windowA.within(find.text(l10n.deleteMessage)));
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          TransfersPage,
          find.text('report.bin'),
        ).evaluate().isEmpty,
        description: 'the file to leave the Transfers surface',
      );

      await shutdown(tester, [alice, bob]);
    });
  });
}

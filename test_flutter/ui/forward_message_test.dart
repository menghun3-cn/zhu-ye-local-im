import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';

import '../support/ui_harness.dart';

/// What forwarding a message offers, and what a batch of them does.
///
/// The send itself is answered by `test/app/app_controller_test.dart` against
/// real Devices; what is pinned here is the surface: the menu lines a message
/// grows, the picking mode 多选 opens, and the one dialog both paths share.
void main() {
  /// Alice sends Bob two messages and ends up looking at their conversation.
  ///
  /// Driven through the composer the way a user types, so what is on screen
  /// is what a user would have.
  Future<({UiDevice alice, UiDevice bob})> shownTwo(WidgetTester tester) async {
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

    for (final words in ['first one', 'second one']) {
      await tester.enterText(
        onConversation(windowA, find.byType(TextField)),
        words,
      );
      await tester.tap(sendButton(windowA));
      await settleRoute(tester);
    }
    await pumpUntil(
      tester,
      () =>
          onConversation(
            windowA,
            find.text('first one'),
          ).evaluate().isNotEmpty &&
          onConversation(
            windowA,
            find.text('second one'),
          ).evaluate().isNotEmpty &&
          alice.controller.transfers.every((view) => view.state.isSettled),
      description: 'both messages to settle as sent',
    );
    return (alice: alice, bob: bob);
  }

  /// The peer row inside the forward dialog — scoped to the dialog so the
  /// conversation's own header, which names the same Device, cannot answer.
  Finder forwardTarget(String name) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(name));

  /// How many of [text] Bob holds, either direction.
  int bobHolds(UiDevice bob, String text) =>
      bob.controller.transfers.where((view) => view.text == text).length;

  group('a message on a right-click', () {
    testWidgets('offers Forward and Select beside the other lines', (
      tester,
    ) async {
      final sent = await shownTwo(tester);

      await rightClick(tester, onConversation(windowA, find.text('first one')));
      await pumpUntil(
        tester,
        () =>
            windowA.within(find.text(l10n.deleteMessage)).evaluate().isNotEmpty,
        description: 'the message to offer its actions',
      );
      expect(windowA.within(find.text(l10n.forward)), findsOneWidget);
      expect(windowA.within(find.text(l10n.multiSelect)), findsOneWidget);

      await shutdown(tester, [sent.alice, sent.bob]);
    });

    testWidgets('Forward asks for a Device and sends the message there', (
      tester,
    ) async {
      final sent = await shownTwo(tester);

      await rightClick(tester, onConversation(windowA, find.text('first one')));
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.forward)).evaluate().isNotEmpty,
        description: 'the message to offer Forward',
      );
      await tester.tap(windowA.within(find.text(l10n.forward)));
      await pumpUntil(
        tester,
        () => forwardTarget('Bob').evaluate().isNotEmpty,
        description: 'the Device picker to open',
      );
      await tester.tap(forwardTarget('Bob'));

      await pumpUntil(
        tester,
        () => bobHolds(sent.bob, 'first one') == 2,
        description: 'Bob to receive the forwarded copy',
      );
      // The batch was one message: nothing else was copied along.
      expect(bobHolds(sent.bob, 'second one'), 1);

      await shutdown(tester, [sent.alice, sent.bob]);
    });

    testWidgets('Select ticks messages and Forward sends each of them', (
      tester,
    ) async {
      final sent = await shownTwo(tester);

      await rightClick(tester, onConversation(windowA, find.text('first one')));
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.multiSelect)).evaluate().isNotEmpty,
        description: 'the message to offer Select',
      );
      await tester.tap(windowA.within(find.text(l10n.multiSelect)));
      await pumpUntil(
        tester,
        () => find.text(l10n.selectedCount(1)).evaluate().isNotEmpty,
        description: 'the picking bar to count the first tick',
      );

      // The second message joins the first by a plain tap — that is the whole
      // gesture the mode exists for.
      await tester.tap(onConversation(windowA, find.text('second one')));
      await pumpUntil(
        tester,
        () => find.text(l10n.selectedCount(2)).evaluate().isNotEmpty,
        description: 'the second message to be ticked',
      );

      await tester.tap(find.widgetWithText(FilledButton, l10n.forward));
      await pumpUntil(
        tester,
        () => forwardTarget('Bob').evaluate().isNotEmpty,
        description: 'the Device picker to open',
      );
      await tester.tap(forwardTarget('Bob'));

      await pumpUntil(
        tester,
        () =>
            bobHolds(sent.bob, 'first one') == 2 &&
            bobHolds(sent.bob, 'second one') == 2,
        description: 'Bob to receive both forwarded copies',
      );
      // A completed forward closes the picking mode: the bar is gone and the
      // composer is back.
      await pumpUntil(
        tester,
        () => find.text(l10n.selectedCount(2)).evaluate().isEmpty,
        description: 'the picking bar to close',
      );
      expect(
        onConversation(windowA, find.byType(TextField)).evaluate(),
        isNotEmpty,
        reason: 'the composer returns when picking ends',
      );

      await shutdown(tester, [sent.alice, sent.bob]);
    });
  });
}

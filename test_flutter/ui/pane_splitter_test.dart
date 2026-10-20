import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/pages/conversations_page.dart';
import 'package:local_transfer/ui/wechat/splitter.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// The divider between the conversation list and the conversation.
///
/// Four facts under test, all of them about the same splitter: it can be
/// dragged, the drag moves the list and the conversation together, the list
/// cannot be dragged out of existence or past its own bounds, and the
/// conversation never gets squeezed below what it needs to be readable.
void main() {
  /// One Device with a peer in the list, and the window it is drawn in.
  Future<({UiDevice alice, UiDevice bob})> conversationList(
    WidgetTester tester, {
    Size size = wideWindow,
  }) async {
    final hub = MemoryBeaconHub();
    final alice = await startUiDevice(tester, hub.a, 'Alice');
    final bob = await startUiDevice(tester, hub.b, 'Bob');
    await pairDevices(tester, alice, bob);
    await connectDevices(tester, alice, bob);
    await pumpWindow(tester, alice, size: size);

    await openTab(tester, l10n.tabConversation, window: windowA);
    await pumpUntil(
      tester,
      () => conversationListed(windowA, 'Bob'),
      description: 'the conversation to be listed',
    );
    return (alice: alice, bob: bob);
  }

  /// The width of the conversation list, as drawn.
  double listWidth(WidgetTester tester) {
    return tester
        .getSize(
          find.ancestor(
            of: onPage(
              windowA,
              ConversationsPage,
              find.byType(ConversationRow),
            ),
            matching: find.byType(Container),
          ),
        )
        .width;
  }

  /// Drags the splitter by [dx] pixels, to the right.
  Future<void> dragSplitter(WidgetTester tester, double dx) async {
    final splitter = find.byType(PaneSplitter);
    final gesture = await tester.startGesture(tester.getCenter(splitter));
    await tester.pump();
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('the splitter drags the list and the conversation together', (
    tester,
  ) async {
    final (:alice, :bob) = await conversationList(tester);

    final before = listWidth(tester);
    await dragSplitter(tester, 60);
    final after = listWidth(tester);

    expect(
      after,
      greaterThan(before),
      reason: 'dragging the splitter right gives the list more room',
    );
    // By the amount it was dragged, not merely by some amount: a splitter
    // that moved the list by a different number would be applying a rule of
    // its own rather than the one the user's hand asked for.
    expect(
      after - before,
      closeTo(60, 2),
      reason: 'the list moves by the distance the splitter was dragged',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets('the list cannot be dragged narrower than its own floor', (
    tester,
  ) async {
    final (:alice, :bob) = await conversationList(tester);

    // A long drag to the left, far past where the floor is.
    await dragSplitter(tester, -2000);
    final width = listWidth(tester);

    expect(
      width,
      greaterThanOrEqualTo(WeChat.conversationListMinWidth),
      reason: 'a list narrower than this cannot be read',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets('the conversation keeps the width it needs to be read', (
    tester,
  ) async {
    // A window with room to spare, so the drag has somewhere to go.
    final (:alice, :bob) = await conversationList(
      tester,
      size: const Size(1600, 900),
    );

    // Dragged as far right as the list's own ceiling allows.
    await dragSplitter(tester, 4000);
    final width = listWidth(tester);

    // The list stops at its own ceiling...
    expect(
      width,
      lessThanOrEqualTo(WeChat.conversationListMaxWidth),
      reason: 'the list does not grow past its own ceiling',
    );
    // ...and the conversation is still there to be read. The available width
    // is the window less the rail, less the list, less the splitter.
    final available = 1600 - WeChat.railWidth - width - WeChat.splitterWidth;
    expect(
      available,
      greaterThanOrEqualTo(WeChat.conversationPaneMinWidth),
      reason: 'the conversation keeps the width it needs to be read',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets('a narrow window gives the room to the conversation', (
    tester,
  ) async {
    // Just wide enough for the two-pane layout, and no more.
    final (:alice, :bob) = await conversationList(
      tester,
      size: const Size(760, 800),
    );

    await dragSplitter(tester, 400);
    final width = listWidth(tester);
    final available = 760 - WeChat.railWidth - width - WeChat.splitterWidth;

    expect(
      available,
      greaterThanOrEqualTo(WeChat.conversationPaneMinWidth),
      reason: 'the conversation is not squeezed to make room for the list',
    );

    await shutdown(tester, [alice, bob]);
  });
}

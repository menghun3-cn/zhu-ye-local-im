import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/wechat/bubble.dart';
import 'package:local_transfer/ui/wechat/splitter.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// How wide a message bubble may get.
///
/// Four facts under test, all of them about the same decision: a short
/// message's bubble hugs its words rather than the pane; a long one wraps at a
/// share of the chat area instead of running across it; a very short one keeps
/// a minimum width, so it reads as a bubble rather than a dot; and the share
/// is of the *chat area*, so it moves when the window does.
void main() {
  /// One Device with a conversation open, and the text of a message in it.
  ///
  /// The message is sent through the controller rather than typed: what is
  /// under test is how the bubble is *drawn*, and driving the composer would
  /// add the typing path to every test without touching the geometry.
  Future<({UiDevice alice, UiDevice bob, Size size})> conversationWith(
    WidgetTester tester,
    String body, {
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
    await openConversation(tester, windowA, name: 'Bob');
    await sendText(tester, bob, body, to: alice.fingerprint);
    await pumpUntil(
      tester,
      () => onConversation(windowA, find.text(body)).evaluate().isNotEmpty,
      description: 'the message to arrive',
    );
    return (alice: alice, bob: bob, size: size);
  }

  /// The width of the bubble holding [body].
  double bubbleWidth(WidgetTester tester, String body) {
    return tester
        .getSize(
          find.ancestor(
            of: onConversation(windowA, find.text(body)),
            matching: find.byType(MessageBubbleShape),
          ),
        )
        .width;
  }

  /// The width of the area the conversation is drawn in.
  ///
  /// The chat area is the pane the conversation is drawn in, and that is the
  /// width the cap is a share of. Measured rather than assumed: the window
  /// is divided between a rail, a conversation list and the conversation
  /// itself, and the split is the shell's business, not this file's.
  double chatAreaWidth(WidgetTester tester) {
    return tester
        .getSize(
          find.ancestor(
            of: onConversation(windowA, find.byType(ListView)),
            matching: find.byType(ColoredBox),
          ),
        )
        .width;
  }

  testWidgets('a long message wraps instead of running across the pane', (
    tester,
  ) async {
    // One word with no spaces, so the only place it can break is the cap:
    // a text with spaces would wrap on its own and prove nothing.
    const body = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final (:alice, :bob, :size) = await conversationWith(tester, body);

    final width = bubbleWidth(tester, body);
    final chat = chatAreaWidth(tester);
    // The cap is a share of the chat area, and the bubble takes the cap when
    // its text is long enough. Asserted against the area rather than against
    // the window: a bubble drawn to the *window's* share would pass a check
    // that never told the two apart.
    expect(
      width,
      lessThanOrEqualTo(chat * WeChat.bubbleMaxWidthFactor),
      reason:
          'the bubble takes the cap, and the cap is a share of the chat area',
    );
    expect(
      width,
      greaterThan(WeChat.bubbleMinWidth),
      reason: 'and it is still a bubble, not a sliver',
    );
    // It really is the cap and not something wider: a bubble that stopped
    // short of the cap would be wrapping early, and one that went past it
    // would be the bug this is here to catch.
    expect(
      width,
      closeTo(chat * WeChat.bubbleMaxWidthFactor, 1),
      reason: 'a message this long fills the cap exactly',
    );
    // And the text is on more than one line, which is what "wraps" means.
    final text = tester.getSize(onConversation(windowA, find.text(body)));
    expect(
      text.height,
      greaterThan(WeChat.fontSizeBody * WeChat.lineHeightBody),
      reason: 'a message this long is drawn on more than one line',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets('a short message takes only the width its words take', (
    tester,
  ) async {
    const body = 'hi';
    final (:alice, :bob, :size) = await conversationWith(tester, body);

    final width = bubbleWidth(tester, body);
    // Two letters are far narrower than any share of the pane, so the bubble
    // has to have hugged them rather than filled the cap.
    expect(
      width,
      lessThan(size.width * WeChat.bubbleMaxWidthFactor),
      reason: 'a short message does not stretch to the cap',
    );
    // And not so narrow that the bubble disappears into a dot: a bubble that
    // hugs one letter is a dot.
    expect(
      width,
      greaterThanOrEqualTo(WeChat.bubbleMinWidth),
      reason: 'and it still has the width of a bubble',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets('the cap is a share of the chat area, so it moves with it', (
    tester,
  ) async {
    const body = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final (:alice, :bob, :size) = await conversationWith(
      tester,
      body,
      size: const Size(1400, 800),
    );

    final wide = bubbleWidth(tester, body);

    // The same conversation in a narrower window: the cap is a share of the
    // chat area, so it has to shrink with the area. A cap that did not would
    // be a fixed number in disguise, and a bubble drawn to it would keep the
    // width it had in the wide window and overflow the narrow one.
    await pumpWindow(tester, alice, size: const Size(700, 800));
    await pumpUntil(
      tester,
      () => onConversation(windowA, find.text(body)).evaluate().isNotEmpty,
      description: 'the conversation to be drawn again in the narrower window',
    );

    final narrow = bubbleWidth(tester, body);
    expect(
      narrow,
      lessThan(wide),
      reason: 'a narrower chat area means a narrower bubble',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets('a narrow chat area narrows the bubble rather than overflowing', (
    tester,
  ) async {
    const body = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final (:alice, :bob, :size) = await conversationWith(
      tester,
      body,
      size: const Size(420, 800),
    );

    // The floor is a floor, not a promise: a chat area too narrow to hold a
    // 48-pixel bubble gets a narrower bubble rather than one that runs off
    // the edge of the column. An overflow here would be reported by the
    // framework as a layout error, so the assertion is about the width.
    final width = bubbleWidth(tester, body);
    expect(
      width,
      lessThanOrEqualTo(chatAreaWidth(tester)),
      reason: 'the bubble stays inside a narrow chat area',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets('the cap follows the splitter, because the chat area moved', (
    tester,
  ) async {
    const body = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final (:alice, :bob, :size) = await conversationWith(
      tester,
      body,
      size: const Size(1600, 800),
    );

    final before = bubbleWidth(tester, body);

    // The splitter is dragged, so the chat area is what changes. The bubble
    // is capped at a share of the chat area, so it has to move with it —
    // this is the two decisions meeting, and neither of them mentions the
    // other: the cap is a share of the chat area, and the chat area is
    // whatever the splitter left of it.
    final splitter = find.byType(PaneSplitter);
    final gesture = await tester.startGesture(tester.getCenter(splitter));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final after = bubbleWidth(tester, body);
    expect(
      after,
      lessThan(before),
      reason: 'the list took room, so the chat area narrowed, so the cap did',
    );
    // And it is still exactly the cap of the *new* chat area.
    expect(
      after,
      closeTo(chatAreaWidth(tester) * WeChat.bubbleMaxWidthFactor, 1),
      reason: 'the cap is a share of the chat area, whatever it now is',
    );

    await shutdown(tester, [alice, bob]);
  });
}

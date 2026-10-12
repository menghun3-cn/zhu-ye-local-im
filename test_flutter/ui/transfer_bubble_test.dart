import 'dart:io';

import 'package:flutter/material.dart';
// `flutter_test` has a `TestWindow` of its own — an unrelated handle on the
// test's window — and the harness has one meaning a window under test. Only
// the harness's is used here, so the other is hidden rather than renamed.
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// The bubble a file transfer is drawn in, and the one action a send has.
///
/// Three facts under test here, all of them about a bubble that belongs to a
/// *transfer in progress*: that it is drawn to the width its name actually
/// takes rather than to whatever the pane has left; that a name too long for
/// that width **wraps** inside the bubble rather than being cut down to an
/// ellipsis; and that a send the user is watching can be stopped from the
/// bubble itself — with the far end told, because a receiver keeps no clock
/// and would otherwise wait forever.
void main() {
  /// Two paired, connected Devices, [alice] holding a window on the
  /// conversation with [bob], and one file offered but not yet answered.
  ///
  /// The file stays a question on purpose: an offer nobody has answered is the
  /// one state in which the bubble's contents are the most of a transfer — a
  /// name, a size line, a progress bar and, now, the way to stop it.
  Future<({UiDevice alice, UiDevice bob})> wiredWithUnansweredOffer(
    WidgetTester tester,
    File source,
  ) async {
    final hub = MemoryBeaconHub();
    final alice = await startUiDevice(tester, hub.a, 'Alice');
    final bob = await startUiDevice(tester, hub.b, 'Bob');
    await pairDevices(tester, alice, bob);
    await connectDevices(tester, alice, bob);
    await pumpWindow(tester, alice);

    await offerFile(tester, alice, source);
    await openTab(tester, l10n.tabConversation, window: windowA);
    await pumpUntil(
      tester,
      () => conversationListed(windowA, 'Bob'),
      description: 'the conversation to be listed',
    );
    await openConversation(tester, windowA, name: 'Bob');
    await pumpUntil(
      tester,
      () => onConversation(
        windowA,
        find.text(l10n.cancelSend),
      ).evaluate().isNotEmpty,
      description: 'the send to appear with its way out',
    );
    return (alice: alice, bob: bob);
  }

  testWidgets('a file bubble is drawn to the width its name takes', (
    tester,
  ) async {
    final home = tempDirectory('local-transfer-bubble-out-');
    // Five characters: short enough that the floor decides the width, which
    // makes the assertion independent of how a test font draws any letter.
    final source = File('${home.path}${Platform.pathSeparator}a.bin');
    source.writeAsBytesSync([1, 2, 3]);
    final (:alice, :bob) = await wiredWithUnansweredOffer(tester, source);

    // The progress bar is the widget that used to stretch: under a loose
    // constraint it grows to every pixel the conversation has left, and the
    // bubble holding it went with it. Bounded now, it is the width the name
    // block was measured at — inside the two WeChat bounds, and nowhere near
    // the width of the pane behind it.
    final bar = tester.getSize(
      onConversation(windowA, find.byType(LinearProgressIndicator)),
    );
    expect(
      bar.width,
      lessThanOrEqualTo(WeChat.transferBubbleMaxWidth),
      reason: 'a short name cannot make the bar reach across the pane',
    );
    expect(
      bar.width,
      greaterThanOrEqualTo(WeChat.transferBubbleMinWidth),
      reason: 'and a short name still leaves a bar worth reading',
    );
    expect(
      bar.width,
      lessThan(400),
      reason: 'the whole point: the bar is not the width of the conversation',
    );

    // The other half of that decision: because the width came from this name's
    // own measure, the name still sits on one line. A cap on its own would not
    // tell a short name from a long one.
    final shortName = tester.getSize(
      onConversation(windowA, find.text('a.bin')),
    );
    expect(
      shortName.height,
      lessThanOrEqualTo(WeChat.fontSizeBody * WeChat.lineHeightBody * 1.5),
      reason: 'a name that fits is not given lines it does not need',
    );

    await shutdown(tester, [alice, bob]);
  });

  testWidgets(
    'a name too long for the bubble wraps instead of losing its end',
    (tester) async {
      final home = tempDirectory('local-transfer-bubble-wrap-');
      // Named the way a real file is: a project, a version, a platform, an
      // architecture, an extension. Each of those is a fact the user opened the
      // bubble to read, and the ones a single ellipsised line throws away are
      // exactly the ones at the end.
      const name = 'local-transfer-1.0.0-windows-x64-portable-full.zip';
      final source = File('${home.path}${Platform.pathSeparator}$name');
      source.writeAsBytesSync([1, 2, 3]);
      final (:alice, :bob) = await wiredWithUnansweredOffer(tester, source);

      final label = onConversation(windowA, find.text(name));
      final text = tester.widget<Text>(label);
      expect(
        text.maxLines,
        WeChat.transferNameMaxLines,
        reason: 'a name is allowed more than the one line the cap gives it',
      );
      expect(
        text.overflow,
        TextOverflow.ellipsis,
        reason: 'and still has to stop somewhere, for a pathological one',
      );

      final size = tester.getSize(label);
      expect(
        size.width,
        lessThanOrEqualTo(WeChat.transferBubbleMaxWidth),
        reason: 'wrapping must not push the bubble past its cap',
      );
      expect(
        size.height,
        greaterThan(WeChat.fontSizeBody * WeChat.lineHeightBody * 1.5),
        reason: 'a name this long really is drawn on more than one line',
      );

      await shutdown(tester, [alice, bob]);
    },
  );

  testWidgets(
    'a send can be cancelled from its bubble, and the peer hears it',
    (tester) async {
      final home = tempDirectory('local-transfer-cancel-out-');
      final source = File('${home.path}${Platform.pathSeparator}stop-me.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      final (:alice, :bob) = await wiredWithUnansweredOffer(tester, source);

      // The file has to be in Bob's hands *before* it is taken away. What this
      // test is for is that a cancel reaches the side that is holding the
      // question; without this wait the tap can outrun the Offer, Bob is never
      // handed anything to hear about, and the assertion below fails on an
      // empty list rather than on the behaviour it is meant to pin.
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be handed the offer',
      );

      await tester.tap(onConversation(windowA, find.text(l10n.cancelSend)));

      await pumpUntil(
        tester,
        () =>
            alice.controller.transfers.single.state == TransferState.cancelled,
        description: 'the send to settle as cancelled',
      );
      await pumpUntil(
        tester,
        () => bob.offers.single.state == TransferState.cancelled,
        description: 'the far side to hear the send was abandoned',
      );

      await shutdown(tester, [alice, bob]);
    },
  );
}

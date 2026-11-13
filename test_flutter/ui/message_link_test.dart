import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/wechat/bubble.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// The web addresses inside a message's words.
///
/// The facts under test: an address is drawn underlined in the theme's link
/// colour and a tap on it reaches the opener with the address — a `www.` one
/// normalized to `https://`; the rest of the message stays ordinary ink with
/// no recognizer; and a message with no address at all is still the plain
/// [Text] it always was.
void main() {
  Fingerprint fp(String seed) =>
      Fingerprint(seed.codeUnitAt(0).toRadixString(16).padLeft(2, '0') * 32);

  /// One bubble for [view], drawn the way the conversation draws it.
  Future<void> pumpBubble(
    WidgetTester tester,
    UiDevice device,
    TransferView view,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appLocales,
        theme: WeChat.theme(WeChatColors.light),
        home: Scaffold(
          body: Center(
            child: MessageBubble(
              view: view,
              controller: device.controller,
              defaultIncomingDirectory: null,
              peerName: 'Bob',
              peerLabel: null,
              peerSeed: fp('b').hex,
              selfName: 'Alice',
              selfSeed: device.controller.self.fingerprint.hex,
              bubbleMaxWidth: 400,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A settled text message in [direction] saying [text].
  TransferView textView(TransferDirection direction, String text) =>
      TransferView(
        id: 't1',
        direction: direction,
        kind: PayloadKind.text,
        peer: fp('b'),
        at: DateTime.utc(2026, 11, 13),
        state: TransferState.completed,
        transferredBytes: 0,
        totalBytes: 0,
        names: const [],
        text: text,
        offer: null,
      );

  /// The [Text] inside the bubble — the message's own words.
  Text bubbleText(WidgetTester tester) => tester.widget<Text>(
    find.descendant(
      of: find.byType(MessageBubbleShape),
      matching: find.byType(Text),
    ),
  );

  /// Every span of [root]'s tree that carries a tap recognizer.
  List<TextSpan> linkedSpans(TextSpan root) => [
    for (final child in root.children ?? const <InlineSpan>[])
      if (child is TextSpan && child.recognizer != null) child,
  ];

  testWidgets('a tapped address reaches the opener', (tester) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    final links = ScriptedLinkOpener.install();
    await pumpBubble(
      tester,
      device,
      textView(TransferDirection.incoming, 'https://example.com/a?x=1'),
    );

    // The whole message is the address, so a tap on its centre is a tap on
    // the link — which is also what a user does with a message that is only
    // a link.
    await tester.tap(
      find.text('https://example.com/a?x=1', findRichText: true),
    );
    await tester.pump();

    expect(links.opened, ['https://example.com/a?x=1']);

    await shutdown(tester, [device]);
  });

  testWidgets('a www. address opens with an https scheme', (tester) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    final links = ScriptedLinkOpener.install();
    await pumpBubble(
      tester,
      device,
      textView(TransferDirection.incoming, 'www.example.com'),
    );

    await tester.tap(find.text('www.example.com', findRichText: true));
    await tester.pump();

    expect(links.opened, ['https://www.example.com']);

    await shutdown(tester, [device]);
  });

  testWidgets('only the address is a link; the rest is ordinary ink', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpBubble(
      tester,
      device,
      textView(TransferDirection.incoming, '看这个 https://a.com/path 很不错'),
    );

    final text = bubbleText(tester);
    final root = text.textSpan! as TextSpan;
    expect(root.toPlainText(), '看这个 https://a.com/path 很不错');

    final links = linkedSpans(root);
    expect(links, hasLength(1));
    final link = links.single;
    expect(link.text, 'https://a.com/path');
    expect(link.recognizer, isA<TapGestureRecognizer>());
    expect(link.style?.decoration, TextDecoration.underline);
    expect(link.style?.color, WeChatColors.light.brandStrong);

    // The sentence around it carries no recognizer of its own.
    for (final child in root.children!) {
      if (child is TextSpan && child != link) {
        expect(child.recognizer, isNull);
      }
    }

    await shutdown(tester, [device]);
  });

  testWidgets('a message with no address is still a plain Text', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpBubble(
      tester,
      device,
      textView(TransferDirection.incoming, '你好'),
    );

    final text = bubbleText(tester);
    expect(text.data, '你好');
    expect(text.textSpan, isNull);

    await shutdown(tester, [device]);
  });
}

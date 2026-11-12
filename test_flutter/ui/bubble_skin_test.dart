import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/pages/settings_page.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/bubble_skin_picker.dart';
import 'package:local_transfer/ui/wechat/bubble.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// What a bubble is painted with once a skin is chosen.
///
/// The facts under test: a gradient skin replaces the theme's flat colour on
/// the side it was chosen for and leaves the other side alone; an image skin
/// paints its picture under its scrim; a file-kind message never wears a skin
/// at all; and a picture that has gone missing falls back to the ordinary
/// bubble rather than to a blank rectangle.
void main() {
  final gradient = GradientBubbleSkin(
    colors: [0xFFA9DDBB, 0xFF4E9A6E],
    direction: BubbleGradientDirection.vertical,
    ink: BubbleSkinInk.dark,
  );

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

  /// A settled text message in [direction].
  TransferView textView(TransferDirection direction, {String text = '你好'}) =>
      TransferView(
        id: 't1',
        direction: direction,
        kind: PayloadKind.text,
        peer: fp('b'),
        at: DateTime.utc(2026, 11, 12),
        state: TransferState.completed,
        transferredBytes: 0,
        totalBytes: 0,
        names: const [],
        text: text,
        offer: null,
      );

  /// The [MessageBubbleShape] on screen, and nothing else.
  MessageBubbleShape bubbleShape(WidgetTester tester) =>
      tester.widget<MessageBubbleShape>(find.byType(MessageBubbleShape));

  testWidgets('a gradient skin paints the outgoing bubble and its ink', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await tester.runAsync(
      () => device.controller.setBubbleSkin(
        outgoing: true,
        skin: GradientBubbleSkin(
          colors: [0xFFA9DDBB, 0xFF4E9A6E],
          direction: BubbleGradientDirection.vertical,
          ink: BubbleSkinInk.light,
        ),
      ),
    );

    await pumpBubble(tester, device, textView(TransferDirection.outgoing));

    final paint = bubbleShape(tester).paint;
    final gradient = paint.decoration.gradient! as LinearGradient;
    expect(gradient.colors, [const Color(0xFFA9DDBB), const Color(0xFF4E9A6E)]);
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    // Light ink on a mid-tone gradient: the words are white, not the
    // theme's near-black.
    expect(paint.ink, Colors.white);
    final text = tester.widget<Text>(find.text('你好'));
    expect(text.style?.color, Colors.white);

    await shutdown(tester, [device]);
  });

  testWidgets('the two sides wear their own skins, independently', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await tester.runAsync(
      () => device.controller.setBubbleSkin(outgoing: true, skin: gradient),
    );

    // Outgoing wears the gradient; incoming keeps the theme's flat colour —
    // the profile's two slots are read by direction, not shared.
    await pumpBubble(tester, device, textView(TransferDirection.outgoing));
    expect(bubbleShape(tester).paint.decoration.gradient, isNotNull);

    await pumpBubble(tester, device, textView(TransferDirection.incoming));
    final incoming = bubbleShape(tester).paint;
    expect(incoming.decoration.gradient, isNull);
    expect(incoming.decoration.color, WeChatColors.light.bubbleIn);
    expect(incoming.ink, WeChatColors.light.bubbleText);

    await shutdown(tester, [device]);
  });

  testWidgets('an emoji message wears the skin like a text one', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await tester.runAsync(
      () => device.controller.setBubbleSkin(outgoing: true, skin: gradient),
    );

    final view = TransferView(
      id: 'e1',
      direction: TransferDirection.outgoing,
      kind: PayloadKind.emoji,
      peer: fp('b'),
      at: DateTime.utc(2026, 11, 12),
      state: TransferState.completed,
      transferredBytes: 0,
      totalBytes: 0,
      names: const [],
      text: '😀',
      offer: null,
    );
    await pumpBubble(tester, device, view);
    expect(bubbleShape(tester).paint.decoration.gradient, isNotNull);

    await shutdown(tester, [device]);
  });

  testWidgets('a file message keeps the theme even with a skin set', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await tester.runAsync(
      () => device.controller.setBubbleSkin(outgoing: true, skin: gradient),
    );

    // A file bubble is a transfer's receipt — progress, answers — not a
    // message's skin, so the fill stays the theme's green.
    final view = TransferView(
      id: 'f1',
      direction: TransferDirection.outgoing,
      kind: PayloadKind.file,
      peer: fp('b'),
      at: DateTime.utc(2026, 11, 12),
      state: TransferState.completed,
      transferredBytes: 4,
      totalBytes: 4,
      names: const ['report.pdf'],
      text: null,
      offer: null,
    );
    await pumpBubble(tester, device, view);
    final paint = bubbleShape(tester).paint;
    expect(paint.decoration.gradient, isNull);
    expect(paint.decoration.color, WeChatColors.light.bubbleOut);

    await shutdown(tester, [device]);
  });

  testWidgets('a bundled image skin paints its picture under its scrim', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await tester.runAsync(
      () => device.controller.setBubbleSkin(
        outgoing: true,
        skin: ImageBubbleSkin(
          source: BubbleSkinImageSource.asset,
          name: 'mint.png',
          scrim: 0.3,
          ink: BubbleSkinInk.dark,
        ),
      ),
    );

    await pumpBubble(tester, device, textView(TransferDirection.outgoing));

    final paint = bubbleShape(tester).paint;
    expect(paint.decoration.image, isNotNull);
    expect(paint.decoration.image!.image, isA<AssetImage>());
    expect(paint.scrim, isNotNull);
    expect(paint.scrim!.a, closeTo(0.3, 0.001));

    await shutdown(tester, [device]);
  });

  testWidgets('a file skin whose picture is gone falls back to the theme', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await tester.runAsync(
      () => device.controller.setBubbleSkin(
        outgoing: true,
        skin: ImageBubbleSkin(
          source: BubbleSkinImageSource.file,
          name: '/definitely/not/here.png',
          ink: BubbleSkinInk.light,
        ),
      ),
    );

    await pumpBubble(tester, device, textView(TransferDirection.outgoing));

    // App data gets cleaned; a skin that cannot paint its picture is the
    // ordinary bubble, not a blank rectangle with white text on the board.
    final paint = bubbleShape(tester).paint;
    expect(paint.decoration.image, isNull);
    expect(paint.decoration.color, WeChatColors.light.bubbleOut);
    expect(paint.ink, WeChatColors.light.bubbleOutText);

    await shutdown(tester, [device]);
  });

  testWidgets('the picker applies a preset to the side it was opened for', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appLocales,
        theme: WeChat.theme(WeChatColors.light),
        home: Scaffold(
          body: BubbleSkinPicker(
            outgoing: false,
            controller: device.controller,
          ),
        ),
      ),
    );
    await tester.pump();

    // The 「默认」 tile starts selected; choosing a preset moves the draft.
    await tester.tap(find.text(l10n.bubbleSkinPresetBamboo));
    await tester.pump();
    await tester.tap(find.text(l10n.bubbleSkinDone));
    await tester.pump();

    expect(device.controller.incomingBubbleSkin, isNotNull);
    expect(device.controller.incomingBubbleSkin, isA<GradientBubbleSkin>());
    expect(device.controller.outgoingBubbleSkin, isNull);

    await shutdown(tester, [device]);
  });

  testWidgets('the picker restores the theme when the draft is cleared', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await tester.runAsync(
      () => device.controller.setBubbleSkin(outgoing: true, skin: gradient),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appLocales,
        theme: WeChat.theme(WeChatColors.light),
        home: Scaffold(
          body: BubbleSkinPicker(outgoing: true, controller: device.controller),
        ),
      ),
    );
    await tester.pump();

    // The draft opened as the stored gradient; tapping 默认 clears it, and
    // 完成 writes the null back — the theme's colours return. The section
    // heading says the same word, so the tap goes to the tile's InkWell.
    await tester.tap(
      find.widgetWithText(InkWell, l10n.bubbleSkinSectionDefault),
    );
    await tester.pump();
    await tester.tap(find.text(l10n.bubbleSkinDone));
    await tester.pump();

    expect(device.controller.outgoingBubbleSkin, isNull);

    await shutdown(tester, [device]);
  });

  testWidgets('the settings page lists both sides of the conversation', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpWindow(tester, device, size: tallWindow);
    await openTab(tester, l10n.tabMy, window: windowA);
    await openMyCard(tester, l10n.myCardSettings, window: windowA);
    await pumpUntil(
      tester,
      () => onPage(
        windowA,
        SettingsPage,
        find.text(l10n.settingsBubbles),
      ).evaluate().isNotEmpty,
      description: 'the bubble-skin section to be listed',
    );

    expect(
      onPage(windowA, SettingsPage, find.text(l10n.bubbleSkinMine)),
      findsOneWidget,
    );
    expect(
      onPage(windowA, SettingsPage, find.text(l10n.bubbleSkinTheirs)),
      findsOneWidget,
    );

    await shutdown(tester, [device]);
  });
}

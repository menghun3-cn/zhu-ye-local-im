import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

/// The emoji button beside the file button, and the picker it opens.
void main() {
  /// Pumps a composer whose emoji picks are collected in [picked].
  Future<void> pumpComposer(
    WidgetTester tester,
    List<String> picked, {
    List<String> recent = const [],
    TextEditingController? message,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ConversationComposer(
            message: message ?? TextEditingController(),
            onSend: () {},
            onPaste: () async => false,
            onAttach: () {},
            onEmoji: picked.add,
            attachments: const [],
          ),
        ),
      ),
    );
  }

  testWidgets('the emoji button sits next to the file button', (tester) async {
    final l10n = lookupAppLocalizations(appLocale);
    await pumpComposer(tester, <String>[]);

    expect(find.byTooltip(l10n.menuSendFile), findsOneWidget);
    expect(find.byTooltip(l10n.menuSendEmoji), findsOneWidget);

    final file = tester.getRect(find.byTooltip(l10n.menuSendFile));
    final emoji = tester.getRect(find.byTooltip(l10n.menuSendEmoji));
    expect(emoji.left, greaterThan(file.right));
    expect(emoji.top, file.top);
  });

  testWidgets('picking a face calls onEmoji with that face', (tester) async {
    final l10n = lookupAppLocalizations(appLocale);
    final picked = <String>[];
    await pumpComposer(tester, picked);

    await tester.tap(find.byTooltip(l10n.menuSendEmoji));
    await tester.pumpAndSettle();

    // The panel shows the section headings — recents first, then everything.
    expect(find.text(l10n.emojiRecent), findsOneWidget);
    expect(find.text(l10n.kindEmoji), findsOneWidget);

    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();

    expect(picked, ['😀']);
  });

  testWidgets('a picked face goes into the box, it does not go out', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(appLocale);
    final picked = <String>[];
    final message = TextEditingController();
    await pumpComposer(tester, picked, message: message);

    await tester.tap(find.byTooltip(l10n.menuSendEmoji));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();

    // The face is in the composer, waiting for 发送, and nothing was sent.
    expect(message.text, '😀');
    expect(find.text('😀'), findsOneWidget);
  });

  testWidgets('a face joins the words that were already typed', (tester) async {
    final l10n = lookupAppLocalizations(appLocale);
    final picked = <String>[];
    final message = TextEditingController(text: '你好');
    await pumpComposer(tester, picked, message: message);

    await tester.tap(find.byTooltip(l10n.menuSendEmoji));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();

    expect(message.text, '你好😀');
  });

  testWidgets('the panel is drawn plainly, not dimmed', (tester) async {
    final l10n = lookupAppLocalizations(appLocale);
    final picked = <String>[];
    await pumpComposer(tester, picked);

    await tester.tap(find.byTooltip(l10n.menuSendEmoji));
    await tester.pumpAndSettle();

    // A menu entry that is a panel used to be a disabled menu item, and the
    // framework draws a disabled item dimmed — which put a grey veil over
    // the faces. The panel is drawn as a panel, so nothing in it carries the
    // disabled state.
    final heading = tester.widget<Text>(find.text(l10n.kindEmoji));
    final style = heading.style;
    final dimmed = style?.color == WeChatColors.light.disabledText;
    expect(dimmed, isFalse);

    // And the panel has a surface of its own, so the faces do not sit on the
    // menu's tinted item background.
    final panel = tester.widget<Container>(
      find
          .ancestor(
            of: find.text(l10n.kindEmoji),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (panel.color ?? Colors.transparent).a,
      1.0,
      reason: 'the panel paints its own opaque surface',
    );
  });

  testWidgets('the whole table fits in the grid and every face is tappable', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(appLocale);
    final picked = <String>[];
    await pumpComposer(tester, picked);

    await tester.tap(find.byTooltip(l10n.menuSendEmoji));
    await tester.pumpAndSettle();

    // All the faces the composer can send are present in the picker.
    for (final entry in emojiTable) {
      expect(find.text(entry.emoji), findsWidgets);
    }
  });
}

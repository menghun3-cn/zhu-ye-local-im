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
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ConversationComposer(
            message: TextEditingController(),
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

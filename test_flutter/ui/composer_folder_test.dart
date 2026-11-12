import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// The composer's folder half: the toolbar's second attach tool, and the chip
/// a staged folder draws in the tray.
void main() {
  /// Pumps the composer with [attachments] staged and [onAttachFolder] wired.
  Future<void> pumpComposer(
    WidgetTester tester, {
    List<StagedAttachment> attachments = const [],
    VoidCallback? onAttachFolder,
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
            onAttachFolder: onAttachFolder,
            attachments: attachments,
            onRemoveAttachment: (_) {},
          ),
        ),
      ),
    );
  }

  group('the composer folder attachment', () {
    testWidgets('a staged folder is a name chip with a folder glyph', (
      tester,
    ) async {
      final home = tempDirectory('composer-folder-');
      final folder = Directory('${home.path}${Platform.pathSeparator}pics');
      folder.createSync();

      await pumpComposer(
        tester,
        attachments: [
          StagedAttachment(
            path: folder.path,
            name: 'pics',
            isImage: false,
            isFolder: true,
          ),
        ],
      );

      expect(find.text('pics'), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsWidgets);
      expect(
        find.byWidgetPredicate((w) => w is Image),
        findsNothing,
        reason: 'a folder has no preview to decode',
      );
      expect(find.byTooltip(l10n.removeAttachment), findsOneWidget);
    });

    testWidgets('the folder tool asks for a folder', (tester) async {
      var asked = 0;
      await pumpComposer(tester, onAttachFolder: () => asked++);

      await tester.tap(find.byTooltip(l10n.menuSendFolder));
      await tester.pump();

      expect(asked, 1);
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// The composer's attachment tray, on its own.
///
/// The tray draws a staged **picture** as a thumbnail of its own bytes and a
/// staged **file** as a name chip; these tests pin which is which, so that a
/// later tweak cannot quietly turn a picture back into `pasted-179….png`.
void main() {
  /// Pumps the composer with [attachments] staged.
  Future<void> pumpTray(
    WidgetTester tester,
    List<StagedAttachment> attachments,
  ) {
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
            attachments: attachments,
            onRemoveAttachment: (_) {},
          ),
        ),
      ),
    );
  }

  /// Writes [bytes] to a uniquely named temp file and tears it down after.
  ///
  /// The tray reads the bytes off disk — a path that does not exist would make
  /// every test below a test of the error path by accident.
  File pngFixture(String name, Uint8List bytes) {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$name',
    );
    file.writeAsBytesSync(bytes);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    return file;
  }

  /// Lets the real image decode run to completion (or failure) and re-pumps.
  ///
  /// A widget test's clock is fake, and a codec runs on real time: without
  /// this, a decode that *would* fail never fails, and the error path below
  /// would be untestable.
  Future<void> letDecodeSettle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  group('the composer attachment tray', () {
    testWidgets('a staged picture is a thumbnail of its own bytes', (
      tester,
    ) async {
      final png = pngFixture('tray-thumb-shot.png', onePixelPng);
      await pumpTray(tester, [
        StagedAttachment(path: png.path, name: 'shot.png', isImage: true),
      ]);
      await letDecodeSettle(tester);

      expect(
        find.text('shot.png'),
        findsNothing,
        reason: 'a picture is previewed by itself, not by its name',
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.image is ResizeImage,
          // Decoded at the size it is drawn, so five staged screenshots are
          // five small decodes, not five full-size ones in the image cache.
          description: 'the thumbnail image',
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip('shot.png'),
        findsOneWidget,
        reason: 'the name is gone from the face but not from the widget',
      );
      expect(
        find.byTooltip(l10n.removeAttachment),
        findsOneWidget,
        reason: 'the badge on the corner is the same remove affordance',
      );
      expect(
        find.byIcon(Icons.broken_image_outlined),
        findsNothing,
        reason: 'a real PNG decodes',
      );
    });

    testWidgets('a staged file is still a name chip', (tester) async {
      // A file has no preview to show, so its name is what it is previewed
      // by — the chip stays, and no image is resolved for it.
      final file = pngFixture('tray-chip-notes.txt', Uint8List.fromList([1]));
      await pumpTray(tester, [
        StagedAttachment(path: file.path, name: 'notes.txt', isImage: false),
      ]);
      await letDecodeSettle(tester);

      expect(find.text('notes.txt'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Image),
        findsNothing,
        reason: 'a file gets no image decode at all',
      );
      expect(find.byTooltip(l10n.removeAttachment), findsOneWidget);
    });

    testWidgets('a picture whose bytes cannot be decoded keeps its badge', (
      tester,
    ) async {
      // Extension says PNG, bytes say otherwise — the tray shows the broken
      // glyph on the grey, and the × stays because taking a bad staging back
      // out must not depend on whether the picture ever rendered.
      final bad = pngFixture('tray-broken.png', Uint8List.fromList([1, 2, 3]));
      await pumpTray(tester, [
        StagedAttachment(path: bad.path, name: 'broken.png', isImage: true),
      ]);
      await letDecodeSettle(tester);

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.byTooltip(l10n.removeAttachment), findsOneWidget);
      expect(
        find.byTooltip('broken.png'),
        findsOneWidget,
        reason: 'the name is still on the tooltip when the pixels are not',
      );
    });
  });
}

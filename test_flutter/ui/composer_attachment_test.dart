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
            onEmoji: (_) {},
            attachments: attachments,
            onRemoveAttachment: (_) {},
          ),
        ),
      ),
    );
  }

  /// Writes [bytes] to a temp file that goes away when the test does.
  ///
  /// The tray reads the bytes off disk — a path that does not exist would make
  /// every test below a test of the error path by accident. The file lives in a
  /// [tempDirectory], which is deliberately best-effort about the delete: a
  /// picture the tray has decoded keeps its bytes mapped on Windows until the
  /// widget tree that drew it is gone, and that outlives this teardown.
  File pngFixture(String name, Uint8List bytes) {
    final home = tempDirectory('composer-tray-');
    final file = File('${home.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  /// Whether the tray's thumbnail has answered — with pixels or with the
  /// broken-picture glyph.
  ///
  /// Two shapes, because the widget takes two: a decode that succeeds leaves a
  /// [RawImage] holding an image, and one that fails is handed to `errorBuilder`
  /// — which *replaces* the [RawImage] with the glyph. Waiting only for the
  /// first would hang on exactly the case the third test is about.
  bool thumbnailAnswered(WidgetTester tester) {
    if (find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty) {
      return true;
    }
    final raw = find.descendant(
      of: find.byType(Image),
      matching: find.byType(RawImage),
    );
    return raw.evaluate().isNotEmpty &&
        tester.widget<RawImage>(raw).image != null;
  }

  /// Waits for the tray's thumbnail to finish decoding — either way.
  ///
  /// A widget test's clock is fake and a codec runs on real time, so a decode
  /// that *would* fail never fails under a plain `pump`, and a fixed sleep can
  /// only guess at how long the engine needs. A staged *file* draws no image at
  /// all, so there is nothing to wait for and this returns at once — which is
  /// the state the chip test pins.
  Future<void> letDecodeSettle(WidgetTester tester) async {
    if (find.byType(Image).evaluate().isEmpty) return;
    await pumpUntil(
      tester,
      () => thumbnailAnswered(tester),
      description: 'the thumbnail’s decode to answer, one way or the other',
    );
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

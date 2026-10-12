import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/wechat/image_bubble.dart';

import '../support/ui_harness.dart';

/// The thumbnail an image message draws.
///
/// What is under test here is the *shape* of the preview. A picture is not a
/// square, and a message that cuts every one of them down to one is a message
/// that shows the middle of a screenshot and calls it the screenshot. These
/// tests read the size the layout actually gave the picture, which is the only
/// thing a user can see.
void main() {
  /// Wraps [child] the way a conversation would.
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  /// Writes a real picture of the given size and returns it.
  Future<File> picture(
    WidgetTester tester, {
    required int width,
    required int height,
  }) async {
    final home = tempDirectory('local-transfer-image-bubble-');
    final file = File('${home.path}${Platform.pathSeparator}picture.png');
    await writePng(tester, file, width: width, height: height);
    return file;
  }

  /// Pumps a bubble for [file] and waits for the picture itself to be drawn.
  ///
  /// The placeholder has no [Image] in it at all, so this is also the wait for
  /// "the decode finished" — a bubble that never gets past the placeholder
  /// times out here rather than asserting against the wrong box.
  Future<void> showBubble(WidgetTester tester, File file) async {
    await tester.pumpWidget(
      host(ImageBubble(path: file.path, name: 'picture.png')),
    );
    await pumpUntil(
      tester,
      () => find.byType(Image).evaluate().isNotEmpty,
      description: 'the picture to be decoded and drawn',
    );
  }

  testWidgets('a wide picture keeps its shape instead of being squared off', (
    tester,
  ) async {
    final file = await picture(tester, width: 1200, height: 300);
    await showBubble(tester, file);

    final size = tester.getSize(find.byType(Image));
    expect(
      size.width / size.height,
      closeTo(4, 0.01),
      reason: 'a 4:1 screenshot is drawn 4:1, not cropped to a square',
    );
    expect(
      size.width,
      200,
      reason: 'the long side is bounded to the thumbnail size',
    );
    expect(size.height, 50, reason: 'and the short side follows from it');
  });

  testWidgets('a tall picture keeps its shape too', (tester) async {
    final file = await picture(tester, width: 300, height: 1200);
    await showBubble(tester, file);

    final size = tester.getSize(find.byType(Image));
    expect(size.width / size.height, closeTo(0.25, 0.01));
    expect(
      size.height,
      200,
      reason: 'a portrait photograph is bounded by its height',
    );
    expect(size.width, 50);
  });

  testWidgets('a small picture is not blown up to fill the box', (
    tester,
  ) async {
    final file = await picture(tester, width: 40, height: 10);
    await showBubble(tester, file);

    // A picture read through `FileImage` is measured in its own pixels — the
    // provider's scale is 1 — so "40 pixels wide" means 40 logical pixels here,
    // whatever the display's pixel ratio is.
    final size = tester.getSize(find.byType(Image));
    expect(
      size.width,
      closeTo(40, 0.01),
      reason: 'a 40-pixel picture is drawn at 40 pixels, not upscaled to 200',
    );
    expect(size.height, closeTo(10, 0.01));
  });

  testWidgets('a picture that cannot be read falls back to its name', (
    tester,
  ) async {
    final home = tempDirectory('local-transfer-image-gone-');
    final missing = File('${home.path}${Platform.pathSeparator}gone.png');

    await tester.pumpWidget(
      host(ImageBubble(path: missing.path, name: 'gone.png')),
    );
    await pumpUntil(
      tester,
      () => find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty,
      description: 'the unreadable picture to fall back to its name',
    );

    expect(find.text('gone.png'), findsOneWidget);
    expect(
      find.byType(Image),
      findsNothing,
      reason: 'nothing is drawn for a picture that is not there',
    );
  });

  /// The click target a bubble wraps its picture in, if it has one.
  ///
  /// Scoped to the bubble because the framework's own chrome has [MouseRegion]s
  /// of its own — a `Scaffold` holds one — and a bare `find.byType` would find
  /// those instead of answering the question.
  final openTarget = find.descendant(
    of: find.byType(ImageBubble),
    matching: find.byType(MouseRegion),
  );

  testWidgets('a bubble with nothing to open into is not clickable', (
    tester,
  ) async {
    final file = await picture(tester, width: 400, height: 100);
    await showBubble(tester, file);

    expect(
      openTarget,
      findsNothing,
      reason: 'no onOpen means no click cursor on the picture',
    );
  });

  testWidgets('a bubble with somewhere to open into is clickable', (
    tester,
  ) async {
    final file = await picture(tester, width: 400, height: 100);
    var opened = 0;
    await tester.pumpWidget(
      host(
        ImageBubble(
          path: file.path,
          name: 'picture.png',
          onOpen: () => opened++,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(Image).evaluate().isNotEmpty,
      description: 'the picture to be decoded and drawn',
    );

    expect(openTarget, findsOneWidget);
    await tester.tap(find.byType(ImageBubble));
    expect(opened, 1, reason: 'clicking the thumbnail opens the full picture');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

/// Enter and Shift+Enter in the composer, pressed as keys.
///
/// A key event and a text-input action are two roads to the same
/// [ConversationComposer.onSend], and they are not interchangeable: the keys
/// are what a user presses on a desktop, and it was the *key* road that used to
/// turn Shift+Enter into a send. The action road — a soft keyboard's send key —
/// is pinned where it belongs, by driving `TextInputAction.send`.
///
/// The chords cannot be told apart by the action they end in, which is the
/// whole reason they are claimed as keys, so a test that drove the action
/// instead of the keys would pass over the bug these tests exist for.
void main() {
  /// Pumps the composer on its own, collecting what it asks to send.
  ///
  /// Collects the text as it stood at the moment of the send rather than only
  /// counting sends: the two chords are only right together if the line breaks
  /// are still in what goes out.
  Future<TextEditingController> pumpComposer(
    WidgetTester tester,
    List<String> sent,
  ) async {
    final message = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ConversationComposer(
            message: message,
            onSend: () => sent.add(message.text),
            onPaste: () async => false,
            onAttach: () {},
          ),
        ),
      ),
    );
    return message;
  }

  /// Types [text] into the box, which puts the caret at the end of it.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  /// Presses [key] on its own.
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  /// Presses [key] with Shift held, the way a user breaks a line.
  ///
  /// The modifier is held down *across* the press rather than reported as part
  /// of it: a `SingleActivator(shift: true)` reads the keyboard's state, so a
  /// chord that only marked the key event itself would activate nothing.
  Future<void> pressShifted(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  testWidgets('a bare Enter asks to send and leaves no line break', (
    tester,
  ) async {
    final sent = <String>[];
    final message = await pumpComposer(tester, sent);
    await type(tester, 'hello');

    await press(tester, LogicalKeyboardKey.enter);

    expect(sent, ['hello'], reason: 'Enter is the send key in a chat box');
    expect(message.text, 'hello', reason: 'and a send is not a line break');
  });

  testWidgets('Shift+Enter breaks the line and asks for nothing', (
    tester,
  ) async {
    final sent = <String>[];
    final message = await pumpComposer(tester, sent);
    await type(tester, 'hello');

    await pressShifted(tester, LogicalKeyboardKey.enter);

    expect(
      sent,
      isEmpty,
      reason: 'the break is the whole point of the chord — it must not send',
    );
    expect(message.text, 'hello\n');
    expect(
      message.selection,
      const TextSelection.collapsed(offset: 6),
      reason: 'the caret follows what was inserted',
    );
  });

  testWidgets('the break replaces whatever it is typed over', (tester) async {
    final sent = <String>[];
    final message = await pumpComposer(tester, sent);
    await type(tester, 'hello');
    message.selection = const TextSelection(baseOffset: 0, extentOffset: 5);

    await pressShifted(tester, LogicalKeyboardKey.enter);

    expect(
      message.text,
      '\n',
      reason: 'an Insert replaces the selection, so a break has to as well',
    );
    expect(sent, isEmpty);
  });

  testWidgets('the numpad keys mean what the main keys mean', (tester) async {
    final sent = <String>[];
    final message = await pumpComposer(tester, sent);
    await type(tester, 'one');

    await press(tester, LogicalKeyboardKey.numpadEnter);
    expect(sent, ['one'], reason: 'the numpad sends as well');

    await type(tester, 'two');
    await pressShifted(tester, LogicalKeyboardKey.numpadEnter);
    expect(sent, ['one'], reason: 'Shift on the numpad breaks the line too');
    expect(message.text, 'two\n');
  });

  testWidgets('a break is part of the message that goes out', (tester) async {
    final sent = <String>[];
    final message = await pumpComposer(tester, sent);
    await type(tester, 'first');

    await pressShifted(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.enter);

    expect(sent, ['first\n'], reason: 'the newline goes out with the text');
    expect(
      message.text,
      'first\n',
      reason: 'emptying the box is the conversation\'s job, not the field\'s',
    );
  });

  group('the box a message is typed into', () {
    /// The box the typed text sits in, which is the composer's own container.
    ///
    /// Not the `TextField` itself: the field inside it draws nothing at all —
    /// no border, no minimum height — because the container around it is the
    /// thing a user sees. Measuring the field would be measuring a widget with
    /// no fill, no frame and no say in how tall the row is.
    double boxHeight(WidgetTester tester) => tester
        .getSize(
          find
              .ancestor(
                of: find.byType(TextField),
                matching: find.byType(Container),
              )
              .first,
        )
        .height;

    testWidgets('is one control tall', (tester) async {
      await pumpComposer(tester, <String>[]);

      // Measured rather than asked for, because the number that matters is the
      // one on screen: a `constraints` a later change overrode would leave the
      // token correct and the box the wrong size.
      expect(
        boxHeight(tester),
        WeChat.composerControl,
        reason: 'the drawn height is the token, not something near it',
      );
      // Which is taller than it used to be. The complaint was that this box was
      // a strip rather than a box, so the assertion is against the number it
      // was, not just against a token that could be lowered to match.
      expect(
        boxHeight(tester),
        greaterThan(32),
        reason: 'and taller than the strip it was before',
      );
    });

    testWidgets('keeps an outline even though text fields no longer do', (
      tester,
    ) async {
      await pumpComposer(tester, <String>[]);

      // The field itself draws none of it. Every outline the theme gives a text
      // field is turned off here on purpose, because the box around it is the
      // frame — a field drawing its own inside the composer's would be a box in
      // a box. So the assertion is about the *container*, which is what a user
      // would call the field's border.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.decoration?.border,
        InputBorder.none,
        reason: 'the field defers to the box around it',
      );

      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration;
      expect(
        decoration,
        isA<BoxDecoration>(),
        reason: 'the composer draws the field\'s fill itself',
      );
      expect(
        (decoration! as BoxDecoration).color,
        isNotNull,
        reason: 'and it is filled, so the box is visible against the page',
      );
    });

    testWidgets('is shorter than an ordinary dialog field, not taller', (
      tester,
    ) async {
      await pumpComposer(tester, <String>[]);

      // Deliberately *not* the theme's `fieldHeight`: a form field sits under a
      // label and needs the room; the composer shares its row with two buttons
      // and has to line up with them. Asserting the difference is what keeps a
      // later "make all fields the same" from silently making the composer
      // taller than the row it lives in.
      expect(
        boxHeight(tester),
        lessThan(WeChat.fieldHeight),
        reason: 'the composer is not a form field',
      );
    });

    testWidgets('the send button is filled and lines up with the box', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(appLocale);
      await pumpComposer(tester, <String>[]);
      await type(tester, 'ready');

      // Filled rather than a word: sending is the action of this surface. It
      // used to be a `TextButton`, which is the shape for a step that is *not*
      // the point of the screen.
      final send = find.widgetWithText(FilledButton, l10n.send);
      expect(send, findsOneWidget);
      expect(
        find.widgetWithText(TextButton, l10n.send),
        findsNothing,
        reason: 'the send is the action here, so it is drawn as one',
      );

      // And it is at least as tall as the box it sends from — the thing a user
      // reported was a pill visibly shorter than the composer beside it.
      expect(
        tester.getSize(send).height,
        greaterThanOrEqualTo(boxHeight(tester)),
        reason: 'a button shorter than its own field reads as an afterthought',
      );
      expect(
        tester.getSize(send).width,
        greaterThanOrEqualTo(60),
        reason: 'wide enough for the word plus its own padding',
      );
    });
  });
}

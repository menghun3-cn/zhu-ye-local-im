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
            onEmoji: (_) {},
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

  group('the input area, as WeChat draws it', () {
    /// The board the whole input area is drawn on.
    ///
    /// The container with the board's colour, found by the field inside it
    /// rather than by type: the board is a plain `Container`, and the field is
    /// the one thing that is certainly inside it.
    BoxDecoration boardDecoration(WidgetTester tester) =>
        (tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.byType(TextField),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!)
            as BoxDecoration;

    testWidgets('is a rounded board of its own', (tester) async {
      await pumpComposer(tester, <String>[]);

      // WeChat's input area is a *card* laid on the conversation: a lighter
      // board with rounded corners, floating with a margin from the window's
      // edge. It is not a strip welded to the bottom and not a hairline above.
      final decoration = boardDecoration(tester);
      expect(
        decoration.color,
        WeChatColors.light.composerBoard,
        reason: 'the board is a panel of its own colour',
      );
      expect(
        decoration.borderRadius,
        BorderRadius.circular(WeChat.composerBoardRadius),
        reason: 'and it is rounded, the way the reference is',
      );
      // The board *does* carry a hairline: the reference draws one around the
      // input area, and it is what says where the board ends — the two greys
      // are a step apart as well, so the line is not the only thing doing it.
      expect(decoration.border, isNotNull);
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, WeChatColors.light.composerBoardBorder);
    });

    testWidgets('the text area is the height the reference draws', (
      tester,
    ) async {
      await pumpComposer(tester, <String>[]);

      // Measured rather than asked for, because the number that matters is
      // the one on screen: a `constraints` a later change overrode would leave
      // the token correct and the field the wrong size.
      final height = tester
          .getSize(
            find
                .ancestor(
                  of: find.byType(TextField),
                  matching: find.byType(ConstrainedBox),
                )
                .first,
          )
          .height;
      expect(
        height,
        greaterThanOrEqualTo(WeChat.composerFieldHeight),
        reason: 'the reference\'s text area is 56 tall for one line',
      );
    });

    testWidgets('the text is written straight onto the board', (tester) async {
      await pumpComposer(tester, <String>[]);

      // No frame at all: WeChat's input area draws no border around the text,
      // so the field must not draw one either. The earlier design drew a
      // hairline box with a brand ring while focused; both belonged to that
      // frame.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.border, InputBorder.none);
      expect(field.decoration?.enabledBorder, InputBorder.none);
      expect(field.decoration?.focusedBorder, InputBorder.none);

      // And there is no box around it either: the board *is* the frame.
      expect(
        find.ancestor(
          of: find.byType(TextField),
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
        reason: 'the board is the only frame there is',
      );
    });

    testWidgets('the tools are bare glyphs in a row', (tester) async {
      final l10n = lookupAppLocalizations(appLocale);
      await pumpComposer(tester, <String>[]);

      // A face and a file, side by side on the lower edge of the board.
      final face = tester.getRect(find.byTooltip(l10n.menuSendEmoji));
      final file = tester.getRect(find.byTooltip(l10n.menuSendFile));
      expect(face.left, lessThan(file.left), reason: 'the face comes first');
      expect(
        face.center.dy,
        closeTo(file.center.dy, 0.01),
        reason: 'and the two share a line',
      );

      // Each is a line-drawn glyph rather than a framed button: a row of
      // little squares would read as a form, and WeChat's does not.
      expect(
        find.descendant(
          of: find.byTooltip(l10n.menuSendFile),
          matching: find.byType(OutlinedButton),
        ),
        findsNothing,
        reason: 'a tool is a glyph, not a button with a border',
      );
      expect(
        find.descendant(
          of: find.byTooltip(l10n.menuSendFile),
          matching: find.byIcon(Icons.folder_outlined),
        ),
        findsOneWidget,
      );

      // The glyph is drawn at the size the reference measures. The
      // framework's own IconButton padding is 8 on every side, and inside a
      // 28pt box that squashes a 22pt glyph down to 12 — a tool that looks
      // half the size it is supposed to be.
      expect(
        tester
            .getSize(find.byIcon(Icons.sentiment_satisfied_alt_outlined))
            .width,
        WeChat.composerIconSize,
        reason: 'the face is drawn at the size the reference measures',
      );

      // And the step between two tools is 45, which is what the reference
      // measures from one glyph's centre to the next.
      expect(
        file.left - face.left,
        WeChat.composerIconBox + WeChat.composerIconGap,
        reason: 'the tools are 45 apart, as in the reference',
      );
    });

    testWidgets('the send sits at the bottom right of the board', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(appLocale);
      await pumpComposer(tester, <String>[]);
      await type(tester, 'ready');

      final send = find.widgetWithText(FilledButton, l10n.send);
      expect(send, findsOneWidget);
      expect(
        find.widgetWithText(TextButton, l10n.send),
        findsNothing,
        reason: 'the send is the action here, so it is drawn as one',
      );

      final sendRect = tester.getRect(send);
      expect(sendRect.height, WeChat.composerSendHeight);
      expect(sendRect.width, WeChat.composerSendWidth);

      // Bottom right of the board, the way WeChat puts it: the text area is
      // the wide thing at the top, and the send is down at the far end of the
      // tools' line. The insets are measured from the board's **inner**
      // edge, because the hairline is drawn inside the board's own box.
      final board = tester.getRect(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );
      final inner = WeChat.composerBoardBorderWidth;
      expect(
        sendRect.right,
        closeTo(board.right - inner - WeChat.composerSendRightInset, 0.01),
        reason: 'the send is against the board\'s right edge',
      );
      expect(
        sendRect.bottom,
        closeTo(board.bottom - inner - WeChat.composerSendBottomInset, 0.01),
        reason: 'and against its bottom edge',
      );
    });

    testWidgets('the send is grey until there is something to send', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(appLocale);
      await pumpComposer(tester, <String>[]);

      final send = find.widgetWithText(FilledButton, l10n.send);
      final style = tester.widget<FilledButton>(send).style!;

      // Empty box: a grey send. The difference between grey and green is the
      // button's whole message, so it is asserted rather than assumed.
      expect(
        style.backgroundColor?.resolve(const <WidgetState>{}),
        WeChatColors.light.composerSendDisabled,
        reason: 'an empty box has nothing to send, and the button says so',
      );
      expect(
        style.foregroundColor?.resolve(const <WidgetState>{}),
        WeChatColors.light.onComposerSendDisabled,
      );
      // The button still answers the click: grey says "there is nothing here
      // to send", and a control that stopped answering would swallow the
      // click and the focus with it.
      expect(
        tester.widget<FilledButton>(send).onPressed,
        isNotNull,
        reason: 'the send always answers the click',
      );

      await type(tester, 'ready');
      final live = tester.widget<FilledButton>(send).style!;
      expect(
        live.backgroundColor?.resolve(const <WidgetState>{}),
        WeChatColors.light.brandStrong,
        reason: 'with something in the box the send is the action green',
      );
      expect(
        live.foregroundColor?.resolve(const <WidgetState>{}),
        WeChatColors.light.onBrandStrong,
      );
    });
  });
}

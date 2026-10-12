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
}

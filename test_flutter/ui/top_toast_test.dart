import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/feedback.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/top_toast.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

/// The refusal notice, and where it is shown.
///
/// It used to be a [SnackBar], which rises from the bottom of the window —
/// which is exactly where the input area is. A message about a message that
/// could not be sent was therefore laid over the box the user was about to
/// type the next one into. The toast is at the top for that reason, and this
/// is the test that keeps it there.
void main() {
  /// Pumps a screen with a button that fails the way the app fails.
  Future<void> pumpFailingScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => guarded(
                  context,
                  () async =>
                      throw const AppStateException(AppRefusal.noPeerConnected),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a refusal is a toast at the top of the window', (tester) async {
    final l10n = lookupAppLocalizations(appLocale);
    await pumpFailingScreen(tester);

    await tester.tap(find.text('go'));
    await tester.pump();

    // The refusal is on screen, in the app's own words.
    expect(find.text(l10n.refusalNoPeerConnected), findsOneWidget);

    // And it is at the **top**: the notice is above the middle of the window,
    // which is where the bottom-anchored SnackBar used to be.
    final toast = tester.getRect(find.text(l10n.refusalNoPeerConnected));
    expect(
      toast.center.dy,
      lessThan(300),
      reason: 'the notice belongs at the top, not over the input area',
    );

    // Nothing was raised from the bottom: there is no SnackBar in the tree.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the toast goes away on its own', (tester) async {
    final l10n = lookupAppLocalizations(appLocale);
    await pumpFailingScreen(tester);

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text(l10n.refusalNoPeerConnected), findsOneWidget);

    // Three seconds, which is what the toast asks for.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text(l10n.refusalNoPeerConnected), findsNothing);
  });

  testWidgets('the toast is drawn at the top margin the theme names', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => TopToast.show(context, 'hello'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final bar = tester.getRect(find.text('hello'));
    expect(
      bar.top,
      greaterThanOrEqualTo(WeChat.toastTopMargin),
      reason: 'the toast hangs below the window\'s top edge',
    );
  });
}

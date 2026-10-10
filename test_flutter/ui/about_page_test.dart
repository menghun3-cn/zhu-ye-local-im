import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/about_page.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

/// An update checker that answers what the test tells it to, and counts how
/// often it was asked.
///
/// The same seam argument as `ScriptedPicker` in the harness: asking GitHub is
/// the one thing a widget test cannot do, and there would otherwise be no way
/// to reach the "there is a newer version" screen at all.
class _StubUpdateChecker implements UpdateChecker {
  _StubUpdateChecker._(this.answer);

  /// What [latest] answers with.
  final UpdateCheck answer;

  /// How many times the page asked.
  int asked = 0;

  /// Puts a stub in force for one test, and takes it out afterwards.
  static _StubUpdateChecker install(UpdateCheck answer) {
    final checker = _StubUpdateChecker._(answer);
    UpdateResolution.checker = checker;
    addTearDown(UpdateResolution.reset);
    return checker;
  }

  @override
  Future<UpdateCheck> latest() async {
    asked += 1;
    return answer;
  }
}

/// What the About surface says, and what pressing its button does.
///
/// What is under test is the page: that it names the build it is running, that
/// nothing reaches the network until somebody asks, and that each of the four
/// answers an [UpdateCheck] can carry arrives as a different sentence rather
/// than as a shared "it failed".
void main() {
  final l10n = lookupAppLocalizations(appLocale);

  /// Shows the page over [checker], in the theme and language the app uses.
  Future<void> show(WidgetTester tester, UpdateChecker checker) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appLocales,
        theme: WeChat.theme(WeChatColors.light),
        home: const Scaffold(body: AboutPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Presses the button and lets the answer land.
  Future<void> pressCheck(WidgetTester tester) async {
    await tester.tap(find.text(l10n.aboutCheckForUpdates));
    await tester.pumpAndSettle();
  }

  testWidgets('names the build that is running', (tester) async {
    final checker = _StubUpdateChecker.install(
      const UpdateCheck(UpdateOutcome.upToDate),
    );
    await show(tester, checker);

    expect(find.text(l10n.appTitle), findsOneWidget);
    expect(find.text(l10n.aboutVersion(appVersion)), findsOneWidget);
    expect(
      checker.asked,
      0,
      reason: 'opening the page must not reach outside the network',
    );
    // Nothing has been asked, so nothing is claimed either way.
    expect(find.text(l10n.aboutUpToDate), findsNothing);
    expect(find.text(l10n.aboutUnreachable), findsNothing);
  });

  testWidgets('asks only when the button is pressed', (tester) async {
    final checker = _StubUpdateChecker.install(
      const UpdateCheck(UpdateOutcome.upToDate),
    );
    await show(tester, checker);

    await pressCheck(tester);

    expect(checker.asked, 1);
    expect(find.text(l10n.aboutUpToDate), findsOneWidget);
  });

  testWidgets('offers the download page when there is a newer version', (
    tester,
  ) async {
    final checker = _StubUpdateChecker.install(
      const UpdateCheck(
        UpdateOutcome.available,
        version: '9.9.9',
        url: 'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
      ),
    );
    await show(tester, checker);

    await pressCheck(tester);

    expect(find.text(l10n.aboutUpdateAvailable('9.9.9')), findsOneWidget);
    expect(find.text(l10n.aboutOpenDownload), findsOneWidget);
    // The address is printed as well as offered: a machine whose browser cannot
    // be opened is exactly the machine that has to copy it by hand.
    expect(
      find.text(
        'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
      ),
      findsOneWidget,
    );
  });

  testWidgets('says so when there is nothing to compare against', (
    tester,
  ) async {
    // The state the repository is genuinely in until a release is published,
    // and not an error: there is nothing wrong with the app or the network.
    final checker = _StubUpdateChecker.install(
      const UpdateCheck(UpdateOutcome.noRelease),
    );
    await show(tester, checker);

    await pressCheck(tester);

    expect(find.text(l10n.aboutNoRelease), findsOneWidget);
    expect(find.text(l10n.aboutOpenDownload), findsNothing);
  });

  testWidgets('says so when the question could not be asked', (tester) async {
    final checker = _StubUpdateChecker.install(UpdateCheck.unreachable);
    await show(tester, checker);

    await pressCheck(tester);

    expect(find.text(l10n.aboutUnreachable), findsOneWidget);
    expect(find.text(l10n.aboutNoRelease), findsNothing);
  });

  testWidgets('always says how an upgrade is done by hand', (tester) async {
    final checker = _StubUpdateChecker.install(UpdateCheck.unreachable);
    await show(tester, checker);

    // Whatever the network did, the way that needs no network is on the card.
    expect(find.text(l10n.aboutHowToUpgrade), findsOneWidget);
  });
}

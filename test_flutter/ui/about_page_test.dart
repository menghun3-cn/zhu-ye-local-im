import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/about_page.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// What the About surface says, and what pressing its buttons does.
///
/// What is under test is the page: that it names the build it is running, that
/// nothing leaves this page for the network until somebody asks, and that each
/// of the four answers an [UpdateCheck] can carry arrives as a different
/// sentence rather than as a shared "it failed".
///
/// The page's own button is not the only thing that asks — the application asks
/// once as it comes up, which is what the rail's update entry reads, and that is
/// `test_flutter/ui/update_rail_test.dart`'s subject. What is asserted here is
/// narrower and unchanged: *this page* asks nothing until it is asked, so that
/// looking at the About card is not itself a request.
void main() {
  final l10n = lookupAppLocalizations(appLocale);

  /// Shows the page in the theme and language the app uses.
  Future<void> show(WidgetTester tester) async {
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

  /// Presses the button showing [label] and lets whatever it starts land.
  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('names the build that is running', (tester) async {
    final checker = ScriptedUpdateChecker.install(
      const UpdateCheck(UpdateOutcome.upToDate),
    );
    await show(tester);

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
    final checker = ScriptedUpdateChecker.install(
      const UpdateCheck(UpdateOutcome.upToDate),
    );
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);

    expect(checker.asked, 1);
    expect(find.text(l10n.aboutUpToDate), findsOneWidget);
  });

  testWidgets('offers the download page when there is a newer version', (
    tester,
  ) async {
    final checker = ScriptedUpdateChecker.install(
      const UpdateCheck(
        UpdateOutcome.available,
        version: '9.9.9',
        url: 'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
      ),
    );
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);

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
    expect(checker.asked, 1);
  });

  testWidgets('hands the download address to the platform to open', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(
      const UpdateCheck(
        UpdateOutcome.available,
        version: '9.9.9',
        url: 'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
      ),
    );
    // Installed rather than driven: the real opener starts the machine's
    // browser, and this test is about which address the page hands over.
    final links = ScriptedLinkOpener.install();
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);
    await press(tester, l10n.aboutOpenDownload);

    expect(links.opened, [
      'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
    ]);
  });

  testWidgets('says so when there is nothing to compare against', (
    tester,
  ) async {
    // The state the repository is genuinely in until a release is published,
    // and not an error: there is nothing wrong with the app or the network.
    ScriptedUpdateChecker.install(const UpdateCheck(UpdateOutcome.noRelease));
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);

    expect(find.text(l10n.aboutNoRelease), findsOneWidget);
    expect(find.text(l10n.aboutOpenDownload), findsNothing);
  });

  testWidgets('says so when the question could not be asked', (tester) async {
    ScriptedUpdateChecker.install(UpdateCheck.unreachable);
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);

    expect(find.text(l10n.aboutUnreachable), findsOneWidget);
    expect(find.text(l10n.aboutNoRelease), findsNothing);
  });

  testWidgets('always says how an upgrade is done by hand', (tester) async {
    ScriptedUpdateChecker.install(UpdateCheck.unreachable);
    await show(tester);

    // Whatever the network did, the way that needs no network is on the card.
    expect(find.text(l10n.aboutHowToUpgrade), findsOneWidget);
  });
}

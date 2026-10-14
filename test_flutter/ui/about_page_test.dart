import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/about_page.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/update_install.dart';
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
///
/// The second half is the one-click install: that it is offered exactly when
/// this build can replace itself *and* there is something to replace it with,
/// that the folder is only handed over once somebody has answered the question
/// the update asks first, that answering no leaves the fetched package where it
/// is, and that each way it can fail arrives as its own sentence. What an
/// install does to the folder — the download, the checksum, the renames — is
/// not here: it needs no widgets, and it is `test/ui/update_install_test.dart`.
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

  /// Presses the button showing [label] and draws the frames it causes.
  ///
  /// `pumpAndSettle` cannot be used for the hand-over, and the reason is worth
  /// writing down: the last thing this card draws is a bar whose length is not
  /// known, and an indeterminate [LinearProgressIndicator] animates for as long
  /// as it is on screen. Waiting for the tree to go quiet is therefore waiting
  /// for a process that is on its way out — which never happens. Two frames
  /// instead of one, because the first is the press and the second is the state
  /// the callbacks left behind.
  Future<void> pressAndDraw(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump();
  }

  /// Waits for the question an update asks before anything closes.
  ///
  /// A dialog of the tree's own rather than a state on the page, so what is
  /// waited for is the dialog itself.
  Future<void> pumpUntilAsked(WidgetTester tester) => pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
    description: 'the update to ask before anything closes',
  );

  /// Answers the question the update asked with the button showing [label], and
  /// lets the answer land.
  ///
  /// The dialog is waited out rather than pumped past: its exit animation is
  /// what stands between the tap and the page's own continuation, and a fixed
  /// number of frames would be a guess about how long a route takes.
  Future<void> tapUpdateAnswer(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await pumpUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
      description: 'the question to close',
    );
    await tester.pump();
    await tester.pump();
  }

  /// The answer that says a newer build exists.
  const available = UpdateCheck(
    UpdateOutcome.available,
    version: '9.9.9',
    url: 'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
  );

  /// The same answer, from a release that says what it changes.
  const availableWithNotes = UpdateCheck(
    UpdateOutcome.available,
    version: '9.9.9',
    url: 'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
    notes: '### 新增\n\n- 一键更新\n\n### 修复\n\n- 修好了',
  );

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

  testWidgets('the buttons that do something here are filled, one of them', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(available);
    await show(tester);

    // Checking is the ordinary action on this page, so it is drawn as the
    // ordinary action — the filled pill the rest of the app uses. It used to be
    // a `TextButton` with an icon, which is the shape for a *secondary* step,
    // and a page whose only button looks secondary reads as a page with no
    // action on it.
    expect(
      find.widgetWithText(FilledButton, l10n.aboutCheckForUpdates),
      findsOneWidget,
      reason: 'the page\'s own action is the filled one',
    );
    expect(
      find.widgetWithText(TextButton, l10n.aboutCheckForUpdates),
      findsNothing,
      reason: 'a word-shaped button would say this is not the way in',
    );

    await press(tester, l10n.aboutCheckForUpdates);

    // Installing is the same kind of thing — a step taken on this page — so it
    // is filled too. Opening the download page is *not*: it leaves for a
    // browser, and dressing it like the others would make three buttons of
    // equal weight where the user has one decision to make.
    expect(
      find.widgetWithText(FilledButton, l10n.aboutUpdateInstall),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, l10n.aboutOpenDownload),
      findsOneWidget,
      reason: 'leaving the app is not the same action as acting in it',
    );
  });

  testWidgets('offers the download page when there is a newer version', (
    tester,
  ) async {
    final checker = ScriptedUpdateChecker.install(available);
    // Not about installing: what this test is about is the page's answer to a
    // newer version, and the plain download path is the same on every platform.
    ScriptedUpdateInstaller.replace();
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

  testWidgets('shows the version, and what the release says it changes', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(availableWithNotes);
    ScriptedUpdateInstaller.replace();
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);

    // The version answers "is there something to fetch"; the notes answer "do I
    // want it", which is the question somebody standing in front of a button
    // that replaces this program actually has.
    expect(find.text(l10n.aboutUpdateAvailable('9.9.9')), findsOneWidget);
    expect(find.text(l10n.aboutUpdateNotes), findsOneWidget);
    // Sections and items, with the markup they were written in taken off: the
    // reader is being told what changed, not shown a file.
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('修复'), findsOneWidget);
    expect(find.text('一键更新'), findsOneWidget);
    expect(find.text('修好了'), findsOneWidget);
    expect(find.textContaining('###'), findsNothing);
  });

  testWidgets('says nothing extra when the release carried no notes', (
    tester,
  ) async {
    // `--generate-notes` writes some of its own and somebody filling in the web
    // form may write none, so a release with an empty body is a release to show
    // the version of and nothing else. An empty panel with a title on it would
    // be claiming there is news when there is none.
    ScriptedUpdateChecker.install(available);
    ScriptedUpdateInstaller.replace();
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);

    expect(find.text(l10n.aboutUpdateAvailable('9.9.9')), findsOneWidget);
    expect(find.text(l10n.aboutUpdateNotes), findsNothing);
  });

  testWidgets('hands the download address to the platform to open', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(available);
    ScriptedUpdateInstaller.replace();
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

  testWidgets('offers the one-click update once a newer version is known', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(available);
    final installer = ScriptedUpdateInstaller.replace(supported: true);
    await show(tester);

    // Not before the question has been answered: there would be nothing to
    // install, and a download that has no version behind it is not an offer.
    expect(find.text(l10n.aboutUpdateInstall), findsNothing);

    await press(tester, l10n.aboutCheckForUpdates);

    expect(find.text(l10n.aboutUpdateInstall), findsOneWidget);
    // The sentence that explains the button replaces the by-hand one, which is
    // still offered — by the button beside it rather than in words.
    expect(find.text(l10n.aboutUpdateInstallHint), findsOneWidget);
    expect(installer.askedFor, isEmpty);
  });

  testWidgets('leaves the one-click update out where this build cannot '
      'replace itself', (tester) async {
    ScriptedUpdateChecker.install(available);
    ScriptedUpdateInstaller.replace();
    await show(tester);

    await press(tester, l10n.aboutCheckForUpdates);

    expect(find.text(l10n.aboutUpdateInstall), findsNothing);
    expect(find.text(l10n.aboutHowToUpgrade), findsOneWidget);
    // The way that needs no help from the page is still there.
    expect(find.text(l10n.aboutOpenDownload), findsOneWidget);
  });

  testWidgets('asks before it closes, and installs when told to', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(available);
    final installer = ScriptedUpdateInstaller.replace(
      supported: true,
      progress: const [
        UpdateInstallProgress(
          UpdateInstallStage.downloading,
          received: 1048576,
          total: 2097152,
        ),
        UpdateInstallProgress(UpdateInstallStage.verifying),
        UpdateInstallProgress(UpdateInstallStage.staging),
      ],
      prepared: const PreparedUpdate.installer(
        'LocalTransfer-9.9.9-windows-x64-setup.exe',
      ),
    );
    await show(tester);
    await press(tester, l10n.aboutCheckForUpdates);

    await pressAndDraw(tester, l10n.aboutUpdateInstall);
    await pumpUntilAsked(tester);

    // The question is on screen and nothing has been handed over: the package
    // is in place and this build is still running, which is the whole point of
    // asking rather than doing.
    expect(find.text(l10n.aboutUpdateConfirmTitle), findsOneWidget);
    expect(find.text(l10n.aboutUpdateConfirmBody('9.9.9')), findsOneWidget);
    expect(installer.applied, isEmpty);

    await tapUpdateAnswer(tester, l10n.aboutUpdateConfirmApply);

    expect(
      installer.applied.single.package,
      'LocalTransfer-9.9.9-windows-x64-setup.exe',
    );
    // The last thing the old build draws. The real installer ends the process
    // rather than returning, so this is the state the user is left looking at.
    expect(find.text(l10n.aboutUpdateHandingOver), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('changes nothing when the question is answered no', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(available);
    final installer = ScriptedUpdateInstaller.replace(
      supported: true,
      progress: const [UpdateInstallProgress(UpdateInstallStage.staging)],
      prepared: const PreparedUpdate.installer(
        'LocalTransfer-9.9.9-windows-x64-setup.exe',
      ),
    );
    await show(tester);
    await press(tester, l10n.aboutCheckForUpdates);

    await pressAndDraw(tester, l10n.aboutUpdateInstall);
    await pumpUntilAsked(tester);
    await tapUpdateAnswer(tester, l10n.cancel);

    // Nothing was handed over, nothing failed, and the package is where it was
    // fetched to — which is what the line says and the button offers again.
    expect(installer.applied, isEmpty);
    expect(find.text(l10n.aboutUpdateReady), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(l10n.aboutUpdateInstall), findsOneWidget);

    // And it offers it without fetching anything again: the package is already
    // in the update folder.
    await press(tester, l10n.aboutUpdateInstall);
    await pumpUntilAsked(tester);

    expect(installer.askedFor, hasLength(1));
    expect(find.text(l10n.aboutUpdateConfirmTitle), findsOneWidget);
  });

  testWidgets('shows the bytes while a download is running', (tester) async {
    ScriptedUpdateChecker.install(available);
    // A download that has not answered yet: the middle of one is the only place
    // the byte counts exist, and the only way to be in it is to hold the
    // attempt there.
    final running = Completer<UpdatePrepareResult>();
    ScriptedUpdateInstaller.replace(
      supported: true,
      progress: const [
        UpdateInstallProgress(
          UpdateInstallStage.downloading,
          received: 1048576,
          total: 4194304,
        ),
      ],
      hold: running,
    );
    await show(tester);
    await press(tester, l10n.aboutCheckForUpdates);

    await press(tester, l10n.aboutUpdateInstall);

    expect(find.textContaining(l10n.aboutUpdateDownloading), findsOneWidget);
    // Both halves of the pair come from the Transfers surface's own formatter,
    // so a download reads like every other byte count in the app.
    expect(
      find.textContaining(
        l10n.bytesOf(formatBytes(1048576), formatBytes(4194304)),
      ),
      findsOneWidget,
    );
    // No question yet: nothing is ready to ask about.
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('says why an update did not happen, and offers it again', (
    tester,
  ) async {
    ScriptedUpdateChecker.install(available);
    ScriptedUpdateInstaller.replace(
      supported: true,
      failure: UpdateInstallFailure.checksum,
    );
    await show(tester);
    await press(tester, l10n.aboutCheckForUpdates);

    await press(tester, l10n.aboutUpdateInstall);

    expect(find.text(l10n.updateFailureChecksum), findsOneWidget);
    // Nothing is in flight any more, and the same button is how it is retried:
    // "try again" and "do it" are one action with one name.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(l10n.aboutUpdateInstall), findsOneWidget);
  });

  testWidgets('says when a replacement never finished', (tester) async {
    // The trace of a hand-over that died: the build that failed was the new
    // one, and all it left behind is a window that came and went.
    ScriptedUpdateChecker.install(UpdateCheck.unreachable);
    ScriptedUpdateInstaller.replace(
      supported: true,
      leftOver: UpdateInstallFailure.handover,
    );
    await show(tester);

    expect(find.text(l10n.updateFailureHandover), findsOneWidget);
  });
}

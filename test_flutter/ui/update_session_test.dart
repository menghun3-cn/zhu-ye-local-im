import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/about_page.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/update_install.dart';
import 'package:local_transfer/ui/update_session.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

/// The update session: who owns a download, and what a restart finds.
///
/// What is under test is the seam the bug lived on — the download used to be
/// owned by the About page's state, so leaving the page dropped its answer
/// and a second press could put two fetches on one partial file. The session
/// is the owner now, and these tests stand on either side of it: that the
/// work survives the page, that a second request joins the first rather than
/// starting another, that a package a restart finds on disk is offered
/// rather than downloaded again, and that the question before closing is
/// asked once per prepared update.
void main() {
  final l10n = lookupAppLocalizations(appLocale);

  /// The answer that says a newer build exists.
  const available = UpdateCheck(
    UpdateOutcome.available,
    version: '9.9.9',
    url: 'https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest',
  );

  /// What a prepared installer hands back.
  const prepared = PreparedUpdate.installer(
    'LocalTransfer-9.9.9-windows-x64-setup.exe',
  );

  /// Shows the About card in the theme and language the app uses, on [session].
  Future<void> show(WidgetTester tester, UpdateInstallSession session) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appLocales,
        theme: WeChat.theme(WeChatColors.light),
        home: Scaffold(body: AboutPage(session: session)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Presses the button showing [label] and lets whatever it starts land.
  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Waits for the question an update asks before anything closes.
  Future<void> pumpUntilAsked(WidgetTester tester) => pumpUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
    description: 'the update to ask before anything closes',
  );

  group('UpdateInstallSession', () {
    test('joins a second install request to the one in flight', () async {
      final running = Completer<UpdatePrepareResult>();
      final installer = ScriptedUpdateInstaller.replace(
        supported: true,
        hold: running,
      );
      final session = UpdateInstallSession();
      addTearDown(session.dispose);

      // Neither is awaited: the first is still in flight, which is the point
      // — the second has to join it rather than start another fetch.
      final first = session.install(available);
      final second = session.install(available);

      expect(installer.askedFor, hasLength(1));
      expect(session.busy, isTrue);

      running.complete(const UpdatePrepareResult.ready(prepared));
      await first;
      await second;

      expect(session.prepared, prepared);
      expect(session.busy, isFalse);
    });

    test(
      'counts a press on a prepared update as a request for the question',
      () async {
        final installer = ScriptedUpdateInstaller.replace(
          supported: true,
          prepared: prepared,
        );
        final session = UpdateInstallSession();
        addTearDown(session.dispose);

        await session.install(available);
        expect(session.confirmRequests, 0);

        await session.install(available);
        await session.install(available);

        // The package was fetched once; the presses after it are what is left —
        // the question, asked again rather than a download started over.
        expect(installer.askedFor, hasLength(1));
        expect(session.confirmRequests, 2);
      },
    );

    test(
      'restore fetches nothing when no finished download is there',
      () async {
        final installer = ScriptedUpdateInstaller.replace(supported: true);
        final session = UpdateInstallSession();
        addTearDown(session.dispose);

        await session.restore(available);

        expect(installer.fetchedAsked.single.version, '9.9.9');
        expect(installer.askedFor, isEmpty);
        expect(session.prepared, isNull);
      },
    );

    test('restore stages what a finished download left behind', () async {
      final installer = ScriptedUpdateInstaller.replace(
        supported: true,
        fetched: true,
        prepared: prepared,
      );
      final session = UpdateInstallSession();
      addTearDown(session.dispose);

      await session.restore(available);

      // The prepare that ran is the local verify-and-stage one: the package
      // was already on disk, so this is the same call a press would make —
      // and the flag is what tells the card to offer it rather than announce.
      expect(installer.askedFor.single.version, '9.9.9');
      expect(session.prepared, prepared);
      expect(session.preparedIsRestore, isTrue);
    });

    test('looks for a finished download once per version', () async {
      final installer = ScriptedUpdateInstaller.replace(supported: true);
      final session = UpdateInstallSession();
      addTearDown(session.dispose);

      await session.restore(available);
      await session.restore(available);

      expect(installer.fetchedAsked, hasLength(1));
    });

    test('reset forgets what an earlier answer readied', () async {
      ScriptedUpdateInstaller.replace(supported: true, prepared: prepared);
      final session = UpdateInstallSession();
      addTearDown(session.dispose);
      await session.install(available);
      expect(session.prepared, isNotNull);

      session.reset();

      expect(session.prepared, isNull);
      expect(session.failure, isNull);
    });
  });

  group('the About card on a session', () {
    testWidgets('keeps a download running while the page is away', (
      tester,
    ) async {
      ScriptedUpdateChecker.install(available);
      final running = Completer<UpdatePrepareResult>();
      final installer = ScriptedUpdateInstaller.replace(
        supported: true,
        // A determinate fraction, so the progress bar is still and the test
        // can wait for the tree to settle — an indeterminate one animates
        // for as long as it is up, which is exactly as long as this download.
        progress: const [
          UpdateInstallProgress(
            UpdateInstallStage.downloading,
            received: 1,
            total: 2,
          ),
        ],
        hold: running,
      );
      final session = UpdateInstallSession();
      addTearDown(session.dispose);
      await show(tester, session);
      await press(tester, l10n.aboutCheckForUpdates);
      await press(tester, l10n.aboutUpdate);

      // Mid-download, the page goes away the way the My card list takes it.
      await tester.pumpWidget(const SizedBox());
      expect(session.busy, isTrue);

      // The fetch was never the page's to cancel: it finishes anyway, and a
      // card built afterwards finds the question already owed.
      running.complete(const UpdatePrepareResult.ready(prepared));
      await show(tester, session);
      await pumpUntilAsked(tester);

      expect(find.text(l10n.aboutUpdateConfirmTitle), findsOneWidget);
      expect(installer.applied, isEmpty);
    });

    testWidgets('shows the progress of a download still running to a card '
        'built mid-flight', (tester) async {
      ScriptedUpdateChecker.install(available);
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
      final session = UpdateInstallSession();
      addTearDown(session.dispose);
      await show(tester, session);
      await press(tester, l10n.aboutCheckForUpdates);
      await press(tester, l10n.aboutUpdate);

      // Rebuilt from scratch, the way coming back to the sub-page is: the
      // progress is the session's, so it is where it was left.
      await tester.pumpWidget(const SizedBox());
      await show(tester, session);

      expect(find.textContaining(l10n.aboutUpdateDownloading), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      running.complete(const UpdatePrepareResult.ready(prepared));
      await pumpUntilAsked(tester);
    });

    testWidgets('offers a package a restart found, without a question', (
      tester,
    ) async {
      ScriptedUpdateChecker.install(available);
      final installer = ScriptedUpdateInstaller.replace(
        supported: true,
        fetched: true,
        prepared: prepared,
      );
      final session = UpdateInstallSession();
      addTearDown(session.dispose);

      // What the shell does when the notice's answer lands: look before
      // asking, and stage what is already there.
      await session.restore(available);
      await show(tester, session);
      await tester.pumpAndSettle();

      // Ready is a state, not a popup: the card says the package is waiting
      // and no question was asked — opening a page is not a request to close
      // the app.
      expect(find.text(l10n.aboutUpdateReady), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      // The press that means it asks the question, and nothing is fetched
      // again to answer it.
      await press(tester, l10n.aboutUpdate);
      await pumpUntilAsked(tester);

      expect(installer.askedFor, hasLength(1));
      expect(find.text(l10n.aboutUpdateConfirmTitle), findsOneWidget);
    });
  });
}

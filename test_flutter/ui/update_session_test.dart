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
/// rather than downloaded again, and that a finished prepare is applied
/// without a second question.
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
      // A finished prepare is applied without being asked again: the press
      // that started the download was already the answer.
      expect(installer.applied, [prepared]);
    });

    test('applies a package restore found without fetching again', () async {
      final installer = ScriptedUpdateInstaller.replace(
        supported: true,
        fetched: true,
        prepared: prepared,
      );
      final session = UpdateInstallSession();
      addTearDown(session.dispose);

      // What a restart does: stage what the update folder already holds. A
      // restored package is only offered — opening a page is not a request
      // to close the app — so nothing has been applied yet.
      await session.restore(available);
      expect(installer.applied, isEmpty);

      await session.install(available);
      await session.install(available);

      // The package was fetched once; the presses after it are applies of
      // the same prepared update, not downloads started over.
      expect(installer.askedFor, hasLength(1));
      expect(installer.applied, hasLength(2));
    });

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
      // and finding it is not a request to close the app, so nothing was
      // applied.
      expect(installer.askedFor.single.version, '9.9.9');
      expect(session.prepared, prepared);
      expect(installer.applied, isEmpty);
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

      // The fetch was never the page's to cancel: it finishes anyway, and the
      // hand-over that follows needs no page at all.
      running.complete(const UpdatePrepareResult.ready(prepared));
      await pumpUntil(
        tester,
        () => installer.applied.isNotEmpty,
        description: 'the finished download to be applied',
      );

      expect(installer.applied.single.package, prepared.package);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shows the progress of a download still running to a card '
        'built mid-flight', (tester) async {
      ScriptedUpdateChecker.install(available);
      final running = Completer<UpdatePrepareResult>();
      final installer = ScriptedUpdateInstaller.replace(
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
      await pumpUntil(
        tester,
        () => installer.applied.isNotEmpty,
        description: 'the finished download to be applied',
      );
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
      // and nothing was applied — opening a page is not a request to close
      // the app.
      expect(find.text(l10n.aboutUpdateReady), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(installer.applied, isEmpty);

      // The press that means it applies the package, and nothing is fetched
      // again to answer it.
      await press(tester, l10n.aboutUpdate);
      await pumpUntil(
        tester,
        () => installer.applied.isNotEmpty,
        description: 'the offered package to be applied',
      );

      expect(installer.askedFor, hasLength(1));
      expect(installer.applied.single.package, prepared.package);
    });
  });
}

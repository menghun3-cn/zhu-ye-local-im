import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/update_notice.dart';

import '../support/ui_harness.dart';

/// The rail's update entry: when it is there, what the hover says, and where a
/// press goes.
///
/// This is one requirement of the release round — 「有版本更新时，做左侧菜单栏最
/// 下方显示"更新"按钮，鼠标滑过时显示要升级更新的版本号」 — and it can only be
/// asserted because of two seams. The answer comes from [ScriptedUpdateChecker],
/// so nothing here asks GitHub; the press lands in [ScriptedLinkOpener], so
/// nothing here starts a browser on the machine running the suite. Both matter
/// more than usual for this feature: the question is asked by the application
/// coming up rather than by a button, so a test that forgot the first seam would
/// leave a real request behind.
///
/// The notice is built here and handed to the shell rather than made inside it
/// — see `HomeShell.update` — which is what lets a test put a known answer in
/// the rail without waiting for `LocalTransferApp` to start.
void main() {
  /// A notice holding [answer], already asked.
  Future<UpdateNotice> noticeSaying(UpdateCheck answer) async {
    ScriptedUpdateChecker.install(answer);
    final notice = UpdateNotice();
    addTearDown(notice.dispose);
    await notice.check();
    return notice;
  }

  /// [matching] restricted to the rail.
  ///
  /// Scoped, and it has to be: the shell keeps all six surfaces alive in an
  /// `IndexedStack`, and several of the rail's labels are also headings inside
  /// the pages — 「关于」 is both the last destination and the About card's own
  /// title.
  Finder inRail(Finder matching) => find.descendant(
    of: windowA.within(find.byType(NavigationRail)),
    matching: matching,
  );

  /// An answer that says a newer build exists, at a version and address a
  /// person could read.
  const newerBuild = UpdateCheck(
    UpdateOutcome.available,
    version: '0.1.7',
    url: 'https://github.com/menghun3-cn/zhu-ye-local-im/releases/tag/v0.1.7',
  );

  testWidgets('is absent while this build is the latest one', (tester) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpWindow(
      tester,
      device,
      update: await noticeSaying(const UpdateCheck(UpdateOutcome.upToDate)),
    );

    expect(inRail(find.text(l10n.railUpdate)), findsNothing);
    // The six surfaces are untouched by its absence: the entry is added to the
    // rail, not put in place of anything.
    for (final label in [
      l10n.tabConversation,
      l10n.tabDevices,
      l10n.tabTransfers,
      l10n.tabClipboard,
      l10n.tabSettings,
      l10n.tabAbout,
    ]) {
      expect(inRail(find.text(label)), findsOneWidget, reason: label);
    }

    await shutdown(tester, [device]);
  });

  testWidgets('is absent when the question could not be asked', (tester) async {
    // A machine with no route out is the ordinary case, not a broken one, and
    // an entry offering an upgrade nobody can describe would be worse than no
    // entry at all.
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    final notice = await noticeSaying(UpdateCheck.unreachable);
    await pumpWindow(tester, device, update: notice);

    // Two different things, asserted separately: the entry is not offered, and
    // the notice really did record *why* — "the question could not be asked" is
    // not the same state as "nothing has been asked yet", even though the rail
    // draws both the same way.
    expect(inRail(find.text(l10n.railUpdate)), findsNothing);
    expect(notice.answer?.outcome, UpdateOutcome.unreachable);
    expect(notice.version, isNull);

    await shutdown(tester, [device]);
  });

  testWidgets('sits below every surface, not among them', (tester) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpWindow(tester, device, update: await noticeSaying(newerBuild));

    final entry = inRail(find.text(l10n.railUpdate));
    expect(entry, findsOneWidget);
    // 「最下方」 is the requirement, and it is a claim about position rather
    // than about order in a list: asserted against the first and the last of
    // the surfaces. The entry is pinned rather than listed precisely so that it
    // stays here the day a seventh surface arrives.
    final entryY = tester.getCenter(entry).dy;
    expect(
      entryY,
      greaterThan(tester.getCenter(inRail(find.text(l10n.tabAbout))).dy),
    );
    expect(
      entryY,
      greaterThan(tester.getCenter(inRail(find.text(l10n.tabConversation))).dy),
    );

    await shutdown(tester, [device]);
  });

  testWidgets('names the newer version on the hover', (tester) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpWindow(tester, device, update: await noticeSaying(newerBuild));

    // The rail has room for one word, so the number — which is the whole reason
    // the entry is worth drawing — is what the hover carries. Asserted twice
    // over: that the tooltip holds the right sentence, and that hovering
    // actually puts it on screen. The first without the second would pass while
    // the entry showed nothing a user could see.
    final sentence = l10n.aboutUpdateAvailable('0.1.7');
    expect(find.byTooltip(sentence), findsOneWidget);

    // Hovered over the label rather than over the `Tooltip` widget: the rail
    // may well hold other tooltips the day a destination is drawn without its
    // label, and this one is the entry under test.
    await hoverOver(tester, inRail(find.text(l10n.railUpdate)));

    expect(find.text(sentence), findsOneWidget);

    await shutdown(tester, [device]);
  });

  testWidgets('opens the release it names when pressed', (tester) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    final links = ScriptedLinkOpener.install();
    await pumpWindow(tester, device, update: await noticeSaying(newerBuild));

    await tester.tap(updateEntry(windowA));
    await tester.pump();

    expect(links.opened, [
      'https://github.com/menghun3-cn/zhu-ye-local-im/releases/tag/v0.1.7',
    ]);

    await shutdown(tester, [device]);
  });

  testWidgets('falls back to the download page when the answer names none', (
    tester,
  ) async {
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    final links = ScriptedLinkOpener.install();
    await pumpWindow(
      tester,
      device,
      // A release whose `html_url` was missing. Pressing the entry still has to
      // go somewhere a person can download from, and the place they would have
      // gone by hand is the one the About card falls back to as well.
      update: await noticeSaying(
        const UpdateCheck(UpdateOutcome.available, version: '0.1.7'),
      ),
    );

    await tester.tap(updateEntry(windowA));
    await tester.pump();

    expect(links.opened, [updateReleasesPage]);

    await shutdown(tester, [device]);
  });

  testWidgets('has nowhere to appear in a window with no rail', (tester) async {
    // A narrow window swaps the rail for a bottom bar, and the entry belongs to
    // the rail: 「左侧菜单栏最下方」 has no left menu bar to be at the bottom
    // of. This is a deliberate limit rather than an oversight — the About card
    // is still the way to ask from a narrow window — and it is asserted so that
    // it stays deliberate.
    final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
    await pumpWindow(
      tester,
      device,
      size: narrowWindow,
      update: await noticeSaying(newerBuild),
    );

    expect(windowA.within(find.byType(NavigationRail)), findsNothing);
    expect(find.text(l10n.railUpdate), findsNothing);

    await shutdown(tester, [device]);
  });
}

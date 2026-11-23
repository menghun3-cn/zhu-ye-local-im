import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/share_file.dart';

import '../support/ui_harness.dart';

/// The 分享 line on a settled message's menu, and the one thing it is for.
///
/// Two facts under test: that a message whose bytes are on this machine offers
/// to hand them to another application — the Android share sheet, where WeChat
/// is one of the targets — and that the path it hands over is the file that
/// landed, not a staged copy or a guess. The sharer itself is the seam: the
/// real one opens Android's chooser, which no widget test can drive.
void main() {
  testWidgets(
    'a landed file is shared to another app from its menu, and only where a '
    'share sheet exists',
    (tester) async {
      // The real sharer opens Android's chooser, so the seam stands in for it:
      // what is under test is that the menu appears and the *path* it carries
      // is the file that landed, not that this machine can open a chooser.
      final sharer = ScriptedSharer.install();
      addTearDown(ShareResolution.reset);
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);

      final home = tempDirectory('local-transfer-share-out-');
      final source = File('${home.path}${Platform.pathSeparator}report.bin');
      source.writeAsBytesSync([for (var i = 0; i < 64; i++) i]);
      final inbox = tempDirectory('local-transfer-share-in-');

      await offerFile(tester, alice, source);
      await pumpUntil(
        tester,
        () => bob.offers.isNotEmpty,
        description: 'Bob to be offered the file',
      );
      await tester.runAsync(
        () => bob.controller.acceptInto(bob.offers.single, inbox),
      );
      await pumpUntil(
        tester,
        () => bob.controller.transfers.any((view) => view.localPath != null),
        description: 'the file to land on Bob',
      );
      final landed = bob.controller.transfers.single.localPath;
      expect(landed, isNotNull);

      await pumpWindow(tester, bob);
      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Alice'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Alice');
      await pumpUntil(
        tester,
        () => onConversation(
          windowA,
          find.text('report.bin'),
        ).evaluate().isNotEmpty,
        description: 'the landed file to be a message',
      );

      await rightClick(
        tester,
        onConversation(windowA, find.text('report.bin')),
      );
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.shareFile)).evaluate().isNotEmpty,
        description: 'the context menu to offer sharing the file',
      );
      await tester.tap(windowA.within(find.text(l10n.shareFile)));
      await pumpUntil(
        tester,
        () => sharer.shared.isNotEmpty,
        description: 'the menu line to share the file',
      );
      expect(sharer.shared.single, [landed]);

      // A Device with no share sheet — Windows, where the menu's other lines
      // still apply — does not offer the line at all: an action that could
      // only ever fail is not a choice.
      sharer.supported = false;
      await rightClick(
        tester,
        onConversation(windowA, find.text('report.bin')),
      );
      await pumpUntil(
        tester,
        () => windowA.within(find.text(l10n.openFile)).evaluate().isNotEmpty,
        description: 'the context menu to open again',
      );
      expect(
        windowA.within(find.text(l10n.shareFile)).evaluate(),
        isEmpty,
        reason: 'no share sheet, no line for it',
      );

      await shutdown(tester, [alice, bob]);
    },
  );
}

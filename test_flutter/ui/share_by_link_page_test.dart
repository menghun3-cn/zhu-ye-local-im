import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide TestWindow;
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/core/link_transfer/link_transfer.dart';
import 'package:local_transfer/ui/clipboard_paste.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/pages/share_by_link_page.dart';
import 'package:local_transfer/ui/pickers.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/ui_harness.dart';

/// Opens 传输 → 通过链接分享, the surface these tests are about.
Future<void> openShareByLinkPage(WidgetTester tester) async {
  await openTab(tester, l10n.tabTransfers, window: windowA);
  await tester.tap(windowA.within(find.text(l10n.shareByLinkTitle)));
  await settleRoute(tester);
}

/// Real files for the share to point at — the page checks they exist.
File shareableFile(Directory dir, String name, List<int> bytes) {
  final file = File('${dir.path}${Platform.pathSeparator}$name')
    ..writeAsBytesSync(bytes);
  return file;
}

/// Lets the link server's real socket work finish, then stops it again — the
/// singleton would otherwise hold its port for the rest of the file.
Future<void> stopLinkTransfer(WidgetTester tester) =>
    tester.runAsync(() => LinkTransfer.instance.stop());

void main() {
  group('the Share by link page', () {
    testWidgets('picked files become one share card with a link and a QR', (
      tester,
    ) async {
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      final dir = tempDirectory('share-by-link-pick-');
      final first = shareableFile(dir, 'report.pdf', [1, 2, 3]);
      final second = shareableFile(dir, 'photo.png', [4, 5, 6]);
      picker.willOffer([first.path, second.path]);

      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openShareByLinkPage(tester);

      await tapButton(tester, l10n.shareByLink, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ShareByLinkPage,
          find.text(l10n.shareByLinkFileCount(2)),
        ).evaluate().isNotEmpty,
        description: 'the share card to appear',
      );

      expect(
        onPage(windowA, ShareByLinkPage, find.byType(QrImageView)),
        findsOneWidget,
        reason: 'one share is one QR code',
      );
      final link = tester.widgetList<SelectableText>(
        onPage(windowA, ShareByLinkPage, find.byType(SelectableText)),
      );
      expect(
        link.single.data,
        contains('/s/'),
        reason: 'the card carries the share page URL, not a per-file link',
      );

      await stopLinkTransfer(tester);
      await shutdown(tester, [device]);
    });

    testWidgets('dropping files onto the page creates the same share', (
      tester,
    ) async {
      final dir = tempDirectory('share-by-link-drop-');
      final first = shareableFile(dir, 'notes.txt', [7, 8, 9]);
      final second = shareableFile(dir, 'data.bin', [0, 1]);

      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openShareByLinkPage(tester);

      // The platform's drop arrives as a `DropDoneDetails` on the target's own
      // callback — the OS drag itself is not something a widget test can
      // drive, so the callback is invoked the way the plugin would.
      final target = onPage(windowA, ShareByLinkPage, find.byType(DropTarget));
      expect(target, findsOneWidget);
      tester.widget<DropTarget>(target).onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(first.path), DropItemFile(second.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();

      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ShareByLinkPage,
          find.text(l10n.shareByLinkFileCount(2)),
        ).evaluate().isNotEmpty,
        description: 'the dropped files to become a share card',
      );

      await stopLinkTransfer(tester);
      await shutdown(tester, [device]);
    });

    testWidgets('dropping only a folder says there is nothing to share', (
      tester,
    ) async {
      final dir = tempDirectory('share-by-link-folder-');

      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openShareByLinkPage(tester);

      final target = onPage(windowA, ShareByLinkPage, find.byType(DropTarget));
      tester.widget<DropTarget>(target).onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(dir.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();

      await pumpUntil(
        tester,
        // The toast lives in the window's overlay, outside the page's own
        // subtree — `onPage` would never see it.
        () => windowA
            .within(find.text(l10n.shareByLinkNoFiles))
            .evaluate()
            .isNotEmpty,
        description: 'the nothing-to-share answer',
      );
      expect(
        onPage(
          windowA,
          ShareByLinkPage,
          find.text(l10n.shareByLinkFileCount(1)),
        ),
        findsNothing,
        reason: 'a folder is not a file the share page can serve',
      );

      await stopLinkTransfer(tester);
      await shutdown(tester, [device]);
    });

    testWidgets('tapping the QR code opens it large in a dialog', (
      tester,
    ) async {
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      final dir = tempDirectory('share-by-link-qr-zoom-');
      final file = shareableFile(dir, 'report.pdf', [1]);
      picker.willOffer([file.path]);

      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openShareByLinkPage(tester);

      await tapButton(tester, l10n.shareByLink, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ShareByLinkPage,
          find.byType(QrImageView),
        ).evaluate().isNotEmpty,
        description: 'the share card with its QR code',
      );

      await tester.tap(
        onPage(windowA, ShareByLinkPage, find.byType(QrImageView)),
      );
      await pumpUntil(
        tester,
        () => windowA.within(find.byType(AlertDialog)).evaluate().isNotEmpty,
        description: 'the enlarged QR dialog',
      );

      final dialogQr = tester.widgetList<QrImageView>(
        find.descendant(
          of: windowA.within(find.byType(AlertDialog)),
          matching: find.byType(QrImageView),
        ),
      );
      expect(
        dialogQr.single.size,
        greaterThan(200),
        reason: 'the dialog draws the code big enough to screenshot',
      );

      await stopLinkTransfer(tester);
      await shutdown(tester, [device]);
    });

    testWidgets('copying the QR code puts PNG bytes on the clipboard', (
      tester,
    ) async {
      final clipboard = ScriptedClipboard.install();
      addTearDown(PasteResolution.reset);
      final picker = ScriptedPicker.install();
      addTearDown(PickerResolution.reset);
      final dir = tempDirectory('share-by-link-qr-');
      final file = shareableFile(dir, 'report.pdf', [1]);
      picker.willOffer([file.path]);

      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openShareByLinkPage(tester);

      await tapButton(tester, l10n.shareByLink, window: windowA);
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ShareByLinkPage,
          find.byType(QrImageView),
        ).evaluate().isNotEmpty,
        description: 'the share card with its QR code',
      );

      await tester.tap(
        onPage(
          windowA,
          ShareByLinkPage,
          find.byTooltip(l10n.shareByLinkCopyQr),
        ),
      );
      await pumpUntil(
        tester,
        () => clipboard.copiedImages.isNotEmpty,
        description: 'the QR image to reach the clipboard',
      );

      final png = clipboard.copiedImages.single;
      expect(
        png,
        // The PNG magic number: what lands on the clipboard has to be a
        // picture a chat client can paste, not the link's text.
        predicate<Uint8List>(
          (bytes) =>
              bytes.length > 8 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4E &&
              bytes[3] == 0x47,
        ),
      );

      await stopLinkTransfer(tester);
      await shutdown(tester, [device]);
    });

    testWidgets('a share survives backing out, and deleting revokes it', (
      tester,
    ) async {
      final dir = tempDirectory('share-by-link-persist-');
      final file = shareableFile(dir, 'notes.txt', [1, 2]);

      final device = await startUiDevice(tester, MemoryBeaconHub().a, 'Alice');
      await pumpWindow(tester, device);
      await openShareByLinkPage(tester);

      final target = onPage(windowA, ShareByLinkPage, find.byType(DropTarget));
      tester.widget<DropTarget>(target).onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(file.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ShareByLinkPage,
          find.text(l10n.shareByLinkFileCount(1)),
        ).evaluate().isNotEmpty,
        description: 'the share card to appear',
      );

      // Back out to the transfer list and return: the card must still be
      // there — the server holds the share, not the page's state.
      await tester.tap(windowA.within(find.byIcon(Icons.arrow_back)));
      await pumpUntil(
        tester,
        () => windowA
            .within(find.text(l10n.shareByLinkTitle))
            .evaluate()
            .isNotEmpty,
        description: 'the transfers list with its share entry',
      );
      await tester.tap(windowA.within(find.text(l10n.shareByLinkTitle)));
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ShareByLinkPage,
          find.text(l10n.shareByLinkFileCount(1)),
        ).evaluate().isNotEmpty,
        description: 'the same share card after returning',
      );

      // Deleting the card revokes the share on the server — the link stops
      // working now, not whenever the 30 minutes would have run out.
      await tester.tap(
        onPage(windowA, ShareByLinkPage, find.byTooltip(l10n.deleteMessage)),
      );
      await pumpUntil(
        tester,
        () => onPage(
          windowA,
          ShareByLinkPage,
          find.byType(QrImageView),
        ).evaluate().isEmpty,
        description: 'the card to be gone',
      );
      expect(LinkTransfer.instance.shares, isEmpty);

      await stopLinkTransfer(tester);
      await shutdown(tester, [device]);
    });

    testWidgets('a covered conversation takes no drop meant for this page', (
      tester,
    ) async {
      final hub = MemoryBeaconHub();
      final alice = await startUiDevice(tester, hub.a, 'Alice');
      final bob = await startUiDevice(tester, hub.b, 'Bob');
      await pairDevices(tester, alice, bob);
      await connectDevices(tester, alice, bob);
      await pumpWindow(tester, alice);

      await openTab(tester, l10n.tabConversation, window: windowA);
      await pumpUntil(
        tester,
        () => conversationListed(windowA, 'Bob'),
        description: 'the conversation to be listed',
      );
      await openConversation(tester, windowA, name: 'Bob');
      await openShareByLinkPage(tester);

      // `desktop_drop`'s target is global and coordinate-based: it cannot
      // tell that the conversation is covered, so `enable` is the only thing
      // keeping a drop on this page out of the hidden composer. The covered
      // page is still mounted — the shell's `IndexedStack` keeps every tab —
      // but `find` skips it by default, so the lookups go in with
      // `skipOffstage: false`.
      final coveredConversation = find.descendant(
        of: find.byType(ConversationView, skipOffstage: false),
        matching: find.byType(DropTarget, skipOffstage: false),
        skipOffstage: false,
      );
      final sharePage = find.descendant(
        of: find.byType(ShareByLinkPage, skipOffstage: false),
        matching: find.byType(DropTarget, skipOffstage: false),
        skipOffstage: false,
      );

      expect(coveredConversation, findsOneWidget);
      expect(
        tester.widget<DropTarget>(coveredConversation).enable,
        isFalse,
        reason: 'the conversation is covered by the share page',
      );
      expect(tester.widget<DropTarget>(sharePage).enable, isTrue);

      // The leak runs both ways: the share page stays mounted under the
      // conversations tab once it has been opened, and must not take a drop
      // meant for the conversation either.
      await openTab(tester, l10n.tabConversation, window: windowA);
      expect(
        tester.widget<DropTarget>(sharePage).enable,
        isFalse,
        reason: 'the share page is covered by the conversations tab',
      );
      expect(
        tester.widget<DropTarget>(coveredConversation).enable,
        isTrue,
        reason: 'the conversation is on top again',
      );

      await shutdown(tester, [alice, bob]);
    });
  });
}

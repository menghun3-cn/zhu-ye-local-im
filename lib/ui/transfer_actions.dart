import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'clipboard_paste.dart';
import 'dialogs.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';
import 'reveal.dart';

/// What can be done with a Transfer, in one place.
///
/// Written once here rather than once per surface that draws a Transfer,
/// because every surface that shows one shows the same actions. An offer is
/// answered from wherever the user is looking at it — the Transfers surface
/// lists every Transfer, and a peer's conversation shows the ones between the
/// two of them — so the folder question and the refusal live here; and what a
/// *settled* Transfer offers — showing its file in its folder, and putting a
/// picture back on the clipboard — lives here beside them for the same reason.

/// Asks where [view]'s offer should land, then takes it.
///
/// [defaultDirectory] is where the platform puts received files when the user
/// has not said otherwise; the folder is asked for rather than assumed, because
/// a Device that only ever wrote to one folder would be a Device that cannot
/// file anything.
Future<void> acceptOffer(
  BuildContext context,
  LocalTransferController controller,
  TransferView view, {
  String? defaultDirectory,
}) async {
  final offer = view.offer;
  if (offer == null) return;
  final l10n = AppLocalizations.of(context);
  final path = await askForDirectory(
    context,
    title: view.kind == PayloadKind.file
        ? l10n.whereShouldFilesLand
        : l10n.whereShouldThisArrive,
    initial: defaultDirectory,
  );
  if (path == null) return;
  // The dialog is gone by now, and so may be the surface behind it.
  if (!context.mounted) return;
  await guarded(context, () async {
    final directory = Directory(path);
    // A folder the user typed may not exist yet; creating it here rather than
    // failing the Transfer is what makes the field usable.
    directory.createSync(recursive: true);
    await controller.acceptInto(offer, directory);
  });
}

/// Declines [view]'s offer.
void rejectOffer(
  BuildContext context,
  LocalTransferController controller,
  TransferView view,
) {
  final offer = view.offer;
  if (offer == null) return;
  unawaited(guarded(context, () => controller.reject(offer)));
}

/// Whether [view] is a send this Device is still making and can still stop.
///
/// True from the moment an Offer goes out — waiting for an answer counts, which
/// is the whole point: a file picked by mistake should be stoppable during the
/// seconds the peer leaves the question on screen, not only once bytes move.
/// The controller hands the live send out on [TransferView.send] precisely
/// while a stop would change something.
bool canCancelTransfer(TransferView view) => view.send != null;

/// Abandons [view]'s send and tells the peer why.
///
/// Telling the peer is not a courtesy — it is what un-sticks the other side.
/// A receiver whose sender vanished would otherwise sit on a bubble that fills
/// in forever, because a receiver keeps no clock of its own. The send itself
/// goes out through the same quiet road every ending takes: a Transfer is over
/// either way, so a link that died before the news arrived is not a second
/// error for the user to read.
Future<void> cancelSend(BuildContext context, TransferView view) {
  final send = view.send;
  if (send == null) return Future.value();
  return guarded(context, send.cancel);
}

/// Whether [view] names a file on this machine whose folder can be opened.
///
/// True for a file this Device received, for one it sent, and for an image
/// either way — every case in which "where is it" has an answer. False while a
/// file offer is still waiting, because nothing has been written anywhere yet,
/// and false for text, which is not a file at all.
bool canRevealTransfer(TransferView view) => view.localPath != null;

/// Shows [view]'s file in this machine's file manager.
///
/// A failure is said out loud rather than raised: a platform with no file
/// manager, and a path whose file has since been moved or deleted, are both
/// ordinary — neither is an error the user needs an exception for, and the
/// sentence is easier to act on than a stack trace.
Future<void> revealTransfer(BuildContext context, TransferView view) async {
  final path = view.localPath;
  if (path == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  // The one call goes through the seam, so a widget test can assert the folder
  // it was asked for without an Explorer window opening on the test machine.
  if (await RevealResolution.revealer.reveal(path)) return;
  messenger.showSnackBar(SnackBar(content: Text(l10n.cannotOpenFolder)));
}

/// Whether [view] is a picture whose bytes are on this machine and can
/// therefore be put on the clipboard.
///
/// An image and not a file, because "copy" means two different things to the
/// two of them: a picture copied in Explorer is a picture, and a spreadsheet
/// copied here would be a file list. False for an image still in flight — there
/// is nothing to read yet — and false for a picture whose local copy has since
/// been deleted, which is discovered on the read rather than guessed at here.
bool canCopyImage(TransferView view) =>
    view.kind == PayloadKind.image && view.localPath != null;

/// Puts [view]'s picture on this machine's clipboard.
///
/// The bytes are read back from disk rather than carried in memory: a
/// conversation holds however many pictures the user has exchanged, and the one
/// being copied is the one the user pointed at, which is exactly the one the
/// app does not have to keep decoded.
///
/// A failure is said out loud, for the same reason a failed reveal is: the
/// platforms disagree about whether an app may write its own clipboard at all,
/// and "nothing happened" is not something a user can act on. A success says
/// nothing — the pasted picture is the confirmation.
Future<void> copyTransferImage(BuildContext context, TransferView view) async {
  final path = view.localPath;
  if (path == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } on Object {
    // The file the Transfer points at is not there any more. That is a copy
    // that cannot happen rather than one that failed halfway.
    messenger.showSnackBar(SnackBar(content: Text(l10n.cannotCopyImage)));
    return;
  }
  // Through the seam, so a widget test can assert the bytes that reached the
  // clipboard without a `testWidgets` body ever touching a platform channel.
  if (await PasteResolution.paste.writeImage(bytes)) return;
  messenger.showSnackBar(SnackBar(content: Text(l10n.cannotCopyImage)));
}

/// Offers what can be done with a Transfer once it has settled, on a
/// right-click.
///
/// The answers an *offer* needs — accept and refuse — are buttons in the open,
/// because a decision behind a menu is a decision nobody finds. These are the
/// other kind of action: things the user wants after a Transfer has settled,
/// when the question is over and the bytes are somewhere on disk. A right-click
/// keeps them reachable without putting a toolbar on a message.
///
/// Which actions a given Transfer offers is decided by the predicates above
/// rather than by the caller, so the conversation, the Transfers list and any
/// surface added later cannot each draw a different menu for the same message.
///
/// [child] is wrapped rather than replaced — the picture and the card are what
/// is being pointed at, and they have to go on drawing exactly as they did.
class TransferContextMenu extends StatelessWidget {
  /// Wraps [child] with the actions [view] offers.
  const TransferContextMenu({
    super.key,
    required this.view,
    required this.child,
  });

  /// The Transfer being pointed at.
  final TransferView view;

  /// What is drawn, and what the pointer has to be over.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Nothing to offer means nothing to intercept: a handler that opened an
    // empty menu would swallow the right-click that selects a name to copy.
    if (!canRevealTransfer(view) &&
        !canCopyImage(view) &&
        !canCancelTransfer(view)) {
      return child;
    }
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_open(context, details.globalPosition)),
      child: child,
    );
  }

  /// Opens the menu where the pointer was.
  Future<void> _open(BuildContext context, Offset at) async {
    final l10n = AppLocalizations.of(context);
    // Read once, before the await: the surface behind the menu can be gone by
    // the time one of these is chosen, and the list must not change under the
    // menu the user is looking at either.
    final reveal = canRevealTransfer(view);
    final copy = canCopyImage(view);
    final cancel = canCancelTransfer(view);
    // The overlay is what `showMenu` lays the menu out inside, so its size is
    // the one the margins below have to be measured against.
    final overlay = Overlay.of(context).context.findRenderObject();
    final size = overlay is RenderBox
        ? overlay.size
        : MediaQuery.sizeOf(context);
    final chosen = await showMenu<String>(
      context: context,
      // Anchored at the pointer, with what is left of the overlay given as the
      // right and bottom margins — which is how the menu is kept inside the
      // window rather than half off its edge.
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        size.width - at.dx,
        size.height - at.dy,
      ),
      items: [
        if (cancel)
          _item(
            value: _cancelAction,
            icon: Icons.close,
            label: l10n.cancelSend,
          ),
        if (reveal)
          _item(
            value: _revealAction,
            icon: Icons.folder_open_outlined,
            label: l10n.openContainingFolder,
          ),
        if (copy)
          _item(
            value: _copyAction,
            icon: Icons.content_copy_outlined,
            label: l10n.copyImage,
          ),
      ],
    );
    if (!context.mounted) return;
    switch (chosen) {
      case _cancelAction:
        await cancelSend(context, view);
      case _revealAction:
        await revealTransfer(context, view);
      case _copyAction:
        await copyTransferImage(context, view);
    }
  }

  /// One line of the menu.
  ///
  /// A row rather than a `ListTile`: a menu item is one line, and a tile brings
  /// its own padding, its own tap target and its own ripple.
  PopupMenuItem<String> _item({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

/// Showing the file where it lives, and putting a picture on the clipboard.
///
/// Three values rather than two because `showMenu` answers with what was
/// chosen, and `null` is what a dismissed menu answers with as well.
const String _cancelAction = 'cancel';
const String _revealAction = 'reveal';
const String _copyAction = 'copy';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
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
/// two of them — so the folder question and the refusal live here; and a file
/// that has already landed can be shown in its folder from either place too, so
/// that action lives here beside them.

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

/// Offers what can be done with a file once it has landed, on a right-click.
///
/// The answers an *offer* needs — accept and refuse — are buttons in the open,
/// because a decision behind a menu is a decision nobody finds. This is the
/// other kind of action: something the user wants after a Transfer has settled,
/// when the question is over and the file is somewhere on disk. A right-click
/// keeps it reachable without putting a toolbar on a message.
///
/// [child] is wrapped rather than replaced — the bubble and the card are what is
/// being pointed at, and they have to go on drawing exactly as they did.
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
    if (!canRevealTransfer(view)) return child;
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_open(context, details.globalPosition)),
      child: child,
    );
  }

  /// Opens the menu where the pointer was.
  Future<void> _open(BuildContext context, Offset at) async {
    final l10n = AppLocalizations.of(context);
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
        PopupMenuItem<String>(
          value: _revealAction,
          // A row rather than a `ListTile`: a menu item is one line, and a tile
          // brings its own padding, its own tap target and its own ripple.
          child: Row(
            children: [
              const Icon(Icons.folder_open_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.openContainingFolder),
            ],
          ),
        ),
      ],
    );
    if (chosen != _revealAction || !context.mounted) return;
    await revealTransfer(context, view);
  }
}

/// The one value the context menu can come back with.
const String _revealAction = 'reveal';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'dialogs.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';

/// The two answers an offer can be given, in one place.
///
/// An offer is answered from wherever the user is looking at it — the Transfers
/// surface lists every Transfer, and a peer's conversation shows the ones
/// between the two of them — so the folder question and the refusal are written
/// once here rather than once per surface that draws an offer.

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

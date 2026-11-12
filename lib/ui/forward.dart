import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'labels.dart';
import 'l10n/generated/app_localizations.dart';
import 'top_toast.dart';

/// Forwards [views] to the Device the user picks, one Transfer per message.
///
/// This is the one road every forward takes — the menu's 转发 on a single
/// message and the selection bar's 转发 on a batch — so the pick, the order
/// and the failure count are decided once here rather than per surface.
///
/// Only [TransferView.canForward] messages are sent: the caller may hand over
/// a selection that includes a multi-item transfer or a draft, and those are
/// filtered out rather than failing one by one. [views] is expected in the
/// order the messages should arrive; the caller sorts, this does not.
///
/// Returns whether a target was picked and the send was attempted, so a
/// caller holding a selection mode can tell "the user backed out" from "the
/// forwards went out" and keep the ticks in the first case.
Future<bool> forwardToPickedDevice(
  BuildContext context,
  LocalTransferController controller,
  List<TransferView> views,
) async {
  final sendable = [
    for (final view in views)
      if (view.canForward) view,
  ];
  if (sendable.isEmpty) return false;
  // Taken before the dialog's await, for the same reason `guarded` takes its
  // strings early: the surface that asked may be gone by the time the pick
  // comes back, and the toast still has somewhere to be drawn.
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final target = await showDialog<Fingerprint>(
    context: context,
    builder: (dialogContext) => _ForwardTargetDialog(controller: controller),
  );
  // No pick is a backed-out dialog, not a failure: nothing was sent and
  // nothing is owed, so the caller's selection stays exactly as it was.
  if (target == null) return false;

  final failed = await controller.forwardMessages(sendable, to: target);
  // The toast is the whole report a partial batch gets: every message that
  // could not go — a file moved since it arrived, a kind with nothing left
  // to send — is counted rather than named, because the ones that did go are
  // already visible as new messages in the target's conversation.
  if (failed > 0 && overlay != null) {
    await TopToast.showIn(overlay, l10n.forwardFailedCount(failed));
  }
  return true;
}

/// The Devices a forward can go to, as a dialog answers with one Fingerprint.
///
/// Every peer is listed, offline ones included: a forward to a Device that is
/// away is kept as an unsent draft owed to it — the same thing a message
/// typed while it was offline becomes — so "not connected right now" is not
/// a reason to leave it out. Connected first and then by name, the order the
/// conversation list already teaches.
class _ForwardTargetDialog extends StatelessWidget {
  const _ForwardTargetDialog({required this.controller});

  final LocalTransferController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final peers = [...controller.peers]
      ..sort((a, b) {
        if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
        return a.displayName.compareTo(b.displayName);
      });
    return AlertDialog(
      title: Text(l10n.forwardTo),
      content: SizedBox(
        width: 340,
        child: peers.isEmpty
            ? Text(l10n.noDevicesToForward)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final peer in peers)
                    ListTile(
                      dense: true,
                      leading: Icon(iconForPlatform(peer.platform)),
                      title: Text(peer.displayName),
                      subtitle: Text(describePeerConnection(peer, l10n)),
                      onTap: () => Navigator.of(context).pop(peer.fingerprint),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'controller_scope.dart';
import 'l10n/generated/app_localizations.dart';

/// The three-dot menu shared by the compact conversation header and the
/// full-window conversation route.
///
/// Trust is offered only while the peer is still known. Clearing is always
/// offered: it is a fact about this Device's own history, and it does not need
/// the other Device to be on the network.
class ConversationMenuButton extends StatelessWidget {
  const ConversationMenuButton({
    super.key,
    required this.peer,
    this.color,
    this.iconSize = 24,
  });

  final Fingerprint peer;
  final Color? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final controller = ControllerScope.of(context);
    final known = _peerOf(controller);
    return PopupMenuButton<_ConversationAction>(
      icon: Icon(Icons.more_horiz, size: iconSize, color: color),
      onSelected: (action) => _choose(context, controller, known, action),
      itemBuilder: (context) {
        final l10n = AppLocalizations.of(context);
        return [
          if (known != null)
            PopupMenuItem(
              value: _ConversationAction.toggleFavorite,
              child: Text(
                known.isFavorite ? l10n.stopTrustingDevice : l10n.trustDevice,
              ),
            ),
          PopupMenuItem(
            value: _ConversationAction.clearConversation,
            child: Text(l10n.clearConversation),
          ),
        ];
      },
    );
  }

  PeerView? _peerOf(LocalTransferController controller) {
    for (final candidate in controller.peers) {
      if (candidate.fingerprint == peer) return candidate;
    }
    return null;
  }

  Future<void> _choose(
    BuildContext context,
    LocalTransferController controller,
    PeerView? known,
    _ConversationAction action,
  ) async {
    switch (action) {
      case _ConversationAction.toggleFavorite:
        if (known != null) {
          controller.setFavorite(peer, value: !known.isFavorite);
        }
        return;
      case _ConversationAction.clearConversation:
        final l10n = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.clearConversationConfirmTitle),
            content: Text(l10n.clearConversationConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.clearConversationConfirmAction),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await controller.clearConversation(peer);
        }
        return;
    }
  }
}

enum _ConversationAction { toggleFavorite, clearConversation }

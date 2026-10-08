import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../conversation_view.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';

/// One Device's conversation, on a screen of its own.
///
/// This is the pushed route a user reaches from the Devices surface, and it is
/// now only a frame: the history, the composer and the messages all live in
/// [ConversationView], which the Conversations surface draws too. What this
/// page adds is the [AppBar] — the peer's name, its address, and the trust
/// menu — and there is nothing else it needs to add.
///
/// The Conversations surface is where a user is meant to end up; this remains
/// because "open the conversation with *that* Device" is still a thing to do
/// from a Device card, and because a conversation that fills the window is
/// easier to read than one in a pane.
class ConversationPage extends StatelessWidget {
  /// Opens the conversation with [peer].
  const ConversationPage({
    super.key,
    required this.peer,
    this.defaultIncomingDirectory,
  });

  /// The Device this conversation is with.
  final Fingerprint peer;

  /// Where a file received here lands when the user has not said otherwise.
  final String? defaultIncomingDirectory;

  /// What is known about this peer right now, or null once it is unknown.
  PeerView? _peerOf(LocalTransferController controller) {
    for (final peer in controller.peers) {
      if (peer.fingerprint == this.peer) return peer;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ControllerScope.of(context);
    final known = _peerOf(controller);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              known?.displayName ?? peer.short(),
              overflow: TextOverflow.ellipsis,
            ),
            // The address stays on screen for the whole conversation: it is
            // the answer to "which machine am I actually talking to", and it
            // is the piece of information a user needs when they walk over to
            // the other one.
            Text(
              known == null ? l10n.neverSeen : describePeerAddress(known, l10n),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (known != null)
            PopupMenuButton<bool>(
              onSelected: (value) => controller.setFavorite(peer, value: value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: !known.isFavorite,
                  child: Text(
                    known.isFavorite
                        ? l10n.stopTrustingDevice
                        : l10n.trustDevice,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ConversationView(
        peer: peer,
        defaultIncomingDirectory: defaultIncomingDirectory,
      ),
    );
  }
}

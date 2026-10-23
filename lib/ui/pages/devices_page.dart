import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../dialogs.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../wechat/theme.dart';
import '../widgets.dart';
import 'conversation_page.dart';

/// Who this Device is, who is around, and how to reach them.
class DevicesPage extends StatelessWidget {
  /// Builds the Devices surface.
  const DevicesPage({
    super.key,
    this.defaultIncomingDirectory,
    this.onConversationRequested,
  });

  /// Where a file received from a conversation lands by default.
  final String? defaultIncomingDirectory;

  /// Called when the user asks for a conversation with [Fingerprint]'s Device.
  ///
  /// The shell passes one that brings the Conversations surface to the front,
  /// which is the point of the parameter: connecting from here used to leave
  /// the user on this page, having to find the conversation themselves. This
  /// page does not know the shell exists, so it asks rather than switches.
  ///
  /// Null in a test that only cares about this surface; the card then falls
  /// back to pushing the conversation as a route of its own.
  final void Function(Fingerprint peer)? onConversationRequested;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final peers = controller.peers;
    return ListView(
      padding: WeChat.pagePadding,
      children: [
        _SelfCard(controller: controller),
        const SizedBox(height: WeChat.cardGap),
        _AutomaticConnectionCard(controller: controller),
        const SizedBox(height: WeChat.sectionGap),
        SectionHeader(
          title: l10n.tabDevices,
          trailing: TextButton.icon(
            onPressed: () => showManualAddressDialog(context, controller),
            icon: const Icon(Icons.cable, size: 18),
            label: Text(l10n.byAddress),
          ),
        ),
        if (peers.isEmpty)
          HintText(l10n.devicesEmptyHint)
        else
          for (final peer in peers)
            _PeerCard(
              peer: peer,
              defaultIncomingDirectory: defaultIncomingDirectory,
              onConversationRequested: onConversationRequested,
            ),
      ],
    );
  }
}

/// What this Device says about itself.
class _SelfCard extends StatelessWidget {
  const _SelfCard({required this.controller});

  final LocalTransferController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final self = controller.self;
    final port = controller.listenPort;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WeChat.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconForPlatform(self.platform), size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(self.alias, style: theme.textTheme.titleMedium),
                      SelectableText(
                        self.shortFingerprint,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => showRenameDialog(context, controller),
                  child: Text(l10n.rename),
                ),
              ],
            ),
            const Divider(height: 24),
            FactLine(l10n.factPlatform, self.platform.displayName),
            FactLine(
              l10n.tabClipboard,
              describeClipboardFacts(self.capability, l10n),
            ),
            FactLine(l10n.factOwnerGroup, l10n.groupDevices(self.groupLength)),
            FactLine(l10n.factSessions, l10n.sessionsOpen(self.openSessions)),
            FactLine(
              l10n.factListening,
              // Discovery and the trust exchange do not need a group secret;
              // accepting Sessions does. Say which of those is missing rather
              // than leaving an unpaired Device looking broken.
              port != null
                  ? l10n.onPort(port)
                  : controller.isPaired
                  ? l10n.connectionNotReady
                  : l10n.sessionsAutoConnectPending,
            ),
          ],
        ),
      ),
    );
  }
}

/// How this Device accepts connections made through Discovery.
///
/// There is no switch: answering is part of being reachable. The card states
/// the automatic flow and whether the listener actually started, because a
/// port already held by another process is a degraded state rather than a
/// preference the user chose.
class _AutomaticConnectionCard extends StatelessWidget {
  const _AutomaticConnectionCard({required this.controller});

  final LocalTransferController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final listening = controller.isAutomaticConnectionsReady;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WeChat.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(listening ? Icons.sync : Icons.sync_problem),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.automaticConnectionsTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.automaticConnectionsBody),
            const SizedBox(height: 12),
            Text(
              listening
                  ? l10n.automaticConnectionsReady
                  : l10n.automaticConnectionsUnavailable,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// One Device in the list, and whether it is reachable.
///
/// This surface answers "what is on the network" — the address, the group, how
/// long since it was heard from — and nothing else. Connecting is not done
/// here: a Session is the beginning of a conversation, so the button that opens
/// one lives in the conversation list, beside the conversation it is going to
/// start. What is left on the card is the peer's own facts and, for a Device
/// that is already connected, a way across to the talking.
class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.peer,
    required this.defaultIncomingDirectory,
    this.onConversationRequested,
  });

  final PeerView peer;
  final String? defaultIncomingDirectory;
  final void Function(Fingerprint peer)? onConversationRequested;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final conversation = peer.isConnected
        ? () => _openConversation(context)
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: conversation,
        leading: CircleAvatar(child: Icon(iconForPlatform(peer.platform))),
        title: Text(peer.displayName),
        subtitle: Text(
          '${peer.shortFingerprint} · ${describePeerFacts(peer, l10n)}',
        ),
        isThreeLine: true,
        // A peer with no Session has no action here, so the row says only what
        // it is. The conversation list is where it can be connected from, and
        // repeating the button in two places would be two places to change when
        // what "connect" means changes.
        trailing: conversation == null
            ? null
            : FilledButton.tonalIcon(
                onPressed: conversation,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: Text(l10n.openConversation),
              ),
      ),
    );
  }

  /// Shows the conversation, either in the shell or as a route of its own.
  ///
  /// The shell is asked first, because a conversation belongs in the
  /// Conversations surface beside the others; the pushed route is what is left
  /// when there is no shell to ask — a test that pumps this page alone, or any
  /// caller that has a reason to want a page rather than a pane.
  void _openConversation(BuildContext context) {
    final request = onConversationRequested;
    if (request != null) {
      request(peer.fingerprint);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationPage(
            peer: peer.fingerprint,
            defaultIncomingDirectory: defaultIncomingDirectory,
          ),
        ),
      ),
    );
  }
}

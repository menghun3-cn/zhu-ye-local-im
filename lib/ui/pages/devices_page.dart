import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../controller_scope.dart';
import '../dialogs.dart';
import '../feedback.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../widgets.dart';
import 'conversation_page.dart';

/// Who this Device is, who is around, and how to reach them.
class DevicesPage extends StatelessWidget {
  /// Builds the Devices surface.
  const DevicesPage({super.key, this.defaultIncomingDirectory});

  /// Where a file received from a conversation lands by default.
  final String? defaultIncomingDirectory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final peers = controller.peers;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SelfCard(controller: controller),
        const SizedBox(height: 12),
        _PairingCard(controller: controller),
        const SizedBox(height: 20),
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
              controller: controller,
              defaultIncomingDirectory: defaultIncomingDirectory,
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
        padding: const EdgeInsets.all(16),
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
              // The port is the honest answer to "can anything reach me": an
              // unpaired Device binds none, and says so.
              port == null ? l10n.notAcceptingSessions : l10n.onPort(port),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pairing, whichever side of it this Device is on.
class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.controller});

  final LocalTransferController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final paired = controller.isPaired;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(paired ? Icons.link : Icons.link_off),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    paired
                        ? l10n.pairingCardPairedTitle
                        : l10n.pairingCardUnpairedTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              paired
                  ? l10n.pairingCardPairedBody
                  : l10n.pairingCardUnpairedBody,
            ),
            const SizedBox(height: 12),
            // A switch rather than a button: this Device answers requests for as
            // long as it is on, so it is a standing state rather than a step the
            // user takes. The subtitle reports the listener rather than the
            // preference, because the two can disagree — a port already taken by
            // a second copy of the app is the case — and the switch promising
            // something that is not happening would be the lie.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.acceptsPairingRequests,
              onChanged: (value) => guarded(
                context,
                () => controller.setAcceptsPairingRequests(value),
              ),
              title: Text(l10n.acceptPairingRequests),
              subtitle: Text(
                controller.isAcceptingPairings
                    ? l10n.pairingListening
                    : l10n.pairingNotListening,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One Device in the list, with what can be done with it.
///
/// A Device this one holds a Session with is a Device to talk to, so the whole
/// card opens the conversation and the column beside the name says so. The
/// other two states are single actions — Pair, or open a Session — and stay as
/// the button they always were.
class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.peer,
    required this.controller,
    required this.defaultIncomingDirectory,
  });

  final PeerView peer;
  final LocalTransferController controller;
  final String? defaultIncomingDirectory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Dialling needs both an address to dial and a peer in the group: a Device
    // from somebody else's group would fail the handshake, so offering the
    // button would be offering a failure. Pairing needs only an address — the
    // whole point of it is to bring a Device that is not in the group in.
    final canConnect = peer.isDiallable && peer.isInGroup;
    final canPair = !peer.isInGroup && peer.address != null;
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
        trailing: peer.isConnected
            ? FilledButton.tonalIcon(
                onPressed: conversation,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: Text(l10n.openConversation),
              )
            : Tooltip(
                message: canConnect
                    ? l10n.openSession
                    : canPair
                    ? l10n.pairWithThisDevice
                    : peer.isInGroup
                    ? l10n.nothingToDialYet
                    : l10n.nothingKnownAboutPeer,
                child: TextButton(
                  onPressed: canConnect
                      ? () => guarded(
                          context,
                          () => controller.connect(peer.fingerprint),
                        )
                      : canPair
                      ? () => showPairWithPeerDialog(context, controller, peer)
                      : null,
                  child: Text(
                    canPair && !canConnect ? l10n.pair : l10n.connect,
                  ),
                ),
              ),
      ),
    );
  }

  void _openConversation(BuildContext context) {
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

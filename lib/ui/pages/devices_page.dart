import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../controller_scope.dart';
import '../dialogs.dart';
import '../feedback.dart';
import '../labels.dart';
import '../widgets.dart';

/// Who this Device is, who is around, and how to reach them.
class DevicesPage extends StatelessWidget {
  /// Builds the Devices surface.
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
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
          title: 'Devices',
          trailing: TextButton.icon(
            onPressed: () => showManualAddressDialog(context, controller),
            icon: const Icon(Icons.cable, size: 18),
            label: const Text('By address'),
          ),
        ),
        if (peers.isEmpty)
          const HintText(
            'Nothing has been discovered yet. Devices running this app on the '
            'same network appear here; one Discovery cannot reach can still be '
            'dialled by address.',
          )
        else
          for (final peer in peers)
            _PeerCard(peer: peer, controller: controller),
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
                  child: const Text('Rename'),
                ),
              ],
            ),
            const Divider(height: 24),
            FactLine('Platform', self.platform.displayName),
            FactLine(
              'Clipboard',
              'can originate: ${self.capability.canOriginate ? 'yes' : 'no'} · '
                  'can apply: ${self.capability.canApply ? 'yes' : 'no'}',
            ),
            FactLine('Owner Group', '${self.groupLength} Device(s)'),
            FactLine('Sessions', '${self.openSessions} open'),
            FactLine(
              'Listening',
              // The port is the honest answer to "can anything reach me": an
              // unpaired Device binds none, and says so.
              port == null ? 'not accepting Sessions' : 'on port $port',
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
                        ? 'Pair another Device'
                        : 'Pair this Device to send anything',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              paired
                  ? 'Devices in one Owner Group can open Sessions with each '
                        'other. Pairing adds one, and is also what lets a '
                        'clipboard be shared.'
                  : 'A Device with no Owner Group has no secret to prove '
                        'itself with, so it accepts no Sessions and can reach '
                        'nobody. Pairing is what changes that — it is not a '
                        'setting on top of something that already works.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => showInvitationDialog(context, controller),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Show a code'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showJoinDialog(context, controller),
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Enter a code'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _PeerAction { sendText, sendFile, favorite }

/// One Device in the list, with what can be done with it.
class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, required this.controller});

  final PeerView peer;
  final LocalTransferController controller;

  @override
  Widget build(BuildContext context) {
    // Dialling needs both an address to dial and a peer in the group: a Device
    // from somebody else's group would fail the handshake, so offering the
    // button would be offering a failure.
    final canConnect = peer.isDiallable && peer.isInGroup;
    final facts = <String>[
      if (peer.alias == null) 'name not announced yet',
      describePeerAddress(peer),
      if (peer.isConnected)
        'Session open'
      else
        'last seen ${describeLastSeen(peer.lastSeen)}',
      if (!peer.isInGroup) 'not in this Owner Group',
      if (peer.isFavorite) 'trusted',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Icon(iconForPlatform(peer.platform))),
        title: Text(peer.displayName),
        subtitle: Text('${peer.shortFingerprint} · ${facts.join(' · ')}'),
        isThreeLine: true,
        trailing: peer.isConnected
            ? PopupMenuButton<_PeerAction>(
                tooltip: 'Send',
                onSelected: (action) => _act(context, action),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _PeerAction.sendText,
                    child: Text('Send text'),
                  ),
                  const PopupMenuItem(
                    value: _PeerAction.sendFile,
                    child: Text('Send a file'),
                  ),
                  PopupMenuItem(
                    value: _PeerAction.favorite,
                    child: Text(
                      peer.isFavorite
                          ? 'Stop trusting this Device'
                          : 'Trust this Device',
                    ),
                  ),
                ],
              )
            : Tooltip(
                message: canConnect
                    ? 'Open a Session'
                    : peer.isInGroup
                    ? 'Nothing to dial yet: this Device has not been seen'
                    : 'This Device is not in your Owner Group',
                child: TextButton(
                  onPressed: canConnect
                      ? () => guarded(
                          context,
                          () => controller.connect(peer.fingerprint),
                        )
                      : null,
                  child: const Text('Connect'),
                ),
              ),
      ),
    );
  }

  void _act(BuildContext context, _PeerAction action) {
    switch (action) {
      case _PeerAction.sendText:
        unawaited(showSendTextDialog(context, controller, peer));
      case _PeerAction.sendFile:
        unawaited(showSendFileDialog(context, controller, peer));
      case _PeerAction.favorite:
        controller.setFavorite(peer.fingerprint, value: !peer.isFavorite);
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../dialogs.dart';
import '../feedback.dart';
import '../labels.dart';
import '../widgets.dart';

/// Everything this Device has sent or been offered, newest first.
class TransfersPage extends StatelessWidget {
  /// Builds the Transfers surface, offering [defaultIncomingDirectory] as the
  /// folder a received file lands in.
  const TransfersPage({super.key, required this.defaultIncomingDirectory});

  /// Where a Transfer goes when the user has not said otherwise.
  final String? defaultIncomingDirectory;

  @override
  Widget build(BuildContext context) {
    final controller = ControllerScope.of(context);
    final transfers = controller.transfers;
    if (transfers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: HintText('Nothing has been sent or received yet.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transfers.length,
      itemBuilder: (context, index) {
        final view = transfers[index];
        return _TransferCard(
          view: view,
          controller: controller,
          peerName: _nameOf(controller, view.peer),
          defaultIncomingDirectory: defaultIncomingDirectory,
        );
      },
    );
  }
}

/// What to call the Device on the other end.
///
/// A Transfer outlives the peer list — the list is pruned, and a Device can
/// leave the group — so this falls back to the Fingerprint rather than
/// assuming the peer is still known.
String _nameOf(LocalTransferController controller, Fingerprint peer) {
  for (final candidate in controller.peers) {
    if (candidate.fingerprint == peer) return candidate.displayName;
  }
  return peer.short();
}

/// One Transfer, with the decision it may be waiting on.
class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.view,
    required this.controller,
    required this.peerName,
    required this.defaultIncomingDirectory,
  });

  final TransferView view;
  final LocalTransferController controller;
  final String peerName;
  final String? defaultIncomingDirectory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outgoing = view.direction == TransferDirection.outgoing;
    final title = view.names.isEmpty
        ? labelForKind(view.kind)
        : view.names.first;
    final alsoNamed = view.names.length - 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  outgoing ? Icons.north_east : Icons.south_west,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  avatar: Icon(iconForState(view.state), size: 16),
                  label: Text(labelForState(view.state)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                '${outgoing ? 'To' : 'From'} $peerName',
                labelForKind(view.kind),
                if (alsoNamed > 0) 'and $alsoNamed more',
                if (view.kind == PayloadKind.file)
                  '${formatBytes(view.transferredBytes)} of '
                      '${formatBytes(view.totalBytes)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (!view.state.isSettled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: view.fraction),
              ),
            if (view.needsDecision)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => unawaited(_accept(context)),
                      icon: const Icon(Icons.download),
                      label: const Text('Accept'),
                    ),
                    TextButton.icon(
                      onPressed: () => _reject(context),
                      icon: const Icon(Icons.block),
                      label: const Text('Refuse'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context) async {
    final offer = view.offer;
    if (offer == null) return;
    final path = await askForDirectory(
      context,
      title: view.kind == PayloadKind.file
          ? 'Where should these files land?'
          : 'Where should this arrive?',
      initial: defaultIncomingDirectory,
    );
    if (path == null) return;
    // The dialog is gone by now, and so may be the page.
    if (!context.mounted) return;
    await guarded(context, () async {
      final directory = Directory(path);
      // A folder the user typed may not exist yet; creating it here rather
      // than failing the Transfer is what makes the field usable.
      directory.createSync(recursive: true);
      await controller.acceptInto(offer, directory);
    });
  }

  void _reject(BuildContext context) {
    final offer = view.offer;
    if (offer == null) return;
    unawaited(guarded(context, () => controller.reject(offer)));
  }
}

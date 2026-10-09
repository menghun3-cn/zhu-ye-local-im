import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../transfer_actions.dart';
import '../wechat/theme.dart';
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
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    // Only files are listed here. A text message is a conversation, not a
    // transfer — it lives in the conversation it was said in, where the answer
    // to it belongs too — and a clipboard entry is mirrored, not moved. Both
    // travel the same machinery underneath, so both appear in `controller`
    // .transfers, and both are filtered out here: a menu that repeated what
    // two other surfaces already show, minus the context, would be a third
    // place answering for one thing.
    final transfers = [
      for (final view in controller.transfers)
        if (view.kind == PayloadKind.file) view,
    ];
    if (transfers.isEmpty) {
      return Padding(
        padding: WeChat.pagePadding,
        child: HintText(l10n.transfersEmptyHint),
      );
    }
    return ListView.builder(
      padding: WeChat.pagePadding,
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final outgoing = view.direction == TransferDirection.outgoing;
    final title = view.names.isEmpty
        ? labelForKind(view.kind, l10n)
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
                  color: WeChat.secondaryText,
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
                  label: Text(labelForState(view.state, l10n)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                outgoing
                    ? l10n.transferTo(peerName)
                    : l10n.transferFrom(peerName),
                labelForKind(view.kind, l10n),
                if (alsoNamed > 0) l10n.andMore(alsoNamed),
                if (view.kind == PayloadKind.file)
                  l10n.bytesOf(
                    formatBytes(view.transferredBytes),
                    formatBytes(view.totalBytes),
                  ),
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
                      onPressed: () => unawaited(
                        acceptOffer(
                          context,
                          controller,
                          view,
                          defaultDirectory: defaultIncomingDirectory,
                        ),
                      ),
                      icon: const Icon(Icons.download),
                      label: Text(l10n.accept),
                    ),
                    TextButton.icon(
                      onPressed: () => rejectOffer(context, controller, view),
                      icon: const Icon(Icons.block),
                      label: Text(l10n.refuse),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

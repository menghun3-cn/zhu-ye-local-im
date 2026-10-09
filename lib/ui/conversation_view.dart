import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'controller_scope.dart';
import 'dialogs.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';
import 'transfer_actions.dart';
import 'widgets.dart';

/// One Device's conversation: the messages, and the box that writes more.
///
/// This is the body of a conversation without the frame around it: no
/// [Scaffold], no [AppBar], no title. That is deliberate — the same body is
/// drawn two ways. `ConversationPage` pushes it as a route of its own, filling
/// a window; the Conversations surface puts it in the right-hand pane beside a
/// list of every conversation. Both want the same history and the same
/// composer, and neither wants the other's chrome, so the chrome is what stays
/// outside.
///
/// An arriving file offer appears here as a message that has not been answered
/// yet, with the two answers on it, so the thing that was sent and the decision
/// it needs are in the same place. Text never does: it is accepted on arrival
/// (see `LocalTransferController`), so it shows as an ordinary message.
class ConversationView extends StatefulWidget {
  /// Shows the conversation with [peer].
  const ConversationView({
    super.key,
    required this.peer,
    this.defaultIncomingDirectory,
    this.header,
  });

  /// The Device this conversation is with.
  final Fingerprint peer;

  /// Where a file received here lands when the user has not said otherwise.
  final String? defaultIncomingDirectory;

  /// Drawn above the history, inside this view rather than as an [AppBar].
  ///
  /// The shell's Conversations surface wants a header, because it has no
  /// [Scaffold] of its own to put one in; the pushed page passes null because
  /// its [AppBar] already names the peer.
  final Widget? header;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final TextEditingController _message = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// What is known about this peer right now, or null once it is unknown.
  PeerView? _peerOf(LocalTransferController controller) {
    for (final peer in controller.peers) {
      if (peer.fingerprint == widget.peer) return peer;
    }
    return null;
  }

  /// This conversation's messages, newest first.
  ///
  /// Newest first because the list is drawn reversed — the newest message is
  /// at the bottom, which is where a conversation is read from.
  List<TransferView> _messagesOf(LocalTransferController controller) => [
    for (final view in controller.transfers)
      // Clipboard entries travel as Transfers too, but they are mirrored
      // rather than written and read, so they would be noise here.
      if (view.peer == widget.peer && view.kind != PayloadKind.clipboard) view,
  ];

  void _sendMessage(LocalTransferController controller) {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    unawaited(
      guarded(context, () async {
        await controller.sendText(text, to: widget.peer);
        _message.clear();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final peer = _peerOf(controller);
    final messages = _messagesOf(controller);

    return Column(
      children: [
        if (widget.header != null) widget.header!,
        Expanded(
          child: messages.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: HintText(l10n.conversationEmpty),
                )
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => MessageBubble(
                    view: messages[index],
                    controller: controller,
                    defaultIncomingDirectory: widget.defaultIncomingDirectory,
                  ),
                ),
        ),
        const Divider(height: 1),
        ConversationComposer(
          message: _message,
          onSend: () => _sendMessage(controller),
          onAttach: peer == null
              ? null
              : () => unawaited(
                  showSendFileDialog(
                    context,
                    controller,
                    to: widget.peer,
                    name: peer.displayName,
                  ),
                ),
        ),
      ],
    );
  }
}

/// The box a message is typed in, and the two things that can be done with it.
class ConversationComposer extends StatelessWidget {
  /// Builds the composer over [message].
  const ConversationComposer({
    super.key,
    required this.message,
    required this.onSend,
    required this.onAttach,
  });

  /// The text being typed. Owned by the caller so it survives a rebuild.
  final TextEditingController message;

  /// Sends what is in [message].
  final VoidCallback onSend;

  /// Null when the peer is no longer known well enough to send to it.
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: onAttach,
              tooltip: l10n.menuSendFile,
              icon: const Icon(Icons.attach_file),
            ),
            Expanded(
              child: TextField(
                controller: message,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: l10n.messageHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: onSend,
              tooltip: l10n.send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// One message: what it carries, where it got to, and any answer it needs.
class MessageBubble extends StatelessWidget {
  /// Draws [view].
  const MessageBubble({
    super.key,
    required this.view,
    required this.controller,
    required this.defaultIncomingDirectory,
  });

  /// The Transfer this bubble is for.
  final TransferView view;

  /// The controller the two answers are called on.
  final LocalTransferController controller;

  /// Where a file received from this bubble lands by default.
  final String? defaultIncomingDirectory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final outgoing = view.direction == TransferDirection.outgoing;
    final scheme = theme.colorScheme;
    final background = outgoing
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = outgoing
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _body(context, l10n, foreground),
            // A conversation is not a transfer: for a text message the
            // "kind · state" line would read "text · completed", which is
            // transfer bookkeeping the user has no use for — a chat bubble
            // says what it says, and its direction is already the side of the
            // pane it sits on. A file keeps the line, because there it is the
            // receipt the user reads.
            if (view.kind != PayloadKind.text) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    outgoing ? Icons.north_east : Icons.south_west,
                    size: 12,
                    color: foreground,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    [
                      labelForKind(view.kind, l10n),
                      labelForState(view.state, l10n),
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ],
            if (!view.state.isSettled)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(
                  value: view.fraction,
                  minHeight: 3,
                ),
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
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(l10n.accept),
                    ),
                    TextButton.icon(
                      onPressed: () => rejectOffer(context, controller, view),
                      icon: const Icon(Icons.block, size: 18),
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

  /// What the message actually says: its words, or the files it carries.
  Widget _body(BuildContext context, AppLocalizations l10n, Color foreground) {
    final text = view.text;
    if (view.kind == PayloadKind.text && text != null) {
      return SelectableText(text, style: TextStyle(color: foreground));
    }
    final theme = Theme.of(context);
    final lines = <Widget>[
      for (final name in view.names)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconForKind(view.kind), size: 16, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
      if (view.kind == PayloadKind.file)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.bytesOf(
              formatBytes(view.transferredBytes),
              formatBytes(view.totalBytes),
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }
}

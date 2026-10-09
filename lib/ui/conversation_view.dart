import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'controller_scope.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';
import 'pickers.dart';
import 'transfer_actions.dart';
import 'wechat/bubble.dart';
import 'wechat/image_bubble.dart';
import 'wechat/theme.dart';
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

  /// Whether a drag from outside the window is over the history right now.
  bool _dropping = false;

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

  /// Asks for files and sends whatever came back.
  ///
  /// Every chosen file becomes its own message rather than one offer of many:
  /// a conversation reads a line at a time, and a single bubble naming eight
  /// files is a folder listing, not a message. Files the picker called images
  /// are sent as images so they draw.
  Future<void> _pickAndSend(LocalTransferController controller) async {
    final chosen = await PickerResolution.picker.files();
    if (!mounted || chosen.isEmpty) return;
    await _sendPaths(controller, [for (final file in chosen) file.path]);
  }

  /// Asks for one image and sends it.
  Future<void> _pickAndSendImage(LocalTransferController controller) async {
    final chosen = await PickerResolution.picker.image();
    if (!mounted || chosen == null) return;
    await _sendPaths(controller, [chosen.path]);
  }

  /// Sends each of [paths] as its own message, pictures as pictures.
  Future<void> _sendPaths(
    LocalTransferController controller,
    List<String> paths,
  ) async {
    final drop = classifyDrop(paths);
    await guarded(context, () async {
      for (final image in drop.images) {
        await controller.sendImage(image, to: widget.peer);
      }
      for (final file in drop.files) {
        await controller.sendFile(file, to: widget.peer);
      }
    });
  }

  /// The frame drawn over the history while a drag is in progress.
  ///
  /// A drop with no visible answer is the worst kind: the user is holding a
  /// file over a window that looks exactly as it did before, and has no way to
  /// tell whether letting go will do anything.
  Widget _dropOverlay() {
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: Container(
        color: WeChat.brand.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: WeChat.bubbleIn,
            borderRadius: BorderRadius.circular(WeChat.bubbleRadius),
            border: Border.all(color: WeChat.brand, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.file_download_outlined,
                color: WeChat.brand,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.dropToSend,
                style: const TextStyle(
                  fontSize: WeChat.fontSizeBody,
                  color: WeChat.bubbleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final peer = _peerOf(controller);
    final messages = _messagesOf(controller);
    final self = controller.self;
    // A drop is only meaningful when there is somewhere to send to; without a
    // peer the overlay would promise something the app cannot do.
    final canSend = peer != null;

    final history = messages.isEmpty
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
              // A Device with no name is named by its Fingerprint, which is
              // also its seed — so an unnamed peer still gets an avatar that
              // is stable and its own.
              peerName: peer?.displayName ?? widget.peer.short(),
              peerSeed: widget.peer.hex,
              selfName: self.displayName,
              selfSeed: self.fingerprint.hex,
            ),
          );
    return Column(
      children: [
        if (widget.header != null) widget.header!,
        Expanded(
          child: DropTarget(
            // Only registered when there is a peer: a target that accepted a
            // drop it could not send would swallow the file silently.
            enable: canSend,
            onDragEntered: (_) => setState(() => _dropping = true),
            onDragExited: (_) => setState(() => _dropping = false),
            onDragDone: (detail) {
              setState(() => _dropping = false);
              unawaited(
                _sendPaths(controller, [
                  for (final file in detail.files) file.path,
                ]),
              );
            },
            child: Stack(
              children: [
                Positioned.fill(child: history),
                if (_dropping) _dropOverlay(),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        ConversationComposer(
          message: _message,
          onSend: () => _sendMessage(controller),
          onAttach: canSend ? () => unawaited(_pickAndSend(controller)) : null,
          onPickImage: canSend
              ? () => unawaited(_pickAndSendImage(controller))
              : null,
        ),
      ],
    );
  }
}

/// The box a message is typed in, and the two things that can be done with it.
///
/// Laid out the way WeChat's composer is: a row of small grey tool buttons with
/// the paperclip among them, then a borderless white field on the page's grey,
/// then a flat brand-green "send" — not a Material [FilledButton], whose
/// elevation and rounded-rectangle padding read as a form submit rather than a
/// chat send.
///
/// Enter sends and Shift+Enter breaks the line, which is the desktop
/// convention. That is not what [TextField] does by default, so it is wired by
/// hand in `_ComposerField` below; `textInputAction` is only a hint to the
/// *platform* keyboard and does nothing for a physical one.
class ConversationComposer extends StatefulWidget {
  /// Builds the composer over [message].
  const ConversationComposer({
    super.key,
    required this.message,
    required this.onSend,
    required this.onAttach,
    this.onPickImage,
  });

  /// The text being typed. Owned by the caller so it survives a rebuild.
  final TextEditingController message;

  /// Sends what is in [message].
  final VoidCallback onSend;

  /// Null when the peer is no longer known well enough to send to it.
  final VoidCallback? onAttach;

  /// Null when an image cannot be sent — no peer, or no picker on this platform.
  final VoidCallback? onPickImage;

  @override
  State<ConversationComposer> createState() => _ConversationComposerState();
}

class _ConversationComposerState extends State<ConversationComposer> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Sends, then puts the caret back in the box.
  ///
  /// Two things would otherwise take it away, and both have to be answered
  /// here rather than by the caller. [TextField.onSubmitted] fires when a
  /// physical Enter is pressed even though the field never loses focus on its
  /// own, and the rebuild that follows `onSend` can drop and re-create the
  /// field if its key changes — so the focus is re-requested *after* the frame
  /// that the send caused, not before it.
  void _send() {
    widget.onSend();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Container(
        // A hairline rather than a [Divider]: the composer sits on its own
        // slightly-grey panel in WeChat, and a full-width rule between the two
        // greys would draw a line the reference does not have.
        decoration: const BoxDecoration(
          color: WeChat.toolbarBackground,
          border: Border(top: BorderSide(color: WeChat.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: widget.onAttach,
                  tooltip: l10n.menuSendFile,
                  icon: const Icon(Icons.attach_file, size: 20),
                  color: WeChat.secondaryText,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: widget.onPickImage,
                  tooltip: l10n.menuSendImage,
                  icon: const Icon(Icons.image_outlined, size: 20),
                  color: WeChat.secondaryText,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: WeChat.bubbleIn,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _ComposerField(
                      controller: widget.message,
                      focusNode: _focus,
                      hint: l10n.messageHint,
                      onSend: _send,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(label: l10n.send, onPressed: _send),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The text field, wired so that Enter sends and Shift+Enter breaks the line.
///
/// [TextField] with `maxLines: null` treats Enter as a newline and never calls
/// [TextField.onSubmitted] — the opposite of what a chat box does. The field is
/// therefore given `maxLines: null` (so it still grows) and a [Shortcuts] layer
/// that turns a bare Enter into [SendMessageIntent] while leaving Shift+Enter
/// to fall through to the default newline insert.
///
/// [TextField.onSubmitted] is wired as well, and is not redundant: a physical
/// Enter arrives as a key event (the [Shortcuts] path), but a soft keyboard's
/// send key, a test's `TextInputAction.send`, and any platform that reports the
/// action instead of the key arrive here. Both roads lead to the same [onSend].
class _ComposerField extends StatelessWidget {
  const _ComposerField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): SendMessageIntent(),
        // The same intent under the numpad's key, which is a distinct
        // logical key and would otherwise do nothing on a full-size keyboard.
        SingleActivator(LogicalKeyboardKey.numpadEnter): SendMessageIntent(),
      },
      child: Actions(
        actions: {
          SendMessageIntent: CallbackAction<SendMessageIntent>(
            onInvoke: (_) {
              onSend();
              return null;
            },
          ),
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          minLines: 1,
          maxLines: 6,
          // The action a soft keyboard's send key reports, and what a test
          // drives with `TextInputAction.send`. A physical Enter never reaches
          // this — it is answered by the [Shortcuts] layer above.
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSend(),
          style: const TextStyle(
            fontSize: WeChat.fontSizeInput,
            color: WeChat.bubbleText,
          ),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintStyle: const TextStyle(
              fontSize: WeChat.fontSizeInput,
              color: WeChat.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

/// What a bare Enter in the composer means.
class SendMessageIntent extends Intent {
  /// Const so the intent can live in a `const` shortcut table.
  const SendMessageIntent();
}

/// The composer's send button: a flat green pill, as the desktop client has.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(WeChat.brand),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        ),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: WeChat.fontSizePreview),
        ),
      ),
      child: Text(label),
    );
  }
}

/// One message: what it carries, where it got to, and any answer it needs.
///
/// Laid out the way WeChat lays a message out — an avatar, then a bubble, with
/// the pair mirrored for what the user sent. The avatar is not decoration: it
/// is what lets the bubble's tail read as pointing at somebody, and it is how
/// two consecutive messages from different Devices stay tellable apart.
class MessageBubble extends StatelessWidget {
  /// Draws [view].
  const MessageBubble({
    super.key,
    required this.view,
    required this.controller,
    required this.defaultIncomingDirectory,
    required this.peerName,
    required this.peerSeed,
    required this.selfName,
    required this.selfSeed,
  });

  /// The Transfer this bubble is for.
  final TransferView view;

  /// The controller the two answers are called on.
  final LocalTransferController controller;

  /// Where a file received from this bubble lands by default.
  final String? defaultIncomingDirectory;

  /// What the other Device is called, and what colours its avatar.
  final String peerName;

  /// What colours the other Device's avatar — its Fingerprint.
  final String peerSeed;

  /// What this Device is called, and what colours its own avatar.
  final String selfName;

  /// What colours this Device's own avatar.
  final String selfSeed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outgoing = view.direction == TransferDirection.outgoing;
    final background = outgoing ? WeChat.bubbleOut : WeChat.bubbleIn;

    return Padding(
      padding: const EdgeInsets.only(bottom: WeChat.messageGap),
      child: Row(
        mainAxisAlignment: outgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!outgoing) ...[
            Avatar(name: peerName, seed: peerSeed),
            const SizedBox(width: WeChat.bubbleAvatarGap),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: outgoing
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                MessageBubbleShape(
                  colour: background,
                  outgoing: outgoing,
                  child: _contents(context, l10n),
                ),
                // A conversation is not a transfer: for a message that *is* its
                // own content the "kind · state" line would read
                // "text · completed", which is transfer bookkeeping the user
                // has no use for — a chat bubble says what it says, and its
                // direction is already the side it sits on. A file keeps the
                // line, because there it is the receipt the user reads.
                if (_showsReceipt) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: WeChat.bubblePadding.horizontal,
                    ),
                    child: Text(
                      [
                        labelForKind(view.kind, l10n),
                        labelForState(view.state, l10n),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: WeChat.secondaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (outgoing) ...[
            const SizedBox(width: WeChat.bubbleAvatarGap),
            Avatar(name: selfName, seed: selfSeed),
          ],
        ],
      ),
    );
  }

  /// Everything inside the bubble: the message, its progress, and the answers
  /// an offer needs.
  Widget _contents(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _body(context, l10n),
        if (!view.state.isSettled)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(
              value: view.fraction,
              minHeight: 3,
              backgroundColor: Colors.black12,
            ),
          ),
        if (view.needsDecision)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BubbleAction(
                  label: l10n.refuse,
                  onPressed: () => rejectOffer(context, controller, view),
                  primary: false,
                ),
                const SizedBox(width: 8),
                _BubbleAction(
                  label: l10n.accept,
                  onPressed: () => unawaited(
                    acceptOffer(
                      context,
                      controller,
                      view,
                      defaultDirectory: defaultIncomingDirectory,
                    ),
                  ),
                  primary: true,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Whether the "kind · state" line belongs under this bubble.
  ///
  /// Only for a file: everything else in a conversation is its own content, and
  /// a receipt for it would be bookkeeping about a message that has no
  /// bookkeeping to show.
  bool get _showsReceipt => view.kind == PayloadKind.file;

  /// What the message actually says: its words, an image, or the files it
  /// carries.
  Widget _body(BuildContext context, AppLocalizations l10n) {
    final text = view.text;
    if (view.kind == PayloadKind.text && text != null) {
      return SelectableText(
        text,
        style: const TextStyle(
          fontSize: WeChat.fontSizeBody,
          height: WeChat.lineHeightBody,
          color: WeChat.bubbleText,
        ),
      );
    }
    if (view.kind == PayloadKind.image) return _image(context);
    final lines = <Widget>[
      for (final name in view.names)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconForKind(view.kind), size: 18, color: WeChat.bubbleText),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: WeChat.fontSizeBody,
                  color: WeChat.bubbleText,
                ),
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
            style: const TextStyle(
              fontSize: WeChat.fontSizeMeta,
              color: WeChat.secondaryText,
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }

  /// An image message: the picture, or the promise of one.
  ///
  /// Three states, and each has to be told apart from the others because
  /// "no picture" is not the same as "not here yet":
  ///
  /// * no path — the bytes are on their way (or the offer has not been
  ///   answered), so the bubble shows the file's name exactly as a file message
  ///   would, and the progress bar below it says how long that will take;
  /// * a path — the picture;
  /// * a path that no longer reads — [ImageBubble] draws its own fallback.
  Widget _image(BuildContext context) {
    final path = view.localPath;
    if (path == null) {
      final name = view.names.isEmpty ? '' : view.names.first;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 18, color: WeChat.bubbleText),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: WeChat.fontSizeBody,
                color: WeChat.bubbleText,
              ),
            ),
          ),
        ],
      );
    }
    final name = view.names.isEmpty ? '' : view.names.first;
    return ImageBubble(
      path: path,
      name: name,
      onOpen: () =>
          unawaited(showImagePreview(context, path: path, name: name)),
    );
  }
}

/// A small button drawn inside a bubble.
///
/// [FilledButton]'s *default* look is built for a page — a bubble is fifteen
/// pixels of text, and the default button's elevation and padding make it look
/// like a form control. What is dropped is the default, not the widget: every
/// colour and metric is overridden through [ButtonStyle], so this stays a real
/// button — focusable, keyboard-activatable, and findable by its type in a test
/// — while looking the way the bubble needs it to.
class _BubbleAction extends StatelessWidget {
  const _BubbleAction({
    required this.label,
    required this.onPressed,
    required this.primary,
  });

  final String label;
  final VoidCallback onPressed;

  /// Filled in the brand colour when it is the answer the user most likely
  /// wants, outlined otherwise.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        primary ? WeChat.brand : Colors.transparent,
      ),
      // Inside an incoming bubble this sits on white and inside an outgoing one
      // on the bubble green; the outlined variant is drawn in `divider`, which
      // reads as a hairline against both.
      foregroundColor: WidgetStatePropertyAll(
        primary ? Colors.white : WeChat.bubbleText,
      ),
      side: primary
          ? null
          : const WidgetStatePropertyAll(BorderSide(color: WeChat.divider)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: WeChat.fontSizePreview),
      ),
    );
    return TextButton(onPressed: onPressed, style: style, child: Text(label));
  }
}

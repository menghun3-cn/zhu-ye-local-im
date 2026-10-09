import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'clipboard_paste.dart';
import 'controller_scope.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';
import 'pasted_image.dart';
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

  /// Files and pictures chosen for the next message, in the order they were
  /// chosen. Nothing here has been offered to the peer yet: picking a file is
  /// not sending one, and a message is read in the order it was composed, so
  /// the text and everything staged leave together when 发送 is pressed.
  final List<StagedAttachment> _staged = [];

  @override
  void didUpdateWidget(ConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell keys this view by peer, so in practice a new peer means a new
    // State. Clearing anyway costs nothing and makes "a draft never crosses
    // into somebody else's conversation" a property of this widget rather than
    // of how its callers happen to key it.
    if (oldWidget.peer != widget.peer) _staged.clear();
  }

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

  /// Sends the box: the text that was typed, then everything staged.
  ///
  /// One message per staged file, as a picked file always was: a conversation
  /// reads a line at a time, and a single bubble naming eight files is a folder
  /// listing, not a message. Everything is sent before either list is cleared,
  /// so a send that fails leaves the draft where it was and the user can try
  /// again rather than having to choose the files over.
  void _sendMessage(LocalTransferController controller) {
    final text = _message.text.trim();
    final staged = List.of(_staged);
    if (text.isEmpty && staged.isEmpty) return;
    unawaited(
      guarded(context, () async {
        if (text.isNotEmpty) await controller.sendText(text, to: widget.peer);
        for (final attachment in staged) {
          final file = File(attachment.path);
          await (attachment.isImage
              ? controller.sendImage(file, to: widget.peer)
              : controller.sendFile(file, to: widget.peer));
        }
        _message.clear();
        if (!mounted) return;
        setState(() => _staged.clear());
      }),
    );
  }

  /// Asks for files and puts what came back in the composer.
  ///
  /// Picking is not sending: the files wait in the box until 发送 is pressed, so
  /// that a message can be written beside them and a wrong choice can be taken
  /// back without having to answer a question on the far side's screen.
  Future<void> _pickFiles() async {
    final chosen = await PickerResolution.picker.files();
    if (!mounted || chosen.isEmpty) return;
    _stagePaths([for (final file in chosen) file.path]);
  }

  /// Asks for one image and puts it in the composer.
  Future<void> _pickImage() async {
    final chosen = await PickerResolution.picker.image();
    if (!mounted || chosen == null) return;
    _stagePaths([chosen.path]);
  }

  /// Stages whatever the clipboard is holding, and says whether it staged
  /// anything.
  ///
  /// Files first, then a picture. Text is deliberately **not** this method's
  /// business: a plain text clipboard is what Ctrl+V already means, and
  /// answering it here would take the ordinary paste away from the field. The
  /// bool is what lets the composer fall through to it.
  ///
  /// Copying a file in Explorer puts it on the clipboard as a *file*, not as
  /// its contents, and a screenshot arrives as an image with no name at all —
  /// so the picture is written to a temporary file the engine can stream from,
  /// which is the only shape a Transfer understands.
  Future<bool> _pasteIntoComposer(LocalTransferController controller) async {
    // Without a peer there is nowhere to send to, so this is an ordinary text
    // paste after all.
    if (_peerOf(controller) == null) return false;

    final clipboard = PasteResolution.paste;

    final paths = await clipboard.files();
    if (!mounted) return false;
    if (paths.isNotEmpty && _stagePaths(paths) > 0) return true;

    final bytes = await clipboard.image();
    if (!mounted || bytes == null) return false;
    final image = await writePastedImage(bytes);
    if (!mounted || image == null) return false;
    return _stagePaths([image.path]) > 0;
  }

  /// Puts each of [paths] in the composer, pictures as pictures.
  ///
  /// Returns how many it staged, which is what tells a paste whether the
  /// clipboard held anything this app could carry: a folder arrives as a path
  /// with nothing behind it, and classifying it out is not the same as having
  /// taken it.
  int _stagePaths(List<String> paths) {
    final staged = [
      for (final entry in classifyPaths(paths))
        StagedAttachment(
          path: entry.file.path,
          name: fileNameOf(entry.file.path),
          isImage: entry.isImage,
        ),
    ];
    if (staged.isEmpty) return 0;
    setState(() => _staged.addAll(staged));
    return staged.length;
  }

  /// Sends each of [paths] as its own message, pictures as pictures.
  ///
  /// The drag-and-drop path, and the only one that still sends straight away:
  /// the overlay a drag draws over the history says "松手即发送", so a drop is a
  /// person choosing to send a thing rather than to compose a message around
  /// it. Picking and pasting stage instead, and 发送 is what releases those.
  Future<void> _sendDropped(List<String> paths) async {
    final classified = classifyPaths(paths);
    if (classified.isEmpty) return;
    final controller = ControllerScope.of(context);
    await guarded(context, () async {
      for (final entry in classified) {
        await (entry.isImage
            ? controller.sendImage(entry.file, to: widget.peer)
            : controller.sendFile(entry.file, to: widget.peer));
      }
    });
  }

  /// Takes the staged attachment at [index] back out of the composer.
  void _removeStaged(int index) {
    if (index < 0 || index >= _staged.length) return;
    setState(() => _staged.removeAt(index));
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
            color: WeChat.surface,
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
              // A Device with no name is named by its address, and by the last
              // number of it inside the avatar — see `PeerView.avatarLabel`.
              // With no peer in the list at all there is only the Fingerprint,
              // which is stable and its own, so the avatar is still the same
              // one every time.
              peerName: peer?.displayName ?? widget.peer.short(),
              peerLabel: peer?.avatarLabel,
              peerSeed: widget.peer.hex,
              selfName: self.displayName,
              selfSeed: self.fingerprint.hex,
            ),
          );
    return Column(
      children: [
        if (widget.header != null) widget.header!,
        Expanded(
          // The history is a white board with a grey bubble on it for anything
          // received: the WeChat conversation inverted, which is what the two
          // fills trading places means. The header and the composer keep their
          // own greys, so only this pane moves.
          child: ColoredBox(
            color: WeChat.conversationBackground,
            child: DropTarget(
              // Only registered when there is a peer: a target that accepted a
              // drop it could not send would swallow the file silently.
              enable: canSend,
              onDragEntered: (_) => setState(() => _dropping = true),
              onDragExited: (_) => setState(() => _dropping = false),
              onDragDone: (detail) {
                setState(() => _dropping = false);
                unawaited(
                  _sendDropped([for (final file in detail.files) file.path]),
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
        ),
        const Divider(height: 1),
        ConversationComposer(
          message: _message,
          attachments: _staged,
          onRemoveAttachment: _removeStaged,
          onSend: () => _sendMessage(controller),
          onPaste: () => _pasteIntoComposer(controller),
          onAttach: canSend ? () => unawaited(_pickFiles()) : null,
          onPickImage: canSend ? () => unawaited(_pickImage()) : null,
        ),
      ],
    );
  }
}

/// A file or a picture chosen for the next message but not sent yet.
///
/// The composer's own small model: it knows what to call the thing and whether
/// it is drawn as a picture, and nothing else — the conversation owns the paths
/// and does the sending.
class StagedAttachment {
  /// Stages [path], which will be sent as [name].
  const StagedAttachment({
    required this.path,
    required this.name,
    required this.isImage,
  });

  /// Where the bytes are, as the engine will read them.
  final String path;

  /// What the chip says — the file's own name, not its folder.
  final String name;

  /// Whether the far side will draw it as a picture.
  final bool isImage;
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
    required this.onPaste,
    required this.onAttach,
    this.onPickImage,
    this.attachments = const [],
    this.onRemoveAttachment,
  });

  /// The text being typed. Owned by the caller so it survives a rebuild.
  final TextEditingController message;

  /// Sends what is in [message], and everything in [attachments].
  final VoidCallback onSend;

  /// Stages whatever the clipboard is holding, and answers false when it held
  /// no file and no picture — which is the signal to paste text as usual.
  final Future<bool> Function() onPaste;

  /// Null when the peer is no longer known well enough to send to it.
  final VoidCallback? onAttach;

  /// Null when an image cannot be sent — no peer, or no picker on this platform.
  final VoidCallback? onPickImage;

  /// Files and pictures chosen for this message that have not gone out yet.
  ///
  /// Drawn above the field so that what 发送 is about to release is visible
  /// while the message beside it is being written.
  final List<StagedAttachment> attachments;

  /// Takes the attachment at the given index back out. Null when nothing can be
  /// staged, which is the same condition as [onAttach] being null.
  final ValueChanged<int>? onRemoveAttachment;

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
            if (widget.attachments.isNotEmpty) ...[
              _AttachmentTray(
                attachments: widget.attachments,
                onRemove: widget.onRemoveAttachment,
                removeTooltip: l10n.removeAttachment,
              ),
              const SizedBox(height: 8),
            ],
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
                      color: WeChat.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _ComposerField(
                      controller: widget.message,
                      focusNode: _focus,
                      hint: l10n.messageHint,
                      onSend: _send,
                      onPaste: widget.onPaste,
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
    required this.onPaste,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSend;
  final Future<bool> Function() onPaste;

  /// Offers the clipboard to the conversation before the field takes it.
  ///
  /// Answering the chord means the field's own paste never runs, so the
  /// ordinary case has to be reproduced by hand: [onPaste] reports whether it
  /// sent a file or a picture, and if it did not, this is a text paste after
  /// all and [_pasteText] does what the field would have done.
  Future<void> _paste() async {
    if (await onPaste()) return;
    await _pasteText();
  }

  /// The paste [TextField] would have performed, done here because intercepting
  /// Ctrl+V stopped it from ever happening.
  ///
  /// Copies [TextField]'s own rule — the selection is replaced, and the caret
  /// lands after what was inserted — rather than appending, so that pasting
  /// over a selection behaves the way it does everywhere else on the desktop.
  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid) {
      // Never focused, so there is no selection to replace: the text goes on
      // the end, which is what the field does with a caret it does not have.
      controller.value = TextEditingValue(
        text: value.text + text,
        selection: TextSelection.collapsed(
          offset: value.text.length + text.length,
        ),
      );
      return;
    }
    final replaced = value.text.replaceRange(
      selection.start,
      selection.end,
      text,
    );
    controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): SendMessageIntent(),
        // The same intent under the numpad's key, which is a distinct
        // logical key and would otherwise do nothing on a full-size keyboard.
        SingleActivator(LogicalKeyboardKey.numpadEnter): SendMessageIntent(),
        // Paste, claimed so that a file or a picture on the clipboard can
        // become a message. Both chords: a desktop has one and a Mac the other,
        // and this is the same one line either way.
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            PasteIntoComposerIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            PasteIntoComposerIntent(),
      },
      child: Actions(
        actions: {
          SendMessageIntent: CallbackAction<SendMessageIntent>(
            onInvoke: (_) {
              onSend();
              return null;
            },
          ),
          PasteIntoComposerIntent: CallbackAction<PasteIntoComposerIntent>(
            onInvoke: (_) {
              // The clipboard is read asynchronously but a key handler has to
              // answer now: claiming the chord is what stops the field from
              // pasting text underneath us, and the fallback runs afterwards.
              unawaited(_paste());
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

/// What Ctrl+V in the composer means.
///
/// Its own intent rather than the framework's `PasteTextIntent`, because this
/// one is answered by the conversation: the clipboard may be holding a file or
/// a screenshot, and those are messages rather than text.
class PasteIntoComposerIntent extends Intent {
  /// Const so the intent can live in a `const` shortcut table.
  const PasteIntoComposerIntent();
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

/// What is waiting in the composer, above the field.
///
/// A [Wrap] rather than a row, and rather than a bottom sheet: two files fit on
/// one line, sixteen do not, and a composer that silently hid the eleventh is a
/// composer that would send something the user could not see.
class _AttachmentTray extends StatelessWidget {
  const _AttachmentTray({
    required this.attachments,
    required this.onRemove,
    required this.removeTooltip,
  });

  final List<StagedAttachment> attachments;
  final ValueChanged<int>? onRemove;
  final String removeTooltip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var index = 0; index < attachments.length; index++)
          _AttachmentChip(
            attachment: attachments[index],
            // Indexed rather than keyed by name: two files can share a name —
            // one picked from two folders — and the chip is positional anyway.
            onRemove: onRemove == null ? null : () => onRemove!(index),
            removeTooltip: removeTooltip,
          ),
      ],
    );
  }
}

/// One staged file or picture, waiting for 发送.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.onRemove,
    required this.removeTooltip,
  });

  final StagedAttachment attachment;

  /// Null when the composer cannot stage anything in the first place.
  final VoidCallback? onRemove;

  final String removeTooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: WeChat.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: WeChat.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.isImage ? Icons.image_outlined : Icons.attach_file,
            size: 16,
            color: WeChat.secondaryText,
          ),
          const SizedBox(width: 6),
          // Bounded so that one long name cannot push 发送 off the row; the
          // tooltip keeps the whole of it reachable.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Tooltip(
              message: attachment.name,
              child: Text(
                attachment.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: WeChat.fontSizePreview,
                  color: WeChat.bubbleText,
                ),
              ),
            ),
          ),
          // A real [IconButton] rather than a tappable glyph: it keeps the
          // focus ring, the keyboard activation and the semantic label that a
          // hand-rolled gesture detector would drop.
          IconButton(
            onPressed: onRemove,
            tooltip: removeTooltip,
            icon: const Icon(Icons.close, size: 14),
            color: WeChat.secondaryText,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
          ),
        ],
      ),
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
    required this.peerLabel,
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

  /// What to draw in the other Device's avatar instead of the first character
  /// of [peerName], when its name is not what should be drawn there.
  final String? peerLabel;

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
            Avatar(name: peerName, seed: peerSeed, label: peerLabel),
            const SizedBox(width: WeChat.bubbleAvatarGap),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: outgoing
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // A right-click on a bubble is where "show me that file" lives,
                // and it is offered by the same widget the Transfers list uses
                // so the two surfaces cannot drift apart.
                TransferContextMenu(
                  view: view,
                  child: MessageBubbleShape(
                    colour: background,
                    outgoing: outgoing,
                    child: _contents(context, l10n),
                  ),
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

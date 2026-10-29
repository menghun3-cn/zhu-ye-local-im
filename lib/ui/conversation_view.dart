import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'clipboard_paste.dart';
import 'controller_scope.dart';
import 'emoji_picker.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';
import 'pasted_image.dart';
import 'pickers.dart';
import 'transfer_actions.dart';
import 'wechat/bubble.dart';
import 'wechat/composer_tool.dart';
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
    this.autoFocusComposer = false,
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

  /// Whether the composer's field should take focus when this view appears.
  ///
  /// The one case for it is *arriving* at a conversation — from the rail, from
  /// a row in the list, or from the Devices surface — where the user's next
  /// act is nearly always to type. A conversation that was merely rebuilt (the
  /// controller ticking while the user reads it elsewhere) must not steal
  /// focus, which is why this is opt-in per arrival rather than always on.
  final bool autoFocusComposer;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final TextEditingController _message = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Whether a drag from outside the window is over the history right now.
  bool _dropping = false;

  /// What the user has currently selected among the messages, or null.
  ///
  /// Held here rather than inside the [SelectionArea] because its only reader
  /// is a right-click menu on a message, which is a sibling of the area rather
  /// than inside it — see [MessageSelection]. Cleared by the area itself when
  /// the selection collapses, because `onSelectionChanged` fires with null on
  /// exactly that.
  String? _selectedText;

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
    if (oldWidget.peer != widget.peer) {
      _staged.clear();
      // A selection cannot survive into a conversation that replaced the one it
      // was made in either, and a stale one would let a copy on the new
      // conversation's menu put the old conversation's words on the clipboard.
      _selectedText = null;
    }
  }

  @override
  void dispose() {
    for (final attachment in _staged) {
      if (attachment.appOwned) _deleteStagedFile(attachment.path);
    }
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
              ? attachment.appOwned
                    ? controller.sendAppOwnedImage(file, to: widget.peer)
                    : controller.sendImage(file, to: widget.peer)
              : controller.sendFile(file, to: widget.peer));
        }
        _message.clear();
        if (!mounted) return;
        setState(() => _staged.clear());
      }),
    );
  }

  /// Puts [face] into the composer, and remembers it as recent.
  ///
  /// Picking a face is typing a face: it goes into the box and leaves with
  /// whatever else is in it when 发送 is pressed, the same way a face typed
  /// with the keyboard does. It used to go out on the tap as a message of its
  /// own, which meant a person who wanted to write a word next to their
  /// face had to send twice — and a face that is part of a sentence is
  /// ordinary text, not a sticker.
  ///
  /// The recent strip is updated on the same tap, so the next open of the
  /// picker has the face at the front.
  ///
  /// The insertion itself belongs to the composer, which owns the field and
  /// the caret in it: a face belongs where the caret is, not at the end of
  /// whatever happened to be typed before the picker was opened.
  void _insertEmoji(LocalTransferController controller, String face) {
    controller.rememberEmoji(face);
  }

  /// Asks for files and puts what came back in the composer.
  ///
  /// Picking is not sending: the files wait in the box until 发送 is pressed, so
  /// that a message can be written beside them and a wrong choice can be taken
  /// back without having to answer a question on the far side's screen.
  ///
  /// Pictures come through here too — one control, one dialog. What a choice
  /// turns out to be is [_stagePaths]' business, and that is also what decides
  /// whether the far side is asked to accept it: a picture is drawn on arrival,
  /// a file waits for a click.
  Future<void> _pickFiles() async {
    final chosen = await PickerResolution.picker.files();
    if (!mounted || chosen.isEmpty) return;
    _stagePaths([for (final file in chosen) file.path]);
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
    setState(
      () => _staged.add(
        StagedAttachment(
          path: image.path,
          name: fileNameOf(image.path),
          isImage: true,
          appOwned: true,
        ),
      ),
    );
    return true;
  }

  /// Puts each of [paths] in the composer, pictures as pictures.
  ///
  /// Returns how many it staged, which is what tells a paste whether the
  /// clipboard held anything this app could carry: a folder arrives as a path
  /// with nothing behind it, and classifying it out is not the same as having
  /// taken it.
  int _stagePaths(List<String> paths) {
    // Pasting an image writes a temporary file this app owns; everything else
    // a person chose or dropped is their own file and must never be removed.
    final staged = <StagedAttachment>[];
    for (final entry in classifyPaths(paths)) {
      staged.add(
        StagedAttachment(
          path: entry.file.path,
          name: fileNameOf(entry.file.path),
          isImage: entry.isImage,
          appOwned: false,
        ),
      );
    }
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
    final removed = _staged.removeAt(index);
    if (removed.appOwned) _deleteStagedFile(removed.path);
    setState(() {});
  }

  /// Deletes one temporary file this application created.
  void _deleteStagedFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // Best effort; a temp file that will not delete is not worth turning an
      // attachment removal into a failure.
    }
  }

  /// The frame drawn over the history while a drag is in progress.
  ///
  /// A drop with no visible answer is the worst kind: the user is holding a
  /// file over a window that looks exactly as it did before, and has no way to
  /// tell whether letting go will do anything.
  Widget _dropOverlay() {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return IgnorePointer(
      child: Container(
        color: colors.brand.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(WeChat.bubbleRadius),
            border: Border.all(color: colors.brand, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_download_outlined, color: colors.brand, size: 28),
              const SizedBox(height: 8),
              Text(
                l10n.dropToSend,
                style: TextStyle(
                  fontSize: WeChat.fontSizeBody,
                  color: colors.bubbleText,
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

    // The cap on a bubble is a share of the **chat area** — the column the
    // conversation is drawn in — so it is measured once, here, where that
    // width is known. A cap that each bubble measured for itself would be a
    // cap on the list's inner width, and it would shift whenever the list's
    // padding changed rather than whenever the window did.
    //
    // A [LayoutBuilder] re-reads the width on every change of it, so
    // resizing the window — or the divider between the list and the
    // conversation — moves the cap with the area instead of leaving it
    // behind.
    final history = LayoutBuilder(
      builder: (context, constraints) {
        final bubbleMaxWidth =
            constraints.maxWidth * WeChat.bubbleMaxWidthFactor;
        return messages.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: HintText(l10n.conversationEmpty),
              )
            // Selectable, the way every other piece of text on a desktop is: a
            // double-click takes a word and a drag takes a range. What it does
            // *not* do is draw the platform's own copy toolbar — a right-click
            // on a message opens the message's own menu instead, which knows
            // about the selection and offers 复制 of it alongside 打开所在目录
            // and 删除. See [TransferContextMenu]; that is the one place the
            // two are reconciled.
            //
            // The area wraps the whole list rather than each bubble, because a
            // selection that stops at a bubble's edge is not what a user
            // dragging across two messages is asking for.
            //
            // What it selects is published to the menus below it through
            // [MessageSelection]. A [SelectableRegionState] cannot be reached
            // from outside the widget that made it, so the selection has to
            // be pushed from here rather than pulled from there.
            : SelectionArea(
                onSelectionChanged: (content) =>
                    setState(() => _selectedText = content?.plainText),
                child: ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => MessageBubble(
                    view: messages[index],
                    controller: controller,
                    defaultIncomingDirectory: widget.defaultIncomingDirectory,
                    // The cap every bubble in this conversation is drawn to.
                    bubbleMaxWidth: bubbleMaxWidth,
                    // A Device with no name is named by its address, and by
                    // the last number of it inside the avatar — see
                    // `PeerView.avatarLabel`. With no peer in the list at all
                    // there is only the Fingerprint, which is stable and its
                    // own, so the avatar is still the same one every time.
                    peerName: peer?.displayName ?? widget.peer.short(),
                    peerLabel: peer?.avatarLabel,
                    peerSeed: widget.peer.hex,
                    selfName: self.displayName,
                    selfSeed: self.fingerprint.hex,
                  ),
                ),
              );
      },
    );
    return MessageSelection(
      // What the user has selected, so that a right-click on a message can
      // offer to copy it. Published here — around the whole conversation rather
      // than around the history alone — because the menu it is read by is
      // attached to a message, and a message is a descendant of this.
      text: _selectedText,
      child: Column(
        children: [
          if (widget.header != null) widget.header!,
          Expanded(
            // The history is a white board with a grey bubble on it for anything
            // received: the WeChat conversation inverted, which is what the two
            // fills trading places means. The header and the composer keep their
            // own greys, so only this pane moves.
            child: ColoredBox(
              color: WeChatColors.of(context).conversationBackground,
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
            onEmoji: canSend ? (face) => _insertEmoji(controller, face) : null,
            recentEmojis: controller.recentEmojis,
            autoFocus: widget.autoFocusComposer,
          ),
        ],
      ),
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
    this.appOwned = false,
  });

  /// Where the bytes are, as the engine will read them.
  final String path;

  /// What the tray says it is — a file chip's label, a thumbnail's tooltip.
  final String name;

  /// Whether the far side will draw it as a picture.
  final bool isImage;

  /// Whether this is a temporary file the application itself created.
  ///
  /// True only for a picture pasted out of the clipboard, which this app wrote
  /// into the temporary directory. Such a file can be taken away again when it
  /// is un-staged or the view goes away; a file a person picked or dropped is
  /// theirs and is never marked this way.
  final bool appOwned;
}

/// The box a message is typed in, and the two things that can be done with it.
///
/// Laid out the way WeChat's desktop client lays it out: a **rounded white
/// board** floating above the window's edge, the text written straight onto it
/// with no frame, a row of bare line-drawn tools along its lower edge, and the
/// send button at its bottom right.
///
/// The send is green when there is something to send and grey when there is
/// not, because that difference is the button's whole message — see
/// [_SendButton].
///
/// Enter sends and Shift+Enter breaks the line, which is the desktop
/// convention — and neither half of it is what a [TextField] gives on its own.
/// Both are claimed in `_ComposerField` below, where the reason Shift+Enter
/// cannot be left to the framework is written down.
class ConversationComposer extends StatefulWidget {
  /// Builds the composer over [message].
  const ConversationComposer({
    super.key,
    required this.message,
    required this.onSend,
    required this.onPaste,
    required this.onAttach,
    this.onEmoji,
    this.recentEmojis = const [],
    this.attachments = const [],
    this.onRemoveAttachment,
    this.autoFocus = false,
  });

  /// The text being typed. Owned by the caller so it survives a rebuild.
  final TextEditingController message;

  /// Sends what is in [message], and everything in [attachments].
  final VoidCallback onSend;

  /// Stages whatever the clipboard is holding, and answers false when it held
  /// no file and no picture — which is the signal to paste text as usual.
  final Future<bool> Function() onPaste;

  /// Null when the peer is no longer known well enough to send to it.
  ///
  /// The one way in for everything that can be attached, pictures included:
  /// whether a choice turns out to be a picture or a file is not this control's
  /// to say — see [_pickFiles] and [_stagePaths].
  final VoidCallback? onAttach;

  /// Called with the face the user chose from the emoticon picker.
  ///
  /// A face is a character the user chose, so it goes into the box and leaves
  /// with the rest of the message when 发送 is pressed — the same way a face
  /// typed with the keyboard does.
  ///
  /// Null when the peer is no longer known well enough to send to it.
  ///
  /// The same condition as [onAttach]: the face button is a way to send, and
  /// a way to send to nobody is not a button, it is a lie.
  final ValueChanged<String>? onEmoji;

  /// The faces to draw first in the picker, newest first.
  final List<String> recentEmojis;

  /// Whether there is anything in the composer worth sending.
  ///
  /// The send button greys out when there is not, the way WeChat's does: a
  /// live send on an empty box promises something that would not happen.
  ///
  /// The composer answers this itself rather than being told — what is in the
  /// box is its own business, and a caller that had to keep this in step with
  /// what the user typed would eventually get it wrong.
  bool get hasSomethingToSend =>
      message.text.trim().isNotEmpty || attachments.isNotEmpty;

  /// Files and pictures chosen for this message that have not gone out yet.
  ///
  /// Drawn above the field so that what 发送 is about to release is visible
  /// while the message beside it is being written.
  final List<StagedAttachment> attachments;

  /// Takes the attachment at the given index back out. Null when nothing can be
  /// staged, which is the same condition as [onAttach] being null.
  final ValueChanged<int>? onRemoveAttachment;

  /// Whether to request focus for the input field on the next frame.
  ///
  /// Used when the user switches to this conversation (via tab, list selection,
  /// or external request) so they can start typing immediately.
  final bool autoFocus;

  @override
  State<ConversationComposer> createState() => _ConversationComposerState();
}

class _ConversationComposerState extends State<ConversationComposer> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(ConversationComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autoFocus && widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

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

  /// Puts [text] where the caret is in the field.
  ///
  /// The same rule the field itself follows: a selection is replaced, and
  /// the caret lands after what was inserted. A face picked from the picker
  /// is a character typed into the field, so it goes where the person was
  /// writing — not at the end of the line, which is where appending would
  /// put it.
  void _insertAtCaret(String text) {
    final value = widget.message.value;
    final selection = value.selection;
    if (!selection.isValid) {
      // Never focused, so there is no caret to insert at: the text goes on
      // the end, which is what the field does with a caret it does not have.
      widget.message.value = TextEditingValue(
        text: value.text + text,
        selection: TextSelection.collapsed(
          offset: value.text.length + text.length,
        ),
      );
      return;
    }
    widget.message.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return SafeArea(
      top: false,
      // The board floats: a margin between it and the window's edge, so it
      // reads as a card laid on the conversation rather than as a strip
      // welded to the bottom of it.
      child: Padding(
        padding: const EdgeInsets.all(WeChat.composerBoardMargin),
        child: Container(
          // The board the whole input area is drawn on.
          //
          // A panel of its own, not a strip welded to the bottom: WeChat's
          // desktop client draws the input area as a **lighter board** that
          // floats on the conversation, and it carries a hairline of its own.
          decoration: BoxDecoration(
            color: colors.composerBoard,
            borderRadius: BorderRadius.circular(WeChat.composerBoardRadius),
            // The two greys are a step apart as well, so the line is not what
            // separates the board from the conversation — it is what says
            // where the board *ends*.
            border: Border.all(
              color: colors.composerBoardBorder,
              width: WeChat.composerBoardBorderWidth,
            ),
          ),
          child: ConstrainedBox(
            // The board has a height of its own even when there is nothing
            // in it: a composer that collapsed to nothing the moment it was
            // empty would be a composer whose whole height depended on what
            // the user had typed.
            constraints: const BoxConstraints(
              minHeight: WeChat.composerBoardHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The text area, at the top of the board.
                //
                // It is the board's *content*, so it takes the board's padding —
                // and the toolbar below it is a separate row rather than
                // something sharing this row's baseline. WeChat's input area is
                // two stacked things, not one line of controls.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WeChat.composerBoardPadding,
                    WeChat.composerBoardPadding,
                    WeChat.composerBoardPadding,
                    0,
                  ),
                  child: _ComposerField(
                    controller: widget.message,
                    focusNode: _focus,
                    hint: l10n.messageHint,
                    onSend: _send,
                    onPaste: widget.onPaste,
                  ),
                ),
                if (widget.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WeChat.composerBoardPadding,
                      8,
                      WeChat.composerBoardPadding,
                      0,
                    ),
                    child: _AttachmentTray(
                      attachments: widget.attachments,
                      onRemove: widget.onRemoveAttachment,
                      removeTooltip: l10n.removeAttachment,
                    ),
                  ),
                // The toolbar row: the tools on the left, the send on the right.
                //
                // The send sits at the **bottom right** of the board, not beside
                // the field: in WeChat the text box is the wide thing at the top
                // and the tools and the send share the line under it.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WeChat.composerBoardPadding,
                    8,
                    WeChat.composerSendRightInset,
                    WeChat.composerSendBottomInset,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // The tools, in WeChat's order: a face, then a file.
                      //
                      // Each is a bare line-drawn glyph, not a button with a
                      // border: they are a row of tools, and a framed button
                      // would read as a form.
                      EmojiPickerButton(
                        onPick: (face) {
                          widget.onEmoji?.call(face);
                          _insertAtCaret(face);
                        },
                        enabled: widget.onEmoji != null,
                        recent: widget.recentEmojis,
                      ),
                      SizedBox(width: WeChat.composerIconGap),
                      ComposerTool(
                        tooltip: l10n.menuSendFile,
                        icon: Icons.folder_outlined,
                        onPressed: widget.onAttach,
                      ),
                      const Spacer(),
                      // The send's colour follows what is in the box, and the
                      // box is the controller's — which does not rebuild the
                      // composer when it changes. So the button listens to the
                      // controller itself rather than to the composer.
                      ListenableBuilder(
                        listenable: widget.message,
                        builder: (context, _) => _SendButton(
                          label: l10n.send,
                          onPressed: _send,
                          enabled: widget.hasSomethingToSend,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The text field, wired so that Enter sends and Shift+Enter breaks the line.
///
/// The bare Enter is the easy half: [WidgetsApp] declares the framework's own
/// text-editing table near the top of the tree, and a [Shortcuts] widget
/// between that table and the field — this one — overrides it. Claiming Enter
/// here is therefore enough to make it a send instead of a line break, and the
/// event is consumed before the table that would have handed it to the IME.
///
/// Shift+Enter is the half that has to be claimed here for a reason worth
/// writing down, because leaving it to the framework looks right and is not.
/// No default table claims it: every one of those activators is a
/// [SingleActivator] with `shift: false`, and a [SingleActivator] matches its
/// modifiers exactly, so Shift+Enter falls past all of them. What answers it is
/// the *engine*: an enter key nobody claimed is translated into the field's
/// `textInputAction` — [TextInputAction.send] here — and that action cannot
/// tell the two chords apart. Left to fall through, Shift+Enter arrives at
/// [TextField.onSubmitted] as a send, which is the bug this table fixes. So the
/// chord is claimed, the break is inserted by hand ([_breakLine]), and the key
/// event is consumed, which is what keeps the engine out of it.
///
/// [TextField.onSubmitted] is wired as well, and is not redundant: it is what
/// answers a soft keyboard's send key — on Android, where this is the only
/// Enter there is — and any platform that reports the action rather than the
/// key. Both roads lead to the same [onSend].
/// The field, which draws **no frame**.
///
/// WeChat's desktop input area writes its text straight onto the white board:
/// no border, no fill of its own, no focus ring. The earlier design drew a
/// hairline box with a brand ring while focused, and that ring was the whole
/// of what said "type here" — which is a thing a caret says better.
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
  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _insertAtCaret(text);
  }

  /// Breaks the line, which is what Shift+Enter means here.
  ///
  /// Inserted by hand rather than left to the field, because the chord is
  /// claimed by the table above — see the doc on this widget for why it has to
  /// be claimed at all.
  void _breakLine() => _insertAtCaret('\n');

  /// Puts [text] where the caret is, following [TextField]'s own rule — the
  /// selection is replaced, and the caret lands after what was inserted —
  /// rather than appending, so that inserting over a selection behaves the way
  /// it does everywhere else on the desktop.
  ///
  /// Written out by hand because both callers stopped the field from doing it
  /// itself: one by claiming Ctrl+V, the other Shift+Enter.
  void _insertAtCaret(String text) {
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
    final colors = WeChatColors.of(context);
    // The field is **borderless**. WeChat's desktop input area has no frame
    // around the text: the board it sits on is white, and the text is written
    // straight onto it. A framed box inside a white board would be a box in a
    // box, and the frame would be a second thing telling the user where to
    // type when the caret already says so.
    //
    // So there is no focus state to draw here either: the previous design's
    // brand hairline and its soft ring both belonged to that frame, and a
    // borderless field has nothing to change colour.
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        return ConstrainedBox(
          // The text area's own height: one line's worth of the reference's
          // 56, and it grows upward from there as more is typed.
          constraints: const BoxConstraints(
            minHeight: WeChat.composerFieldHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WeChat.composerFieldHPadding,
              vertical: WeChat.composerFieldVPadding,
            ),
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): SendMessageIntent(),
                // The same intent under the numpad's key, which is a distinct
                // logical key and would otherwise do nothing on a full-size
                // keyboard.
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    SendMessageIntent(),
                // Shift+Enter, both keys again, and claimed rather than left
                // alone. An enter key that no table answers is translated by the
                // engine into the field's `textInputAction`, which is a send —
                // so "leaving it to the default line break" is what makes
                // Shift+Enter send. See the doc on this widget for the whole of
                // that.
                SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    InsertLineBreakIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
                    InsertLineBreakIntent(),
                // Paste, claimed so that a file or a picture on the clipboard can
                // become a message. Both chords: a desktop has one and a Mac the
                // other, and this is the same one line either way.
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
                  InsertLineBreakIntent: CallbackAction<InsertLineBreakIntent>(
                    onInvoke: (_) {
                      _breakLine();
                      return null;
                    },
                  ),
                  PasteIntoComposerIntent: CallbackAction<PasteIntoComposerIntent>(
                    onInvoke: (_) {
                      // The clipboard is read asynchronously but a key handler
                      // has to answer now: claiming the chord is what stops the
                      // field from pasting text underneath us, and the fallback
                      // runs afterwards.
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
                  // What a soft keyboard's send key reports, and what a test
                  // drives with `TextInputAction.send`. Neither physical Enter
                  // chord reaches it: both are claimed by the [Shortcuts] layer
                  // above, and that is the point of claiming them — this action
                  // cannot tell them apart.
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: TextStyle(
                    // The composer's own size, a step above the dialogs' input
                    // field: what is written here is conversation body, and the
                    // body is [fontSizeBody].
                    fontSize: WeChat.composerFontSize,
                    height: WeChat.lineHeightBody,
                    color: colors.bubbleText,
                    // The face the whole application draws in, and the chain
                    // behind it. The chain is what decides whether a face
                    // typed here comes out in colour: the colour face has to
                    // come before the monochrome one.
                    fontFamily: WeChat.fontFamily,
                    fontFamilyFallback: WeChat.fontFamilyFallback,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    isDense: true,
                    // Every outline the theme would draw, turned off for this
                    // one field. WeChat's input area draws no frame around the
                    // text, so neither does this one.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    // And no minimum height either: the constraint above is what
                    // decides how tall this is, and the theme's 44 would fight
                    // it.
                    constraints: const BoxConstraints(),
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      fontSize: WeChat.composerFontSize,
                      color: colors.secondaryText,
                      fontFamily: WeChat.fontFamily,
                      fontFamilyFallback: WeChat.fontFamilyFallback,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What a bare Enter in the composer means.
class SendMessageIntent extends Intent {
  /// Const so the intent can live in a `const` shortcut table.
  const SendMessageIntent();
}

/// What Shift+Enter in the composer means.
///
/// Its own intent rather than the framework's idea of a line break, because
/// there is no framework intent to claim here: an Enter that nothing claims is
/// answered by the engine with the field's `textInputAction`, and that is a
/// send. Breaking the line is therefore this intent's own job.
class InsertLineBreakIntent extends Intent {
  /// Const so the intent can live in a `const` shortcut table.
  const InsertLineBreakIntent();
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

/// The composer's send button: a small block at the board's bottom right.
///
/// Two states, and the difference between them is the whole of what the button
/// says: **grey** when the box is empty, **green** when there is something to
/// send. A green send on an empty box is a promise that nothing will happen.
///
/// So the button is not a [FilledButton] with a fixed colour — its colour is a
/// function of whether there is anything to send, and the label's ink follows
/// the fill.
///
/// The button is **clickable either way**. Grey is the way WeChat says "there
/// is nothing here to send", and pressing it does nothing — but it is not a
/// disabled control, because a control that stops answering the click
/// swallows the click *and* the focus, and the send is the one thing a user
/// reaches for twice.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.label,
    required this.onPressed,
    required this.enabled,
  });

  final String label;
  final VoidCallback onPressed;

  /// Whether there is anything to send.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return FilledButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (!enabled) return colors.composerSendDisabled;
          return states.contains(WidgetState.hovered)
              ? Color.lerp(colors.brandStrong, Colors.black, 0.12)
              : colors.brandStrong;
        }),
        foregroundColor: WidgetStatePropertyAll(
          enabled ? colors.onBrandStrong : colors.onComposerSendDisabled,
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(WeChat.composerSendRadius),
            ),
          ),
        ),
        // The theme's own padding would be [buttonHPadding] on either side,
        // which makes this button wider than WeChat's; the label's own width
        // plus a little breathing room is what the reference shows.
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size(WeChat.composerSendWidth, WeChat.composerSendHeight),
        ),
        // Shrink-wrapped so the drawn height *is* the reference's 33: the
        // padded default would report 48 — `kMinInteractiveDimension` — while
        // the child stayed at 33, and the board would show a button taller
        // than the one the reference draws.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: WeChat.composerSendFontSize,
            height: 1,
            fontFamily: WeChat.fontFamily,
            fontFamilyFallback: WeChat.fontFamilyFallback,
          ),
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
          _AttachmentTile(
            attachment: attachments[index],
            // Indexed rather than keyed by name: two files can share a name —
            // one picked from two folders — and the tile is positional anyway.
            onRemove: onRemove == null ? null : () => onRemove!(index),
            removeTooltip: removeTooltip,
          ),
      ],
    );
  }
}

/// One staged attachment, as the tray draws it.
///
/// A picture is a **thumbnail** — a square preview of its own bytes, the way
/// the composer shows it. A name beside a picture glyph is what a *file* gets,
/// because a file's name is the only thing it can be previewed by; a picture
/// can be previewed by itself, and a screenshot the user just pasted is
/// identified at a glance by what it shows rather than by `pasted-179…png`.
/// The name is not lost — it is on the thumbnail's tooltip.
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
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
    if (!attachment.isImage) {
      return _AttachmentChip(
        attachment: attachment,
        onRemove: onRemove,
        removeTooltip: removeTooltip,
      );
    }
    final colors = WeChatColors.of(context);
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(WeChat.attachmentThumbRadius),
      child: Tooltip(
        message: attachment.name,
        child: GestureDetector(
          // The same lightbox a sent picture opens into: the tray's preview
          // and the conversation's message are previews of the same bytes, so
          // they answer a click the same way.
          onTap: () => unawaited(
            showImagePreview(
              context,
              path: attachment.path,
              name: attachment.name,
            ),
          ),
          child: Container(
            width: WeChat.attachmentThumbSide,
            height: WeChat.attachmentThumbSide,
            // The grey a hole in the composer is drawn in — the same choice
            // [ImageBubble] makes for its loading picture, and for the same
            // reason: the box has to read as "a picture arriving", not as a
            // white patch on the toolbar.
            color: colors.pageBackground,
            alignment: Alignment.center,
            child: Image(
              // Decoded at the size it is drawn — a tray of five screenshots
              // is five previews, not five full-size decodes sitting in the
              // image cache.
              image: ResizeImage(
                FileImage(File(attachment.path)),
                width:
                    (MediaQuery.devicePixelRatioOf(context) *
                            WeChat.attachmentThumbSide)
                        .round(),
                allowUpscaling: false,
              ),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                size: 20,
                color: colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        picture,
        Positioned(
          top: 2,
          right: 2,
          // A real [IconButton] rather than a tappable glyph: it keeps the
          // focus ring, the keyboard activation and the semantic label that a
          // hand-rolled gesture detector would drop. On the thumbnail the
          // button is the badge itself — a translucent dark circle with a
          // white ×, which is what WeChat draws and what reads on any picture
          // a user can paste, on either theme.
          child: IconButton(
            onPressed: onRemove,
            tooltip: removeTooltip,
            icon: const Icon(Icons.close, size: 12),
            color: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: WeChat.attachmentThumbBadge,
              height: WeChat.attachmentThumbBadge,
            ),
            style: IconButton.styleFrom(backgroundColor: colors.scrim),
          ),
        ),
      ],
    );
  }
}

/// One staged **file**, waiting for 发送 — the tray's chip, for the things that
/// can only be previewed by their name.
///
/// A picture does not come here any more: it is drawn by [_AttachmentTile] as
/// a thumbnail of its own bytes.
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
    final colors = WeChatColors.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 16, color: colors.secondaryText),
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
                style: TextStyle(
                  fontSize: WeChat.fontSizePreview,
                  color: colors.bubbleText,
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
            color: colors.secondaryText,
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
///
/// A picture this machine holds is the one message with no bubble: it is drawn
/// as itself, in the space the bubble would have occupied. Everything else —
/// including a picture whose bytes are not here yet — is a bubble, because
/// everything else has something to say *beside* the content: a name, a
/// progress bar, a decision.
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
    required this.bubbleMaxWidth,
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

  /// How wide this bubble may get.
  ///
  /// Measured once by the conversation, which is where the width of the chat
  /// area is known, and handed to every bubble in the conversation alike — a
  /// cap that each bubble measured for itself would be a cap on the list's
  /// inner width rather than on the chat.
  final double bubbleMaxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final outgoing = view.direction == TransferDirection.outgoing;
    final background = outgoing ? colors.bubbleOut : colors.bubbleIn;

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
                // A right-click on a message is where "show me that file" and
                // "copy that picture" live, and they are offered by the same
                // widget the Transfers list uses so the two surfaces cannot
                // drift apart.
                TransferContextMenu(
                  view: view,
                  // The bubble is skipped only for a picture this machine
                  // holds. See [_drawsBareImage]: a picture with no bytes here
                  // yet keeps the bubble, because the progress bar and the two
                  // answers need somewhere to be.
                  child: _drawsBareImage
                      ? _bareImage(context)
                      : MessageBubbleShape(
                          colour: background,
                          outgoing: outgoing,
                          maxWidth: bubbleMaxWidth,
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
                      style: TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: colors.secondaryText,
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

  /// Whether this message is a picture whose bytes are on this machine, and is
  /// therefore drawn without a bubble.
  ///
  /// The whole of the difference between a picture and every other message: a
  /// path is the picture itself, and a picture is its own content the way a
  /// text is. A name plus a progress bar is what everything *without* a path
  /// has to show instead, and that is a transfer's business — which is what a
  /// bubble looks like.
  bool get _drawsBareImage =>
      view.kind == PayloadKind.image && view.localPath != null;

  /// A picture that is here, drawn as a picture.
  ///
  /// Nothing surrounds it: no fill, no padding, no tail. What is left is what
  /// WeChat leaves — a rounded thumbnail on the side the message came from,
  /// with the avatar beside it and a click into the full-size view.
  ///
  /// The progress bar below it belongs to a *send*: an incoming picture has a
  /// path only once its bytes have landed, so there is nothing left to report
  /// by the time this is drawn. It is bounded by the thumbnail's own bound, so
  /// that a bar drawn under a wide screenshot cannot outrun the picture it is
  /// a bar for.
  Widget _bareImage(BuildContext context) {
    final colors = WeChatColors.of(context);
    // Non-null by [_drawsBareImage], which is what decides this is called.
    final path = view.localPath!;
    final name = view.names.isEmpty ? '' : view.names.first;
    final outgoing = view.direction == TransferDirection.outgoing;
    return Column(
      crossAxisAlignment: outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ImageBubble(
          path: path,
          name: name,
          onOpen: () =>
              unawaited(showImagePreview(context, path: path, name: name)),
        ),
        if (!view.state.isSettled)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: WeChat.imageMaxSide),
              child: LinearProgressIndicator(
                value: view.fraction,
                minHeight: 3,
                backgroundColor: colors.surfaceSunken,
              ),
            ),
          ),
      ],
    );
  }

  /// Everything inside the bubble: the message, its progress, and the answers
  /// an offer needs.
  Widget _contents(BuildContext context, AppLocalizations l10n) {
    final colors = WeChatColors.of(context);
    // A bar belongs under a *file* — an item with bytes still moving across
    // the wire. A text or a face has no bytes on the wire: its body was inside
    // the Offer, so Accept counted it as present the moment the answer went
    // out, and the few frames before its settle are not progress to show.
    // Without this, a sent message flashes a "sending" card with a bar that
    // then resolves into the message itself.
    final showsProgress = _namesAFile && !view.state.isSettled;
    // A file in flight is the one bubble whose width is a decision rather than
    // a consequence. Left alone, the progress bar inside it would expand to
    // every pixel the conversation has left, and a bubble holding a short name
    // would stretch across the whole pane. So the block that belongs to the
    // file — its name, its size, its bar — is drawn at the width the *name*
    // actually takes, and only the answer buttons sit outside that measure.
    final contentWidth = _namesAFile
        ? _transferBubbleWidth(context, l10n)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _body(l10n, contentWidth, colors),
        if (showsProgress)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              width: contentWidth,
              child: LinearProgressIndicator(
                value: view.fraction,
                minHeight: 3,
                // The track is the bubble's own ink, thinned — not a palette
                // grey. It has to read on four fills (`bubbleIn` and `bubbleOut`
                // in each theme) and no single fixed colour does: the received
                // bubble *is* `surfaceSunken` in the light palette, so a track
                // in that colour would vanish inside one, and `divider` is only
                // about ΔRGB 8 off it — and within a step of `bubbleIn` on the
                // dark page, where that bug already existed silently. Derived
                // from the ink, the track is a fixed *distance* from whatever
                // the bubble is, in every combination.
                backgroundColor: _bubbleInk(colors)
                    .withValues(alpha: WeChat.progressTrackAlpha),
              ),
            ),
          ),
        // The one answer a *sender* has: stop. It sits where the receiver's
        // Accept and Refuse sit, because it is the same kind of thing — a
        // question the transfer is asking that only the person looking at the
        // bubble can settle. An offer that was never answered, a payload
        // crawling over a dead link, a file picked by mistake: all of them end
        // here, and the peer is told, so its side settles too.
        if (view.send != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _BubbleAction(
              label: l10n.cancelSend,
              onPressed: () => unawaited(cancelSend(context, view)),
              primary: false,
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

  /// Whether this bubble names a file or a picture still on the wire — the two
  /// kinds whose bubble is drawn to the name's width rather than left to grow.
  bool get _namesAFile =>
      view.kind == PayloadKind.file ||
      (view.kind == PayloadKind.image && view.localPath == null);

  /// How wide a file bubble's fixed block is drawn.
  ///
  /// The width the longest name *actually takes* — measured, not guessed —
  /// with the icon and the gap it shares its row with, floored so that a
  /// three-character name still leaves a progress bar worth reading, and
  /// capped so that a pathological one cannot push the bubble across the pane.
  /// For a file the size line is measured too, because on a short name it is
  /// the wider of the two.
  ///
  /// Always measured as one line, even for a name that will end up on three:
  /// the cap is what *makes* a long name wrap, so the unwrapped width is
  /// precisely what decides whether the cap applies at all. Measuring the
  /// wrapped height instead would be circular — the width would depend on
  /// where the lines break, and the breaks on the width.
  double _transferBubbleWidth(BuildContext context, AppLocalizations l10n) {
    var width = 0.0;
    for (final name in view.names) {
      width = math.max(
        width,
        18 + 6 + _textWidth(context, name, WeChat.fontSizeBody),
      );
    }
    if (view.kind == PayloadKind.file) {
      final sizeLine = l10n.bytesOf(
        formatBytes(view.transferredBytes),
        formatBytes(view.totalBytes),
      );
      width = math.max(
        width,
        _textWidth(context, sizeLine, WeChat.fontSizeMeta),
      );
    }
    return width.clamp(
      WeChat.transferBubbleMinWidth,
      WeChat.transferBubbleMaxWidth,
    );
  }

  /// The width [text] takes on one line at [fontSize], measured the way the
  /// widgets below will draw it.
  double _textWidth(BuildContext context, String text, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// Whether the "kind · state" line belongs under this bubble.
  ///
  /// Only for a file: everything else in a conversation is its own content, and
  /// a receipt for it would be bookkeeping about a message that has no
  /// bookkeeping to show.
  bool get _showsReceipt => view.kind == PayloadKind.file;

  /// Whether this message is a single emoji face, drawn large like a sticker.
  bool get _isEmoji => view.kind == PayloadKind.emoji;

  /// The ink inside this bubble.
  ///
  /// Two near-blacks rather than one. An outgoing bubble is a pale green, and
  /// text on a tinted fill wants that tint's own dark — a neutral black on
  /// green reads faintly blue. A received bubble is white, so it takes the
  /// plain near-black.
  Color _bubbleInk(WeChatColors colors) =>
      view.direction == TransferDirection.outgoing
      ? colors.bubbleOutText
      : colors.bubbleText;

  /// What the message actually says: its words, or the files it carries.
  ///
  /// A picture never arrives here. One this machine holds is drawn by
  /// [_bareImage], outside the bubble this is the inside of, and one it does
  /// not hold is a name and a progress bar, which is [_image].
  ///
  /// [contentWidth] is the measure [_contents] decided on — the width the
  /// names actually take, floored and capped. Given one, the file block is
  /// drawn at exactly that width, so a name that does not fit **wraps** onto
  /// the next line — up to [WeChat.transferNameMaxLines] of them — instead of
  /// stretching the bubble, and only one longer than that cuts off with an
  /// ellipsis (the whole of it is on the tooltip). A name short enough to fit
  /// on one line still takes one line, because the cap was measured from its
  /// own width. Given none — a text message, whose bubble already hugs its
  /// words — the block takes its natural width.
  ///
  /// A message's words are drawn as an ordinary [Text], which the
  /// [SelectionArea] around the message list already makes selectable — a
  /// double-click takes a word, a drag takes a range, exactly as on any other
  /// desktop text. What a secondary click does is decided by the menu wrapped
  /// around this bubble and not by the text: see [TransferContextMenu], which
  /// offers the selected words *and* the message's own lines in one menu, so
  /// that selecting a word does not cost the user 打开所在目录 or 删除.
  Widget _body(
    AppLocalizations l10n,
    double? contentWidth,
    WeChatColors colors,
  ) {
    if (_isEmoji) {
      final text = view.text;
      return Text(
        text == null || text.isEmpty ? '☺' : text,
        style: TextStyle(
          fontSize: WeChat.emojiBubbleFontSize,
          height: 1.2,
          // The chain behind the face, and the reason a face in a bubble is
          // in colour rather than a grey outline: the colour face has to
          // come before the monochrome one.
          fontFamily: WeChat.fontFamily,
          fontFamilyFallback: WeChat.fontFamilyFallback,
        ),
      );
    }
    final text = view.text;
    if (view.kind == PayloadKind.text && text != null) {
      return Text(
        text,
        style: TextStyle(
          fontSize: WeChat.fontSizeBody,
          height: WeChat.lineHeightBody,
          color: _bubbleInk(colors),
        ),
      );
    }
    if (view.kind == PayloadKind.image) return _image(contentWidth, colors);
    final lines = <Widget>[
      for (final name in view.names)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconForKind(view.kind), size: 18, color: _bubbleInk(colors)),
            const SizedBox(width: 6),
            Flexible(
              child: Tooltip(
                message: name,
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: WeChat.transferNameMaxLines,
                  style: TextStyle(
                    fontSize: WeChat.fontSizeBody,
                    height: WeChat.lineHeightBody,
                    color: _bubbleInk(colors),
                  ),
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
            style: TextStyle(
              fontSize: WeChat.fontSizeMeta,
              color: colors.secondaryText,
            ),
          ),
        ),
    ];
    return SizedBox(
      width: contentWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: lines,
      ),
    );
  }

  /// A picture message whose bytes are not here yet.
  ///
  /// One state, and it is a state rather than an instant: an image is filed on
  /// arrival wherever this Device saves received files, so an image with no
  /// path is either on the wire, or waiting for the user to say where it should
  /// go — and in the second case the two answers are drawn below this, inside
  /// the same bubble.
  ///
  /// A name beside a picture glyph is all that can honestly be drawn for
  /// either: it is the same thing a file message draws, because at this point
  /// the two *are* the same thing — a transfer with a name — and the progress
  /// bar underneath says how long that will take. [contentWidth] is the same
  /// measure [_body] draws its file block at.
  ///
  /// A path that no longer reads is not a third case: that is a picture whose
  /// bytes are here, drawn by [_bareImage], and [ImageBubble] falls back to the
  /// name itself when the decode fails.
  Widget _image(double? contentWidth, WeChatColors colors) {
    final name = view.names.isEmpty ? '' : view.names.first;
    return SizedBox(
      width: contentWidth,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 18, color: _bubbleInk(colors)),
          const SizedBox(width: 6),
          Flexible(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                maxLines: WeChat.transferNameMaxLines,
                style: TextStyle(
                  fontSize: WeChat.fontSizeBody,
                  height: WeChat.lineHeightBody,
                  color: _bubbleInk(colors),
                ),
              ),
            ),
          ),
        ],
      ),
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
    final colors = WeChatColors.of(context);
    final style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        primary ? colors.brandStrong : Colors.transparent,
      ),
      // Inside an incoming bubble this sits on the bubble and inside an
      // outgoing one on the bubble green; the outlined variant is drawn in
      // `divider`, which reads as a hairline against both.
      //
      // The filled variant is a *button*, so it wears the action green
      // (`brandStrong`) and the ink defined for it — white on the deep
      // light-mode green, near-black on the bright dark-theme one. The
      // identifying green (`brand`) is deliberately not used here: it is a
      // fill colour for the progress bar and the selected dot, and white on it
      // is 2.4:1, which is why the design never puts white text on it.
      foregroundColor: WidgetStatePropertyAll(
        primary ? colors.onBrandStrong : colors.bubbleText,
      ),
      side: primary
          ? null
          : WidgetStatePropertyAll(BorderSide(color: colors.divider)),
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
        TextStyle(
          fontSize: WeChat.fontSizePreview,
          fontFamily: WeChat.fontFamily,
          fontFamilyFallback: WeChat.fontFamilyFallback,
        ),
      ),
    );
    return TextButton(onPressed: onPressed, style: style, child: Text(label));
  }
}

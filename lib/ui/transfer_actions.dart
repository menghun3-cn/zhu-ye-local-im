import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'clipboard_paste.dart';
import 'controller_scope.dart';
import 'dialogs.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';
import 'reveal.dart';
import 'top_toast.dart';

/// What can be done with a Transfer, in one place.
///
/// Written once here rather than once per surface that draws a Transfer,
/// because every surface that shows one shows the same actions. An offer is
/// answered from wherever the user is looking at it — the Transfers surface
/// lists every Transfer, and a peer's conversation shows the ones between the
/// two of them — so the folder question and the refusal live here; and what a
/// *settled* Transfer offers — showing its file in its folder, and putting a
/// picture back on the clipboard — lives here beside them for the same reason.

/// Answers [view]'s offer by taking it.
///
/// [defaultDirectory] is where received files go — what the user chose in
/// settings, or the platform's own default. Pressing 接收 *is* the answer, so
/// when that folder exists the offer lands in it straight away and nothing
/// else is asked: a second question between the click and the bytes would make
/// the button feel like the first half of one. The folder question is kept
/// only for a Device that has no folder to receive into at all, where assuming
/// one would mean being able to file nothing.
Future<void> acceptOffer(
  BuildContext context,
  LocalTransferController controller,
  TransferView view, {
  String? defaultDirectory,
}) async {
  final offer = view.offer;
  if (offer == null) return;
  final l10n = AppLocalizations.of(context);
  final path = defaultDirectory == null || defaultDirectory.isEmpty
      ? await askForDirectory(
          context,
          title: view.kind == PayloadKind.file
              ? l10n.whereShouldFilesLand
              : l10n.whereShouldThisArrive,
          initial: defaultDirectory,
        )
      : defaultDirectory;
  if (path == null) return;
  // Only the dialog road can outlive the surface behind it; the direct one has
  // not awaited anything. One check covers both.
  if (!context.mounted) return;
  await guarded(context, () async {
    final directory = Directory(path);
    // A folder the user typed may not exist yet; creating it here rather than
    // failing the Transfer is what makes the field usable. The default needs
    // it too: "files go to Downloads/LocalTransfer" has to become true the
    // first time 接收 is pressed.
    directory.createSync(recursive: true);
    await controller.acceptInto(offer, directory);
  });
}

/// Declines [view]'s offer.
void rejectOffer(
  BuildContext context,
  LocalTransferController controller,
  TransferView view,
) {
  final offer = view.offer;
  if (offer == null) return;
  unawaited(guarded(context, () => controller.reject(offer)));
}

/// Whether [view] is a send this Device is still making and can still stop.
///
/// True from the moment an Offer goes out — waiting for an answer counts, which
/// is the whole point: a file picked by mistake should be stoppable during the
/// seconds the peer leaves the question on screen, not only once bytes move.
/// The controller hands the live send out on [TransferView.send] precisely
/// while a stop would change something.
bool canCancelTransfer(TransferView view) => view.send != null;

/// Abandons [view]'s send and tells the peer why.
///
/// Telling the peer is not a courtesy — it is what un-sticks the other side.
/// A receiver whose sender vanished would otherwise sit on a bubble that fills
/// in forever, because a receiver keeps no clock of its own. The send itself
/// goes out through the same quiet road every ending takes: a Transfer is over
/// either way, so a link that died before the news arrived is not a second
/// error for the user to read.
Future<void> cancelSend(BuildContext context, TransferView view) {
  final send = view.send;
  if (send == null) return Future.value();
  return guarded(context, send.cancel);
}

/// Whether [view] names a file on this machine whose folder can be opened.
///
/// True for a file this Device received, for one it sent, and for an image
/// either way — every case in which "where is it" has an answer. False while a
/// file offer is still waiting, because nothing has been written anywhere yet,
/// and false for text, which is not a file at all.
bool canRevealTransfer(TransferView view) => view.localPath != null;

/// Shows [view]'s file in this machine's file manager.
///
/// A failure is said out loud rather than raised: a platform with no file
/// manager, and a path whose file has since been moved or deleted, are both
/// ordinary — neither is an error the user needs an exception for, and the
/// sentence is easier to act on than a stack trace.
Future<void> revealTransfer(BuildContext context, TransferView view) async {
  final path = view.localPath;
  if (path == null) return;
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  // The one call goes through the seam, so a widget test can assert the folder
  // it was asked for without an Explorer window opening on the test machine.
  if (await RevealResolution.revealer.reveal(path)) return;
  if (overlay == null) return;
  await TopToast.showIn(overlay, l10n.cannotOpenFolder);
}

/// Whether [view] is a picture whose bytes are on this machine and can
/// therefore be put on the clipboard.
///
/// An image and not a file, because "copy" means two different things to the
/// two of them: a picture copied in Explorer is a picture, and a spreadsheet
/// copied here would be a file list. False for an image still in flight — there
/// is nothing to read yet — and false for a picture whose local copy has since
/// been deleted, which is discovered on the read rather than guessed at here.
bool canCopyImage(TransferView view) =>
    view.kind == PayloadKind.image && view.localPath != null;

/// Puts [view]'s picture on this machine's clipboard.
///
/// The bytes are read back from disk rather than carried in memory: a
/// conversation holds however many pictures the user has exchanged, and the one
/// being copied is the one the user pointed at, which is exactly the one the
/// app does not have to keep decoded.
///
/// A failure is said out loud, for the same reason a failed reveal is: the
/// platforms disagree about whether an app may write its own clipboard at all,
/// and "nothing happened" is not something a user can act on. A success says
/// nothing — the pasted picture is the confirmation.
Future<void> copyTransferImage(BuildContext context, TransferView view) async {
  final path = view.localPath;
  if (path == null) return;
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } on Object {
    // The file the Transfer points at is not there any more. That is a copy
    // that cannot happen rather than one that failed halfway.
    if (overlay == null) return;
    await TopToast.showIn(overlay, l10n.cannotCopyImage);
    return;
  }
  // Through the seam, so a widget test can assert the bytes that reached the
  // clipboard without a `testWidgets` body ever touching a platform channel.
  if (await PasteResolution.paste.writeImage(bytes)) return;
  if (overlay == null) return;
  await TopToast.showIn(overlay, l10n.cannotCopyImage);
}

/// Whether [view] is a text message whose words can be put on the clipboard.
///
/// Text and not "anything with something to copy", because a file's body is a
/// name and a picture's is pixels: what a person wants from a message that
/// *says* something is the sentence, and the two other kinds have their own
/// answers below.
bool canCopyText(TransferView view) =>
    view.kind == PayloadKind.text && view.text != null;

/// Puts [view]'s words on this machine's clipboard.
///
/// Through Flutter's own `Clipboard` rather than through [ClipboardPaste]: text
/// is the one thing every platform's clipboard channel reads and writes, which
/// is the whole reason the seam exists for everything else.
///
/// A failure is said out loud for the same reason a failed picture copy is: a
/// copy that did not happen and says nothing is indistinguishable from one that
/// did, and the user pastes nothing and does not know why.
Future<void> copyTransferText(BuildContext context, TransferView view) async {
  final text = view.text;
  if (text == null) return;
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on Object {
    if (overlay == null) return;
    await TopToast.showIn(overlay, l10n.cannotCopyText);
  }
}

/// The words currently selected in the conversation, for the menus in it.
///
/// [SelectableRegionState] is reachable only by the widget that created it —
/// its `SelectionArea` holds the key privately and there is no `of` — so the
/// selection has to be *pushed* down to whoever wants to read it rather than
/// pulled up from it. That is what this is: the conversation's `SelectionArea`
/// reports every change into here ([SelectionArea.onSelectionChanged]), and the
/// menu on a message reads it from here.
///
/// An [InheritedWidget] rather than a callback passed down per bubble, because
/// a bubble is built by a `ListView` and would need the value threaded through
/// the builder for no reason: the selection is a fact about the conversation,
/// not about a message.
///
/// Not a [ChangeNotifier]: nothing rebuilds on a change. The only reader is a
/// right-click, which reads it once, at the moment the menu is built.
class MessageSelection extends InheritedWidget {
  /// Publishes [text] — what is selected, or null for nothing — to [child].
  const MessageSelection({super.key, required this.text, required super.child});

  /// What the conversation has selected, or null when it has nothing.
  ///
  /// The *plain text* of the selection rather than a range or a list of nodes:
  /// the only thing anyone does with it is put it on the clipboard, and the
  /// text is what that takes. A selection spanning two messages arrives here as
  /// one string, which is exactly the answer a copy should give.
  final String? text;

  /// Whether there is anything selected.
  bool get hasSelection => text != null && text!.isNotEmpty;

  /// What is selected above [context], or null when nothing is.
  ///
  /// Null for a surface with no conversation on it — the Transfers list draws
  /// the same menus over text nobody can select — which is a real answer there
  /// and not an error.
  static MessageSelection? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageSelection>();

  @override
  bool updateShouldNotify(MessageSelection oldWidget) => text != oldWidget.text;
}

/// Offers what can be done with a Transfer, on a right-click.
///
/// The answers an *offer* needs — accept and refuse — are buttons in the open,
/// because a decision behind a menu is a decision nobody finds. These are the
/// other kind of action: things the user wants once the question is over and
/// the bytes are somewhere on disk, plus the one thing that is wanted from a
/// message of any kind at all — taking it off the screen. A right-click keeps
/// them reachable without putting a toolbar on a message.
///
/// Which of the byte-actions a given Transfer offers is decided by the
/// predicates above rather than by the caller, so the conversation, the
/// Transfers list and any surface added later cannot each draw a different menu
/// for the same message. Deleting is not one of them: it is offered by
/// everything, settled or not, which is why the menu is never empty and the
/// right-click is always intercepted.
///
/// ## Words, and selecting them
///
/// The bubble's words *are* selectable now — the message list is wrapped in a
/// [SelectionArea], so a double-click takes a word and a drag takes a range,
/// which is what a user expects of any text. That puts this menu in the place
/// the platform's own select/copy toolbar would have been, and rather than
/// letting the two fight, this widget **is** that toolbar: when there is a
/// selection it offers 复制 and 全选 *in addition to* the message's own lines,
/// and the copy takes the selection.
///
/// The alternative — letting `SelectionArea` draw its own menu over the words —
/// would take the message's lines away exactly where a user most wants them: a
/// right-click on the text of a file message would open a copy toolbar with no
/// 打开所在文件夹 and no 删除 on it. One menu that knows about both is what keeps
/// every action reachable from one click.
///
/// For a text message the whole of it can also be copied in one line, without
/// drag-selecting first; that line stays whatever the selection is, because
/// "copy this message" and "copy these three words" are different requests and a
/// menu that silently switched between them would be a menu nobody can predict.
///
/// [child] is wrapped rather than replaced — the picture and the card are what
/// is being pointed at, and they have to go on drawing exactly as they did.
class TransferContextMenu extends StatelessWidget {
  /// Wraps [child] with the actions [view] offers.
  const TransferContextMenu({
    super.key,
    required this.view,
    required this.child,
  });

  /// The Transfer being pointed at.
  final TransferView view;

  /// What is drawn, and what the pointer has to be over.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Every message offers at least one thing, because deleting one is
    // something a user can want from any of them — including a message that
    // never moved a byte. So the right-click is always intercepted, and the
    // guard that used to stand here — a handler that opened an empty menu would
    // have swallowed the right-click that selects a name to copy — has no case
    // left to apply to.
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_open(context, details.globalPosition)),
      child: child,
    );
  }

  /// Opens the menu where the pointer was.
  Future<void> _open(BuildContext context, Offset at) async {
    final l10n = AppLocalizations.of(context);
    // Read once, before the await: the surface behind the menu can be gone by
    // the time one of these is chosen, and the list must not change under the
    // menu the user is looking at either.
    final reveal = canRevealTransfer(view);
    final copyImage = canCopyImage(view);
    final copyText = canCopyText(view);
    final cancel = canCancelTransfer(view);
    // The controller is read here for the same reason, and `ControllerScope.of`
    // throws rather than returning null when the scope above is gone — which is
    // why it is asked before the menu opens rather than after a line is chosen.
    final controller = ControllerScope.of(context);
    // The selection, likewise read before the menu opens: choosing a line
    // collapses the selection, so a handler that asked afterwards would find
    // nothing. Null when this surface has no selectable conversation on it —
    // the Transfers list — or when the user has not selected anything.
    final selection = MessageSelection.maybeOf(context);
    final selected = selection?.hasSelection ?? false ? selection!.text : null;
    final hasSelection = selected != null && selected.isNotEmpty;
    // The overlay is what `showMenu` lays the menu out inside, so its size is
    // the one the margins below have to be measured against.
    final overlay = Overlay.of(context).context.findRenderObject();
    final size = overlay is RenderBox
        ? overlay.size
        : MediaQuery.sizeOf(context);
    final chosen = await showMenu<String>(
      context: context,
      // Anchored at the pointer, with what is left of the overlay given as the
      // right and bottom margins — which is how the menu is kept inside the
      // window rather than half off its edge.
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        size.width - at.dx,
        size.height - at.dy,
      ),
      items: [
        // Selection first, and only while there is one. This is the line the
        // platform's own toolbar would have put here, and it leads because the
        // user who has just dragged across a sentence is looking for exactly
        // it.
        if (hasSelection)
          _item(
            value: _copySelectionAction,
            icon: Icons.content_copy_outlined,
            label: l10n.copySelection,
          ),
        if (cancel)
          _item(
            value: _cancelAction,
            icon: Icons.close,
            label: l10n.cancelSend,
          ),
        if (reveal)
          _item(
            value: _revealAction,
            icon: Icons.folder_open_outlined,
            label: l10n.openContainingFolder,
          ),
        if (copyImage)
          _item(
            value: _copyAction,
            icon: Icons.content_copy_outlined,
            label: l10n.copyImage,
          ),
        // The whole message, whatever is selected. Kept as its own line rather
        // than folded into 复制 above, because the two ask different questions:
        // this one means "the message" and that one means "the words I dragged
        // over", and collapsing them would make the menu's answer depend on a
        // selection the user cannot see while the menu is open.
        if (copyText && !hasSelection)
          _item(
            value: _copyTextAction,
            icon: Icons.content_copy_outlined,
            label: l10n.copyText,
          ),
        // Last, and unconditional. Everything above reaches for the bytes
        // somewhere on this machine or stops them moving; this is the line that
        // takes the message itself away, and it is the one thing a user can
        // want from a message of any kind.
        _item(
          value: _deleteAction,
          icon: Icons.delete_outline,
          label: l10n.deleteMessage,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (chosen) {
      case _copySelectionAction:
        await _copySelection(selected);
      case _cancelAction:
        await cancelSend(context, view);
      case _revealAction:
        await revealTransfer(context, view);
      case _copyAction:
        await copyTransferImage(context, view);
      case _copyTextAction:
        await copyTransferText(context, view);
      case _deleteAction:
        await controller.deleteMessage(view);
    }
  }

  /// Puts the selected words on the clipboard.
  ///
  /// The text came from [MessageSelection] — the conversation's `SelectionArea`
  /// pushes every change into it, because a [SelectableRegionState] is not
  /// reachable from here: `SelectionArea` keeps its key private and offers no
  /// `of`.
  ///
  /// Through Flutter's own `Clipboard`, like [copyTransferText], and silent on
  /// failure for the same reason: a copy that says nothing on success has to say
  /// something on failure, and a user who pastes nothing and hears nothing has
  /// no way to tell which happened.
  Future<void> _copySelection(String? text) async {
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// One line of the menu.
  ///
  /// A row rather than a `ListTile`: a menu item is one line, and a tile brings
  /// its own padding, its own tap target and its own ripple.
  PopupMenuItem<String> _item({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

/// What a menu line answers with.
///
/// One value per line rather than a nullable, because `showMenu` answers with
/// what was chosen and `null` is *also* what a dismissed menu answers with — so
/// "nothing was chosen" has to be told apart from "the line that was chosen
/// happens to be first".
const String _copySelectionAction = 'copy-selection';
const String _cancelAction = 'cancel';
const String _revealAction = 'reveal';
const String _copyAction = 'copy';
const String _copyTextAction = 'copy-text';
const String _deleteAction = 'delete';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app.dart';
import '../../core/link_transfer/link_transfer.dart';
import '../clipboard_paste.dart';
import '../controller_scope.dart';
import '../l10n/generated/app_localizations.dart';
import '../pickers.dart';
import '../top_toast.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// A page for sharing files via download links without needing a peer connection.
///
/// This allows users to select local files — or drop them onto the page — and
/// generate a temporary HTTP link that anyone on the network can use to
/// download them without installing the app. One pick or drop is one share:
/// a single link to a list page, plus a QR code encoding the same link.
/// Shares expire after 30 minutes.
class ShareByLinkPage extends StatefulWidget {
  const ShareByLinkPage({super.key});

  @override
  State<ShareByLinkPage> createState() => _ShareByLinkPageState();
}

class _ShareByLinkPageState extends State<ShareByLinkPage> {
  final List<_Share> _shares = [];
  bool _isLoading = false;

  /// Whether a drag from outside the window is over the page right now.
  bool _dropping = false;

  /// Picks files and creates a share link for them.
  Future<void> _pickAndShare() async {
    final chosen = await PickerResolution.picker.files();
    if (!mounted || chosen.isEmpty) return;
    await _sharePaths([for (final file in chosen) file.path]);
  }

  /// Creates one share link covering [paths].
  ///
  /// The single road in for both the picker and a drop: what a path turns out
  /// to be — a real file or a directory that cannot be served — is decided
  /// here, exactly once. A drop of nothing but folders reports the same
  /// "nothing to share" as picking nothing at all would have.
  Future<void> _sharePaths(List<String> paths) async {
    setState(() => _isLoading = true);

    try {
      final linkTransfer = LinkTransfer.instance;
      if (!linkTransfer.isRunning) {
        await linkTransfer.start();
      }

      if (!mounted) return;

      // The addresses peers were heard at tell the link server which of this
      // machine's interfaces a recipient can reach — LAN or VPN.
      final peerAddresses = shareAddressHints(
        ControllerScope.of(context).discoveredPeers,
      );

      final files = [
        for (final path in paths)
          // A directory has a path but no bytes of its own; the share page
          // serves files, so a dropped folder is filtered out here rather
          // than failing later inside the server.
          if (File(path).existsSync()) (path: path, name: fileNameOf(path)),
      ];
      final link = await linkTransfer.createShare(
        files,
        peerAddresses: peerAddresses,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        if (link != null) {
          _shares.add(
            _Share(
              link: link,
              fileNames: [for (final file in files) file.name],
              createdAt: DateTime.now(),
            ),
          );
        }
      });

      if (link == null) {
        final l10n = AppLocalizations.of(context);
        await TopToast.show(context, l10n.shareByLinkNoFiles);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final l10n = AppLocalizations.of(context);
      await TopToast.show(context, '${l10n.shareByLinkFailed}: $e');
    }
  }

  /// Copies a link to the clipboard.
  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await TopToast.show(context, l10n.shareByLinkCopied);
  }

  /// Copies [share]'s QR code to the clipboard as an image.
  ///
  /// The picture is whatever the card is showing: the boundary is rendered
  /// at four times its size so the paste lands crisp in a chat window rather
  /// than blurry at 84 pixels. `writeImage` answers a bool because a
  /// clipboard that refuses the write — Android in the background, a platform
  /// the plugin does not know — is an ordinary outcome, reported as one.
  Future<void> _copyQr(_Share share) async {
    final boundary =
        share.qrKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;

    final l10n = AppLocalizations.of(context);
    try {
      final image = await boundary.toImage(pixelRatio: 4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('QR encode failed');

      final copied = await PasteResolution.paste.writeImage(
        bytes.buffer.asUint8List(),
      );
      if (!mounted) return;
      await TopToast.show(
        context,
        copied ? l10n.shareByLinkCopiedQr : l10n.shareByLinkCopyQrFailed,
      );
    } on Object {
      if (!mounted) return;
      await TopToast.show(context, l10n.shareByLinkCopyQrFailed);
    }
  }

  /// Removes a share from the list.
  void _removeShare(int index) {
    setState(() => _shares.removeAt(index));
  }

  /// The frame drawn over the page while a drag is in progress.
  ///
  /// A drop with no visible answer is the worst kind: the user is holding a
  /// file over a window that looks exactly as it did before, and has no way
  /// to tell whether letting go will do anything.
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
              Icon(Icons.add_link, color: colors.brand, size: 28),
              const SizedBox(height: 8),
              Text(
                l10n.shareByLinkDropHint,
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

    return Column(
      children: [
        // Header with share button
        Padding(
          padding: WeChat.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.shareByLinkDesc,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: WeChatColors.of(context).secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isLoading ? null : _pickAndShare,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_link),
                label: Text(l10n.shareByLink),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Shares list — the whole region is a drop target, so files can land
        // anywhere on it, not only on the empty state.
        Expanded(
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dropping = true),
            onDragExited: (_) => setState(() => _dropping = false),
            onDragDone: (detail) {
              setState(() => _dropping = false);
              unawaited(
                _sharePaths([for (final file in detail.files) file.path]),
              );
            },
            child: Stack(
              children: [
                _shares.isEmpty
                    ? Center(child: HintText(l10n.shareByLinkEmpty))
                    : ListView.builder(
                        padding: WeChat.pagePadding,
                        itemCount: _shares.length,
                        itemBuilder: (context, index) {
                          final share = _shares[index];
                          return _ShareCard(
                            share: share,
                            onCopyLink: () => _copyLink(share.link),
                            onCopyQr: () => _copyQr(share),
                            onRemove: () => _removeShare(index),
                          );
                        },
                      ),
                if (_dropping) _dropOverlay(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One share: a link to a list page, its QR code, and the files it covers.
class _Share {
  _Share({
    required this.link,
    required this.fileNames,
    required this.createdAt,
  });

  final String link;
  final List<String> fileNames;
  final DateTime createdAt;

  /// Keys the QR's [RepaintBoundary], which is what "copy the QR code" reads
  /// pixels from.
  final GlobalKey qrKey = GlobalKey();

  /// Whether this share has expired (30 minutes).
  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 30);
}

/// The card one share is drawn as: what it holds, the two ways to hand it
/// over — link and QR — and the way to take it back.
class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.share,
    required this.onCopyLink,
    required this.onCopyQr,
    required this.onRemove,
  });

  final _Share share;
  final VoidCallback onCopyLink;
  final VoidCallback onCopyQr;
  final VoidCallback onRemove;

  /// Opens the QR code large enough to screenshot or show across a room.
  ///
  /// The card's QR is 84 pixels — scannable at arm's length and useless as a
  /// picture. The dialog renders the same link at a size a phone camera (or a
  /// screenshot) can actually use, with the copy action one tap away.
  void _showQrDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 280,
              height: 280,
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: share.link,
                size: 256,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onCopyQr();
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(l10n.shareByLinkCopyQr),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_zip, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.shareByLinkFileCount(share.fileNames.length),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: WeChat.fontSizeTitle,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (share.fileNames.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      share.fileNames.join(', '),
                      style: TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: colors.secondaryText,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  SelectableText(
                    share.link,
                    style: TextStyle(
                      fontSize: WeChat.fontSizeMeta,
                      color: colors.secondaryText,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.shareByLinkExpiry,
                    style: TextStyle(
                      fontSize: WeChat.fontSizeMeta,
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: onCopyLink,
                        tooltip: l10n.shareByLinkCopy,
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code, size: 18),
                        onPressed: onCopyQr,
                        tooltip: l10n.shareByLinkCopyQr,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: onRemove,
                        tooltip: l10n.deleteMessage,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // The QR encodes the same link the text above carries — scanning
            // it opens the identical page, for a recipient whose chat client
            // turns a QR into a tap but mangles a pasted URL. Tapping it
            // opens the same code large, for a screenshot or a second screen.
            Tooltip(
              message: l10n.shareByLinkQrEnlarge,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showQrDialog(context),
                  child: RepaintBoundary(
                    key: share.qrKey,
                    child: Container(
                      width: 84,
                      height: 84,
                      color: Colors.white,
                      padding: const EdgeInsets.all(6),
                      child: QrImageView(
                        data: share.link,
                        size: 72,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

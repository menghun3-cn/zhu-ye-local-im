import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/link_transfer/link_transfer.dart';
import '../l10n/generated/app_localizations.dart';
import '../pickers.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// A page for sharing files via download links without needing a peer connection.
///
/// This allows users to select local files and generate temporary HTTP links
/// that anyone on the network can use to download the files without installing
/// the app. Links expire after 30 minutes.
class ShareByLinkPage extends StatefulWidget {
  const ShareByLinkPage({super.key});

  @override
  State<ShareByLinkPage> createState() => _ShareByLinkPageState();
}

class _ShareByLinkPageState extends State<ShareByLinkPage> {
  final List<_SharedLink> _links = [];
  bool _isLoading = false;

  /// Picks files and creates download links for them.
  Future<void> _pickAndShare() async {
    setState(() => _isLoading = true);

    try {
      final chosen = await PickerResolution.picker.files();
      if (!mounted || chosen.isEmpty) return;

      final linkTransfer = LinkTransfer.instance;
      if (!linkTransfer.isRunning) {
        await linkTransfer.start();
      }

      if (!mounted) return;

      final newLinks = <_SharedLink>[];
      for (final file in chosen) {
        final path = file.path;
        if (!File(path).existsSync()) continue;

        final link = await linkTransfer.createLink(path, fileName: file.name);
        if (link != null) {
          newLinks.add(
            _SharedLink(
              fileName: file.name,
              filePath: path,
              link: link,
              createdAt: DateTime.now(),
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _links.addAll(newLinks);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.shareByLinkFailed}: $e')));
    }
  }

  /// Copies a link to the clipboard.
  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.shareByLinkCopied)));
  }

  /// Removes a link from the list.
  void _removeLink(int index) {
    setState(() => _links.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);

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
                  color: colors.secondaryText,
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
        // Links list
        Expanded(
          child: _links.isEmpty
              ? Center(child: HintText(l10n.shareByLinkEmpty))
              : ListView.builder(
                  padding: WeChat.pagePadding,
                  itemCount: _links.length,
                  itemBuilder: (context, index) {
                    final link = _links[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.insert_drive_file, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    link.fileName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: WeChat.fontSizeTitle,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () => _copyLink(link.link),
                                  tooltip: l10n.shareByLinkCopy,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  onPressed: () => _removeLink(index),
                                  tooltip: l10n.deleteMessage,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              link.link,
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A shared file link with metadata.
class _SharedLink {
  const _SharedLink({
    required this.fileName,
    required this.filePath,
    required this.link,
    required this.createdAt,
  });

  final String fileName;
  final String filePath;
  final String link;
  final DateTime createdAt;

  /// Whether this link has expired (30 minutes).
  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 30);
}

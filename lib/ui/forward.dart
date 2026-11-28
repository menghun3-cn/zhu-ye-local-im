import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'labels.dart';
import 'l10n/generated/app_localizations.dart';
import 'presence.dart';
import 'top_toast.dart';
import 'wechat/bubble.dart';
import 'wechat/theme.dart';
import 'widgets.dart';

/// Forwards [views] to the Device the user picks, one Transfer per message.
///
/// This is the one road every forward takes — the menu's 转发 on a single
/// message and the selection bar's 转发 on a batch — so the pick, the order
/// and the failure count are decided once here rather than per surface.
///
/// Only [TransferView.canForward] messages are sent: the caller may hand over
/// a selection that includes a multi-item transfer or a draft, and those are
/// filtered out rather than failing one by one. [views] is expected in the
/// order the messages should arrive; the caller sorts, this does not.
///
/// Returns whether a target was picked and the send was attempted, so a
/// caller holding a selection mode can tell "the user backed out" from "the
/// forwards went out" and keep the ticks in the first case.
Future<bool> forwardToPickedDevice(
  BuildContext context,
  LocalTransferController controller,
  List<TransferView> views,
) async {
  final sendable = [
    for (final view in views)
      if (view.canForward) view,
  ];
  if (sendable.isEmpty) return false;
  // Taken before the dialog's await, for the same reason `guarded` takes its
  // strings early: the surface that asked may be gone by the time the pick
  // comes back, and the toast still has somewhere to be drawn.
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final target = await showDialog<Fingerprint>(
    context: context,
    builder: (dialogContext) => _ForwardTargetDialog(controller: controller),
  );
  // No pick is a backed-out dialog, not a failure: nothing was sent and
  // nothing is owed, so the caller's selection stays exactly as it was.
  if (target == null) return false;

  final failed = await controller.forwardMessages(sendable, to: target);
  // The toast is the whole report a partial batch gets: every message that
  // could not go — a file moved since it arrived, a kind with nothing left
  // to send — is counted rather than named, because the ones that did go are
  // already visible as new messages in the target's conversation.
  if (failed > 0 && overlay != null) {
    await TopToast.showIn(overlay, l10n.forwardFailedCount(failed));
  }
  return true;
}

/// The Devices a forward can go to, as a dialog answers with one Fingerprint.
///
/// Every peer is listed, offline ones included: a forward to a Device that is
/// away is kept as an unsent draft owed to it — the same thing a message
/// typed while it was offline becomes — so "not connected right now" is not
/// a reason to leave it out. Connected first and then by name, the order the
/// conversation list already teaches.
///
/// The rows are drawn the way the conversation list draws them — the same
/// Avatar, the same name-over-address reading, the same connection line —
/// because a forward target *is* a conversation, and a picker that described
/// the same Devices differently would make the user translate between the
/// two lists to know which row they are picking. A search field sits on top
/// for the case the list was built for: enough Devices that scrolling stops
/// being a way to find one.
class _ForwardTargetDialog extends StatefulWidget {
  const _ForwardTargetDialog({required this.controller});

  final LocalTransferController controller;

  @override
  State<_ForwardTargetDialog> createState() => _ForwardTargetDialogState();
}

class _ForwardTargetDialogState extends State<_ForwardTargetDialog> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Whether [peer] answers [query], matched against what its row shows.
  ///
  /// The name and the address are the two strings a row prints, so they are
  /// the two a search looks through — a user who remembers "the Windows
  /// machine" types the alias, and one who remembers "the one at .42" types
  /// the address.
  bool _matches(PeerView peer, String query) {
    return peer.displayName.toLowerCase().contains(query) ||
        (peer.address?.toLowerCase().contains(query) ?? false);
  }

  /// The line under the name: the address when the name is not already it,
  /// the Session detail, and the presence word.
  ///
  /// [describePeerConnection] carries the port but says nothing about
  /// reachability — in the conversation header that moved to a word beside
  /// the title, and this row has no title line for it to move to, so the
  /// state stays here. The address leads when the peer has a name of its
  /// own: a named peer's title is its alias, so two machines both called
  /// "DESKTOP" would read identically without it. When the peer has no name
  /// of its own the display name already *is* the address, and repeating it
  /// would say the same fact twice.
  String _subtitleFor(PeerView peer, AppLocalizations l10n) {
    final parts = <String>[
      ?describePeerConnection(peer, l10n),
      labelForPresenceState(peer.presence, l10n),
    ];
    final address = peer.address;
    if (address != null && address.isNotEmpty && peer.hasRealAlias) {
      parts.insert(0, address);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final query = _search.text.trim().toLowerCase();
    final peers = [...widget.controller.peers]
      ..sort((a, b) {
        if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    final visible = query.isEmpty
        ? peers
        : [
            for (final peer in peers)
              if (_matches(peer, query)) peer,
          ];
    return AlertDialog(
      title: Text(l10n.forwardTo),
      content: SizedBox(
        width: 380,
        child: peers.isEmpty
            ? Text(l10n.noDevicesToForward)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: WeChat.fontSizeInput),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: colors.surfaceSunken,
                      hintText: l10n.searchForwardTargets,
                      prefixIcon: const Icon(Icons.search, size: 19),
                      suffixIconConstraints: const BoxConstraints(maxWidth: 96),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: l10n.clearSearch,
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          WeChat.controlRadius,
                        ),
                        borderSide: BorderSide(color: colors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          WeChat.controlRadius,
                        ),
                        borderSide: BorderSide(color: colors.brandStrong),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Bounded so a long peer list scrolls inside the dialog
                  // instead of sizing it: an unbounded shrinkWrap list asks
                  // for every row's height at once, which is exactly the
                  // case this picker exists for.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: visible.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: HintText(l10n.forwardTargetNoMatch),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final peer = visible[index];
                              return _ForwardTargetRow(
                                peer: peer,
                                subtitle: _subtitleFor(peer, l10n),
                                onTap: () =>
                                    Navigator.of(context).pop(peer.fingerprint),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

/// One pickable Device in the forward dialog.
///
/// Drawn like a conversation row — avatar, name over a supporting line, a
/// hover wash — rather than as a Material [ListTile], whose selected and
/// hover colours come from the colour scheme and not from this design's
/// palette. The same reason the conversation list's own row gives for
/// existing applies here: a row that looks like the list it is picking from
/// is the clearest possible answer to "which one is this".
class _ForwardTargetRow extends StatefulWidget {
  const _ForwardTargetRow({
    required this.peer,
    required this.subtitle,
    required this.onTap,
  });

  final PeerView peer;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_ForwardTargetRow> createState() => _ForwardTargetRowState();
}

class _ForwardTargetRowState extends State<_ForwardTargetRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final peer = widget.peer;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? colors.listHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: WeChat.conversationRowPadding,
            vertical: WeChat.conversationRowVPadding,
          ),
          child: Row(
            children: [
              Avatar(
                name: peer.displayName,
                seed: peer.fingerprint.hex,
                label: peer.avatarLabel,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      peer.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: WeChat.fontSizeTitle,
                        color: colors.bubbleText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: WeChat.fontSizePreview,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

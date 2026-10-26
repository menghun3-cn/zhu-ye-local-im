import 'package:flutter/material.dart';

import '../app/app.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';
import 'wechat/bubble.dart';
import 'wechat/theme.dart';

/// How a peer's [PeerPresence] reads in the conversation list.
String labelForPeerPresence(PeerView peer, AppLocalizations l10n) {
  switch (peer.presence) {
    case PeerPresence.online:
      return l10n.presenceOnline;
    case PeerPresence.connecting:
      return l10n.presenceConnecting;
    case PeerPresence.offline:
      final lastSeen = peer.lastSeen;
      return lastSeen == null
          ? l10n.presenceOffline
          : l10n.presenceOfflineWithLastSeen(describeLastSeen(lastSeen, l10n));
  }
}

/// The global summary of every peer the controller currently knows about.
String describePresenceCounts(PresenceCounts counts, AppLocalizations l10n) {
  if (counts.isEmpty) return l10n.presenceSummaryEmpty;
  return [
    l10n.presenceOnlineCount(counts.online),
    if (counts.connecting > 0) l10n.presenceConnectingCount(counts.connecting),
    l10n.presenceOfflineCount(counts.offline),
  ].join(' · ');
}

/// A small state mark used beside an avatar and in the global summary.
///
/// The mark is deliberately decorative: every place that draws it also draws
/// the state in words, so a reader who cannot distinguish the colours still
/// gets the same fact.
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    required this.presence,
    this.size = 9,
    this.ringColor,
  });

  final PeerPresence presence;
  final double size;

  /// The surface the dot is sitting on, used to separate it from an avatar or
  /// to leave the middle empty for [PeerPresence.connecting].
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final ink = presence == PeerPresence.offline
        ? colors.secondaryText
        : colors.brandStrong;
    final ring = ringColor ?? colors.sidebarBackground;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: presence == PeerPresence.connecting ? ring : ink,
        shape: BoxShape.circle,
        border: Border.all(
          color: presence == PeerPresence.connecting ? ink : ring,
          width: 1.5,
        ),
      ),
    );
  }
}

/// An avatar with the peer's presence mark in its lower-right corner.
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({
    super.key,
    required this.name,
    required this.seed,
    required this.presence,
    this.label,
    this.size = WeChat.avatar,
  });

  final String name;
  final String seed;
  final PeerPresence presence;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(name: name, seed: seed, label: label, size: size),
          Positioned(
            right: -1,
            bottom: -1,
            child: PresenceDot(
              presence: presence,
              ringColor: colors.sidebarBackground,
            ),
          ),
        ],
      ),
    );
  }
}

/// The always-visible online/offline summary for the application chrome.
///
/// It is one widget in two shapes: a narrow rail stack on a wide window, and a
/// single strip above the bottom navigation bar on a narrow one. The two share
/// the same counts and the same words, so they cannot disagree.
class ConnectionSummary extends StatelessWidget {
  const ConnectionSummary({
    super.key,
    required this.counts,
    required this.onTap,
    this.compact = false,
  });

  final PresenceCounts counts;
  final VoidCallback onTap;

  /// Whether this is the narrow rail stack rather than the wide strip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final summary = describePresenceCounts(counts, l10n);
    final background = compact
        ? colors.sidebarBackground
        : colors.toolbarBackground;
    final body = compact
        ? _compactBody(context, l10n, background)
        : _wideBody(context, l10n, background);
    // The summary is a chrome control that hands work to the Devices surface,
    // exactly like the update entry under the rail. A `TextButton` keeps its
    // focus ring, keyboard activation and tooltip semantics, and it participates
    // in the same tab order as the destinations — so the summary does not catch
    // the first Tab that used to land on 会话.
    return Semantics(
      button: true,
      label: summary,
      hint: l10n.presenceOpenDevices,
      child: Tooltip(
        message: '$summary\n${l10n.presenceOpenDevices}',
        child: TextButton(
          onPressed: onTap,
          focusNode: FocusNode(skipTraversal: true),
          style: TextButton.styleFrom(
            foregroundColor: colors.secondaryText,
            backgroundColor: background,
            padding: compact
                ? const EdgeInsets.symmetric(vertical: 4)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: compact
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeChat.controlRadius),
                  )
                : const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            alignment: Alignment.center,
            overlayColor: colors.listHover,
          ),
          child: body,
        ),
      ),
    );
  }

  Widget _compactBody(
    BuildContext context,
    AppLocalizations l10n,
    Color background,
  ) {
    if (counts.isEmpty) {
      return _summaryLine(
        context,
        PeerPresence.offline,
        l10n.presenceSummaryEmpty,
        background,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _summaryLine(
          context,
          PeerPresence.online,
          l10n.presenceOnlineCount(counts.online),
          background,
        ),
        if (counts.connecting > 0) ...[
          const SizedBox(height: 2),
          _summaryLine(
            context,
            PeerPresence.connecting,
            l10n.presenceConnectingCount(counts.connecting),
            background,
          ),
        ],
        const SizedBox(height: 2),
        _summaryLine(
          context,
          PeerPresence.offline,
          l10n.presenceOfflineCount(counts.offline),
          background,
        ),
      ],
    );
  }

  Widget _wideBody(
    BuildContext context,
    AppLocalizations l10n,
    Color background,
  ) {
    if (counts.isEmpty) {
      return Center(
        child: _summaryLine(
          context,
          PeerPresence.offline,
          l10n.presenceSummaryEmpty,
          background,
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 2,
      children: [
        _summaryLine(
          context,
          PeerPresence.online,
          l10n.presenceOnlineCount(counts.online),
          background,
        ),
        if (counts.connecting > 0)
          _summaryLine(
            context,
            PeerPresence.connecting,
            l10n.presenceConnectingCount(counts.connecting),
            background,
          ),
        _summaryLine(
          context,
          PeerPresence.offline,
          l10n.presenceOfflineCount(counts.offline),
          background,
        ),
      ],
    );
  }

  Widget _summaryLine(
    BuildContext context,
    PeerPresence presence,
    String text,
    Color background,
  ) {
    final colors = WeChatColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PresenceDot(
          presence: presence,
          size: compact ? 7 : 8,
          ringColor: background,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? WeChat.railLabelSize : WeChat.fontSizeMeta,
              color: presence == PeerPresence.online
                  ? colors.brandStrong
                  : colors.secondaryText,
              fontWeight: presence == PeerPresence.online
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

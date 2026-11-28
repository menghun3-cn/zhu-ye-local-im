import '../app/app.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';

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

/// The one-word presence reading, without the last-seen detail
/// [labelForPeerPresence] adds for an offline peer.
///
/// This is the form a header's title line carries: beside the peer's name it
/// has room for the state and nothing more, and the list row is where the
/// "离线 · 3 分钟前" reading belongs.
String labelForPresenceState(PeerPresence presence, AppLocalizations l10n) =>
    switch (presence) {
      PeerPresence.online => l10n.presenceOnline,
      PeerPresence.connecting => l10n.presenceConnecting,
      PeerPresence.offline => l10n.presenceOffline,
    };

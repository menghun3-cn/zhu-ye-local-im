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

import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/presence.dart';

void main() {
  final l10n = lookupAppLocalizations(appLocale);

  PeerView peer({
    bool connected = false,
    bool connecting = false,
    DateTime? lastSeen,
  }) => PeerView(
    fingerprint: Fingerprint.ofPublicKey(const [9, 8, 7]),
    alias: 'Bob',
    platform: DevicePlatform.windows,
    address: '10.0.0.7',
    sessionPort: 47655,
    pairingPort: null,
    isConnected: connected,
    isConnecting: connecting,
    isInGroup: true,
    isFavorite: false,
    lastSeen: lastSeen,
  );

  group('a peer presence label', () {
    test('names the live and transitional states', () {
      expect(
        labelForPeerPresence(peer(connected: true), l10n),
        l10n.presenceOnline,
      );
      expect(
        labelForPeerPresence(peer(connecting: true), l10n),
        l10n.presenceConnecting,
      );
    });

    test('adds last seen only when there is one', () {
      expect(labelForPeerPresence(peer(), l10n), l10n.presenceOffline);
      expect(
        labelForPeerPresence(peer(lastSeen: DateTime.now().toUtc()), l10n),
        l10n.presenceOfflineWithLastSeen(l10n.timeJustNow),
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/presence.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

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

  testWidgets('the summary shows every count and is one button', (
    tester,
  ) async {
    var opened = false;
    const counts = PresenceCounts(online: 1, connecting: 2, offline: 3);
    await tester.pumpWidget(
      MaterialApp(
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appLocales,
        theme: WeChat.theme(WeChatColors.light),
        home: Scaffold(
          body: ConnectionSummary(counts: counts, onTap: () => opened = true),
        ),
      ),
    );

    expect(find.text(l10n.presenceOnlineCount(1)), findsOneWidget);
    expect(find.text(l10n.presenceConnectingCount(2)), findsOneWidget);
    expect(find.text(l10n.presenceOfflineCount(3)), findsOneWidget);

    await tester.tap(find.byType(ConnectionSummary));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('the summary stays legible in both palettes', (tester) async {
    const counts = PresenceCounts(online: 1, connecting: 0, offline: 1);
    for (final colors in [WeChatColors.light, WeChatColors.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: appLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: appLocales,
          theme: WeChat.theme(colors),
          home: Scaffold(
            body: ConnectionSummary(counts: counts, onTap: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final online = tester.widget<Text>(
        find.text(l10n.presenceOnlineCount(1)),
      );
      final offline = tester.widget<Text>(
        find.text(l10n.presenceOfflineCount(1)),
      );
      expect(online.style?.color, colors.brandStrong);
      expect(offline.style?.color, colors.secondaryText);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the compact summary fits the rail width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: appLocales,
        theme: WeChat.theme(WeChatColors.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: WeChat.railWidth - 2 * WeChat.railHPadding,
              child: const ConnectionSummary(
                counts: PresenceCounts(online: 1, connecting: 1, offline: 99),
                compact: true,
                onTap: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

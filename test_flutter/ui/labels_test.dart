import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/labels.dart';

/// How a peer reads on a card, for the cases the peer list actually produces.
///
/// Tested here rather than through a window: the string is a pure reading of a
/// [PeerView], and the states that matter — a Device in the group that has
/// never been placed, one that is connected, one whose address is known but
/// which is not accepting Sessions — are all cheaper and more precisely built
/// as values than as screens.
void main() {
  final l10n = lookupAppLocalizations(appLocale);

  PeerView peer({
    String? alias = 'Bob',
    String? address,
    int? sessionPort,
    bool connected = false,
    bool inGroup = true,
    DateTime? lastSeen,
  }) => PeerView(
    fingerprint: Fingerprint.ofPublicKey(const [7, 8, 9]),
    alias: alias,
    platform: DevicePlatform.windows,
    address: address,
    sessionPort: sessionPort,
    isConnected: connected,
    isInGroup: inGroup,
    isFavorite: false,
    lastSeen: lastSeen,
  );

  group('a peer that has never been placed', () {
    test('is described once, not twice', () {
      final facts = describePeerFacts(peer(), l10n);
      // The complaint this pins down: the card used to read
      // "never seen · last seen never" — the same fact, said twice, and the
      // second time as a contradiction.
      expect(facts, contains(l10n.neverSeen));
      expect(
        facts,
        isNot(contains(l10n.lastSeen(l10n.timeNever))),
        reason: 'a Device with no address has no last-seen worth printing',
      );
    });
  });

  group('a connected peer', () {
    test('reads as the address it is connected at', () {
      final facts = describePeerFacts(
        peer(address: '10.0.0.7', sessionPort: 47655, connected: true),
        l10n,
      );
      expect(facts, contains('10.0.0.7:47655'));
      expect(facts, contains(l10n.sessionOpen));
      expect(facts, isNot(contains(l10n.neverSeen)));
    });

    test('keeps its address even when it advertises no Session port', () {
      final facts = describePeerFacts(
        peer(address: '10.0.0.7', connected: true),
        l10n,
      );
      expect(facts, contains('10.0.0.7'));
      expect(
        facts,
        isNot(contains(l10n.peerNotAccepting('10.0.0.7'))),
        reason: 'the Session is the proof that it accepts this one',
      );
    });

    test('never reports a last-seen time', () {
      final facts = describePeerFacts(
        peer(
          address: '10.0.0.7',
          sessionPort: 47655,
          connected: true,
          lastSeen: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        ),
        l10n,
      );
      expect(facts, contains(l10n.sessionOpen));
      expect(facts, isNot(contains(l10n.timeHoursAgo(3))));
    });

    test('is not called unseen when the Session named no address', () {
      // A Session reads its address off the transport, and a transport that
      // reports none would otherwise put "never seen" on a Device this one is
      // demonstrably talking to.
      final facts = describePeerFacts(peer(connected: true), l10n);
      expect(facts, contains(l10n.sessionOpen));
      expect(facts, isNot(contains(l10n.neverSeen)));
    });
  });

  group('a peer that is known but not connected', () {
    test('reads as its address and when it was last seen', () {
      final facts = describePeerFacts(
        peer(
          address: '10.0.0.7',
          sessionPort: 47655,
          lastSeen: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        ),
        l10n,
      );
      expect(facts, contains('10.0.0.7:47655'));
      expect(facts, contains(l10n.lastSeen(l10n.timeHoursAgo(3))));
    });

    test('says so when it is not accepting Sessions', () {
      final facts = describePeerFacts(peer(address: '10.0.0.7'), l10n);
      expect(facts, contains(l10n.peerNotAccepting('10.0.0.7')));
    });
  });

  group('how a conversation is drawn', () {
    test('does not wear the peer platform', () {
      // The row used to be drawn with the platform icon, which in a list of
      // conversations reads as "which app is this" — a question nobody is
      // asking. The platform is still on the peer's own card.
      expect(iconForConversation(), Icons.forum_outlined);
      expect(
        iconForConversation(),
        isNot(iconForPlatform(DevicePlatform.windows)),
      );
      expect(
        iconForConversation(),
        isNot(iconForPlatform(DevicePlatform.android)),
      );
    });
  });

  group('how long a transfer took', () {
    final started = DateTime.utc(2026, 10, 10, 12);

    TransferView view(TransferState state, {DateTime? settledAt}) =>
        TransferView(
          id: 't1',
          direction: TransferDirection.outgoing,
          kind: PayloadKind.file,
          peer: Fingerprint.ofPublicKey(const [7, 8, 9]),
          at: started,
          settledAt: settledAt,
          state: state,
          transferredBytes: 10,
          totalBytes: 100,
          names: const ['a.bin'],
          text: null,
          offer: null,
        );

    test('says nothing before a byte has moved', () {
      // A question nobody has answered has no duration, and "0 秒" printed
      // under it would be a number pretending to be one.
      expect(
        describeTransferDuration(
          view(TransferState.awaitingDecision),
          started,
          l10n,
        ),
        isNull,
      );
      expect(
        describeTransferDuration(
          view(TransferState.rejected, settledAt: started),
          started.add(const Duration(minutes: 5)),
          l10n,
        ),
        isNull,
      );
    });

    test('counts up while it is still going', () {
      expect(
        describeTransferDuration(
          view(TransferState.transferring),
          started.add(const Duration(seconds: 12)),
          l10n,
        ),
        l10n.transferElapsed(l10n.durationSeconds(12)),
      );
    });

    test('reports the interval it took once it has settled', () {
      expect(
        describeTransferDuration(
          view(
            TransferState.completed,
            settledAt: started.add(const Duration(minutes: 3, seconds: 12)),
          ),
          started.add(const Duration(hours: 2)),
          l10n,
        ),
        l10n.transferTook(l10n.durationMinutes(3, 12)),
        reason: 'a finished duration does not keep growing with the clock',
      );
    });

    test('rolls over into hours', () {
      expect(
        describeTransferDuration(
          view(
            TransferState.completed,
            settledAt: started.add(
              const Duration(hours: 1, minutes: 5, seconds: 40),
            ),
          ),
          started,
          l10n,
        ),
        l10n.transferTook(l10n.durationHours(1, 5)),
      );
    });

    test('says nothing when it settled in a run that never watched it', () {
      // A Transfer restored from a previous run lands here: the far end of the
      // interval was never recorded, and measuring to `now` would report the
      // application's uptime as the Transfer's duration.
      expect(
        describeTransferDuration(
          view(TransferState.completed),
          started.add(const Duration(hours: 4)),
          l10n,
        ),
        isNull,
      );
    });
  });
}

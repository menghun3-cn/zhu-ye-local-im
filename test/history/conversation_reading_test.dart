import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

Fingerprint _peer(String label) => Fingerprint.ofPublicKey(utf8.encode(label));

/// One message's contribution to an unread count: which side sent it, and when.
({bool incoming, DateTime at}) _incoming(DateTime at) =>
    (incoming: true, at: at);

({bool incoming, DateTime at}) _outgoing(DateTime at) =>
    (incoming: false, at: at);

void main() {
  group('a conversation nobody has opened', () {
    test('counts every message that arrived', () {
      final reading = ConversationReading();
      final peer = _peer('Alice');

      expect(
        reading.unreadFor(peer, [
          _incoming(DateTime.utc(2026, 10, 10, 9)),
          _incoming(DateTime.utc(2026, 10, 10, 10)),
        ]),
        2,
        reason: 'a first look at an old conversation is still a first look',
      );
    });

    test('does not count what this Device sent', () {
      final reading = ConversationReading();
      final peer = _peer('Alice');

      expect(
        reading.unreadFor(peer, [
          _outgoing(DateTime.utc(2026, 10, 10, 9)),
          _outgoing(DateTime.utc(2026, 10, 10, 10)),
        ]),
        0,
        reason: 'a user does not have to be told about their own words',
      );
    });

    test('says it has never been opened', () {
      expect(ConversationReading().hasOpened(_peer('Alice')), isFalse);
    });
  });

  group('a conversation that has been opened', () {
    test('counts only what arrived after the mark', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 10));

      expect(
        reading.unreadFor(peer, [
          _incoming(DateTime.utc(2026, 10, 10, 9)),
          _incoming(DateTime.utc(2026, 10, 10, 10)),
          _incoming(DateTime.utc(2026, 10, 10, 11)),
        ]),
        1,
        reason: 'the message at the mark itself was on screen when it was made',
      );
    });

    test('counts nothing when the last word was the user\'s own', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 10));

      expect(
        reading.unreadFor(peer, [_outgoing(DateTime.utc(2026, 10, 10, 11))]),
        0,
      );
    });

    test('says it has been opened', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 10));

      expect(reading.hasOpened(peer), isTrue);
      expect(reading.openedThrough(peer), DateTime.utc(2026, 10, 10, 10));
    });

    test('an earlier mark never moves the watermark backwards', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 10))
        // A clock that stepped back — a timezone change, an NTP correction.
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 9));

      expect(
        reading.openedThrough(peer),
        DateTime.utc(2026, 10, 10, 10),
        reason: 'a read conversation must not show everything as unread again',
      );
    });

    test('the same instant is not an advance', () {
      final peer = _peer('Alice');
      final at = DateTime.utc(2026, 10, 10, 10);
      final reading = ConversationReading()
        ..markOpened(peer, at)
        ..markOpened(peer, at);

      expect(reading.openedThrough(peer), at);
    });

    test('a later mark does move it forward', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 10))
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 12));

      expect(reading.openedThrough(peer), DateTime.utc(2026, 10, 10, 12));
    });

    test('peers are marked separately', () {
      final alice = _peer('Alice');
      final bob = _peer('Bob');
      final reading = ConversationReading()
        ..markOpened(alice, DateTime.utc(2026, 10, 10, 10));

      expect(reading.hasOpened(alice), isTrue);
      expect(reading.hasOpened(bob), isFalse);
    });
  });

  group('the last conversation', () {
    test('starts as none', () {
      expect(ConversationReading().lastPeer, isNull);
    });

    test('round-trips through JSON', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()
        ..markOpened(peer, DateTime.utc(2026, 10, 10, 10))
        ..lastPeer = peer.hex;

      final restored = ConversationReading.fromJson(
        jsonDecode(jsonEncode(reading.toJson())) as Map<String, Object?>,
      );

      expect(restored.lastPeer, peer.hex);
      expect(restored.openedThrough(peer), DateTime.utc(2026, 10, 10, 10));
    });

    test('a state with no last peer writes no key and reads back as none', () {
      final json = ConversationReading().toJson();

      expect(json.containsKey('lastPeer'), isFalse);
      expect(ConversationReading.fromJson(json).lastPeer, isNull);
    });
  });

  group('pruning', () {
    test('drops peers that are no longer kept', () {
      final alice = _peer('Alice');
      final bob = _peer('Bob');
      final reading = ConversationReading()
        ..markOpened(alice, DateTime.utc(2026, 10, 10, 10))
        ..markOpened(bob, DateTime.utc(2026, 10, 10, 10));

      reading.retainOnly({bob.hex});

      expect(reading.hasOpened(alice), isFalse);
      expect(reading.hasOpened(bob), isTrue);
    });

    test('clears the last conversation when it is dropped', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()..lastPeer = peer.hex;

      reading.retainOnly(const <String>{});

      expect(reading.lastPeer, isNull);
    });

    test('keeps the last conversation when it is kept', () {
      final peer = _peer('Alice');
      final reading = ConversationReading()..lastPeer = peer.hex;

      reading.retainOnly({peer.hex});

      expect(reading.lastPeer, peer.hex);
    });
  });

  group('a malformed reading state', () {
    test('a non-map openedThrough is refused', () {
      expect(
        () => ConversationReading.fromJson({'openedThrough': 'nope'}),
        throwsFormatException,
      );
    });

    test('a non-string timestamp is refused', () {
      expect(
        () => ConversationReading.fromJson({
          'openedThrough': {'aa': 12},
        }),
        throwsFormatException,
      );
    });

    test('a timestamp that is not ISO-8601 is refused', () {
      expect(
        () => ConversationReading.fromJson({
          'openedThrough': {'aa': 'yesterday'},
        }),
        throwsFormatException,
      );
    });

    test('a non-string lastPeer is refused', () {
      expect(
        () => ConversationReading.fromJson({'lastPeer': 3}),
        throwsFormatException,
      );
    });

    test('an absent openedThrough is an empty one', () {
      expect(
        ConversationReading.fromJson(const {}).hasOpened(_peer('A')),
        isFalse,
      );
    });
  });
}

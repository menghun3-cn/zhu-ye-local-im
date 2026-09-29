import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import 'support.dart';

void main() {
  final aliceDevice = testDevice('alice');
  final bobDevice = testDevice('bob');
  final carolDevice = testDevice('carol');
  final alice = aliceDevice.fingerprint;
  final bob = bobDevice.fingerprint;

  OwnerGroup aliceAndBob() => OwnerGroup(self: alice, members: [bob]);

  group('capturing a local copy', () {
    test(
      'sends it to a Device in the Owner Group, tagged with this one',
      () async {
        final fixture = MirrorFixture(group: aliceAndBob());
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        fixture.clipboard.copy('a password');
        await until(() => channel.sent.length == 1, description: '一个条目');

        final sent = channel.sent.single;
        expect(sent.text, 'a password');
        expect(sent.originFingerprint, alice);
        expect(sent.entryId, isNotEmpty);
        await fixture.close();
      },
    );

    test('sends it to no Device outside the Owner Group', () async {
      final fixture = MirrorFixture(group: aliceAndBob());
      final member = FakeClipboardChannel();
      final stranger = FakeClipboardChannel();
      fixture.attach(bobDevice, member);
      fixture.attach(carolDevice, stranger);
      fixture.mirror.start();

      fixture.clipboard.copy('a password');
      await until(() => member.sent.length == 1, description: '成员的条目');
      // The member's entry has already gone out, so a stranger's would have
      // too if it were coming: nothing here is racing the clock.
      expect(stranger.sent, isEmpty);
      await fixture.close();
    });

    test('passes over an empty copy, which is not a copy at all', () async {
      final fixture = MirrorFixture(group: aliceAndBob());
      final channel = FakeClipboardChannel();
      fixture.attach(bobDevice, channel);
      fixture.mirror.start();

      fixture.clipboard.copy('');
      await settle();
      expect(channel.sent, isEmpty);
      await fixture.close();
    });

    test('captures nothing while the mode is off', () async {
      final fixture = MirrorFixture(
        group: aliceAndBob(),
        mode: ClipboardMode.off,
      );
      final channel = FakeClipboardChannel();
      fixture.attach(bobDevice, channel);
      fixture.mirror.start();

      fixture.clipboard.copy('copied while off');
      fixture.mirror.setMode(ClipboardMode.mirror);
      fixture.clipboard.copy('copied while on');
      await until(() => channel.sent.length == 1, description: '一个条目');

      expect(channel.sent.single.text, 'copied while on');
      await fixture.close();
    });

    test(
      'captures nothing on a platform that cannot read its clipboard',
      () async {
        final fixture = MirrorFixture(
          group: aliceAndBob(),
          capability: ClipboardCapability.forPlatform(DevicePlatform.android),
        );
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        fixture.clipboard.copy('a password');
        await settle();
        expect(channel.sent, isEmpty);
        await fixture.close();
      },
    );

    test(
      'does not send an entry back out when it is the one we applied',
      () async {
        final fixture = MirrorFixture(group: aliceAndBob());
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        channel.deliver(testEntry(bobDevice, 'from bob').toMessage());
        await until(
          () => fixture.clipboard.applied.length == 1,
          description: '一次应用',
        );
        await settle();

        // Applying it made the platform report a clipboard change. Mirroring
        // that change back would start a loop with no end.
        expect(channel.sent, isEmpty);
        expect(fixture.clipboard.applied.single, 'from bob');
        await fixture.close();
      },
    );
  });

  group('applying an incoming entry', () {
    test(
      'replaces the clipboard with no user action while mirroring',
      () async {
        final fixture = MirrorFixture(group: aliceAndBob());
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        channel.deliver(testEntry(bobDevice, 'from bob').toMessage());
        await until(
          () => fixture.clipboard.applied.length == 1,
          description: '一次应用',
        );

        expect(await fixture.clipboard.read(), 'from bob');
        await fixture.close();
      },
    );

    test('waits for the user while staging, then applies on command', () async {
      final fixture = MirrorFixture(
        group: aliceAndBob(),
        mode: ClipboardMode.stage,
      );
      final channel = FakeClipboardChannel();
      fixture.attach(bobDevice, channel);
      fixture.mirror.start();

      final entry = testEntry(bobDevice, 'from bob');
      channel.deliver(entry.toMessage());
      await until(
        () => fixture.mirror.stagedEntries.length == 1,
        description: '一条待处理条目',
      );
      expect(fixture.clipboard.applied, isEmpty);

      await fixture.mirror.apply(entry);
      expect(await fixture.clipboard.read(), 'from bob');
      expect(fixture.mirror.stagedEntries, isEmpty);
      await fixture.close();
    });

    test('refuses when this platform cannot write its clipboard', () async {
      final fixture = MirrorFixture(
        group: aliceAndBob(),
        capability: ClipboardCapability.forPlatform(DevicePlatform.other),
      );
      final channel = FakeClipboardChannel();
      fixture.attach(bobDevice, channel);
      fixture.mirror.start();

      channel.deliver(testEntry(bobDevice, 'from bob').toMessage());
      await settle();
      expect(fixture.clipboard.applied, isEmpty);
      expect(fixture.notices, isNotEmpty);
      await fixture.close();
    });

    test('refuses an entry from a Device outside the Owner Group', () async {
      final fixture = MirrorFixture(group: OwnerGroup(self: alice));
      final channel = FakeClipboardChannel();
      fixture.attach(bobDevice, channel);
      fixture.mirror.start();

      channel.deliver(testEntry(bobDevice, 'from bob').toMessage());
      await settle();
      expect(fixture.clipboard.applied, isEmpty);
      expect(fixture.notices.single, contains('Owner Group'));
      await fixture.close();
    });

    test(
      'refuses an entry tagged with a Device it did not come from',
      () async {
        final fixture = MirrorFixture(
          group: OwnerGroup(
            self: alice,
            members: [bob, carolDevice.fingerprint],
          ),
        );
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        // Carol is in the group, but this arrived over Bob's Session: a peer
        // relaying somebody else's content under a new tag is exactly the
        // smuggling the tag exists to stop.
        channel.deliver(
          testEntry(carolDevice, 'not really from carol').toMessage(),
        );
        await settle();
        expect(fixture.clipboard.applied, isEmpty);
        expect(fixture.notices.single, contains('not the peer'));
        await fixture.close();
      },
    );

    test(
      'drops this Device\'s own content coming back, without a word',
      () async {
        final fixture = MirrorFixture(group: aliceAndBob());
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        channel.deliver(testEntry(aliceDevice, 'our own copy').toMessage());
        await settle();
        expect(fixture.clipboard.applied, isEmpty);
        expect(fixture.notices, isEmpty);
        await fixture.close();
      },
    );

    test('drops an entry it has already handled', () async {
      final fixture = MirrorFixture(group: aliceAndBob());
      final channel = FakeClipboardChannel();
      fixture.attach(bobDevice, channel);
      fixture.mirror.start();

      channel.deliver(
        testEntry(
          bobDevice,
          'once',
          id: 'same',
          at: DateTime.utc(2026, 9, 29, 10),
        ).toMessage(),
      );
      await until(
        () => fixture.clipboard.applied.length == 1,
        description: '一次应用',
      );
      channel.deliver(
        testEntry(
          bobDevice,
          'once',
          id: 'same',
          at: DateTime.utc(2026, 9, 29, 11),
        ).toMessage(),
      );
      await settle();
      expect(fixture.clipboard.applied.length, 1);
      await fixture.close();
    });

    test(
      'drops an entry older than the newest it has taken from that Device',
      () async {
        final fixture = MirrorFixture(group: aliceAndBob());
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        channel.deliver(
          testEntry(
            bobDevice,
            'newer',
            id: 'b',
            at: DateTime.utc(2026, 9, 29, 12),
          ).toMessage(),
        );
        await until(
          () => fixture.clipboard.applied.length == 1,
          description: '一次应用',
        );
        channel.deliver(
          testEntry(
            bobDevice,
            'older',
            id: 'a',
            at: DateTime.utc(2026, 9, 29, 11),
          ).toMessage(),
        );
        await settle();
        expect(fixture.clipboard.applied, ['newer']);
        await fixture.close();
      },
    );

    test('takes an entry stamped the same as the newest one, once', () async {
      final at = DateTime.utc(2026, 9, 29, 12);
      final fixture = MirrorFixture(group: aliceAndBob());
      final channel = FakeClipboardChannel();
      fixture.attach(bobDevice, channel);
      fixture.mirror.start();

      channel.deliver(
        testEntry(bobDevice, 'first', id: 'a', at: at).toMessage(),
      );
      await until(
        () => fixture.clipboard.applied.length == 1,
        description: '一次应用',
      );
      channel.deliver(
        testEntry(bobDevice, 'same instant', id: 'b', at: at).toMessage(),
      );
      await settle();
      expect(fixture.clipboard.applied.length, 1);
      await fixture.close();
    });
  });

  group('the peers a mirror is watching', () {
    test('stops taking entries from a Device it has detached', () async {
      final fixture = MirrorFixture(group: aliceAndBob());
      final member = FakeClipboardChannel();
      final other = FakeClipboardChannel();
      final carol = carolDevice.fingerprint;
      fixture.mirror.setGroup(OwnerGroup(self: alice, members: [bob, carol]));
      fixture.attach(bobDevice, member);
      fixture.attach(carolDevice, other);
      fixture.mirror.start();

      fixture.mirror.detachPeer(carol);
      fixture.clipboard.copy('a password');
      await until(() => member.sent.length == 1, description: '成员的条目');
      expect(other.sent, isEmpty);

      other.deliver(testEntry(carolDevice, 'from carol').toMessage());
      await settle();
      expect(fixture.clipboard.applied, isEmpty);
      await fixture.close();
    });

    test('drops a Device that is forgotten from the Owner Group', () async {
      final fixture = MirrorFixture(group: aliceAndBob());
      final member = FakeClipboardChannel();
      final forgotten = FakeClipboardChannel();
      final carol = carolDevice.fingerprint;
      fixture.mirror.setGroup(OwnerGroup(self: alice, members: [bob, carol]));
      fixture.attach(bobDevice, member);
      fixture.attach(carolDevice, forgotten);
      fixture.mirror.start();

      fixture.mirror.setGroup(OwnerGroup(self: alice, members: [bob]));
      fixture.clipboard.copy('a password');
      await until(() => member.sent.length == 1, description: '成员的条目');
      expect(forgotten.sent, isEmpty);
      await fixture.close();
    });

    test('keeps the last channel when a Device re-attaches', () async {
      final fixture = MirrorFixture(group: aliceAndBob());
      final first = FakeClipboardChannel();
      final second = FakeClipboardChannel();
      fixture.attach(bobDevice, first);
      fixture.attach(bobDevice, second);
      fixture.mirror.start();

      fixture.clipboard.copy('a password');
      await until(() => second.sent.length == 1, description: '新通道的条目');
      expect(first.sent, isEmpty);
      await fixture.close();
    });

    test(
      'releases everything on close, and closing twice is harmless',
      () async {
        final fixture = MirrorFixture(group: aliceAndBob());
        final channel = FakeClipboardChannel();
        fixture.attach(bobDevice, channel);
        fixture.mirror.start();

        await fixture.close();
        await fixture.close();
        expect(fixture.mirror.isRunning, isFalse);

        fixture.clipboard.copy('after close');
        await settle();
        expect(channel.sent, isEmpty);
      },
    );
  });

  group('applying an entry a caller hands over', () {
    test('refuses one from a Device outside the Owner Group', () async {
      final fixture = MirrorFixture(
        group: OwnerGroup(self: alice),
        mode: ClipboardMode.stage,
      );
      await fixture.mirror.apply(testEntry(bobDevice, 'from bob'));
      expect(fixture.clipboard.applied, isEmpty);
      expect(fixture.notices.single, contains('Owner Group'));
      await fixture.close();
    });

    test('accepts one this Device captured itself', () async {
      final fixture = MirrorFixture(group: aliceAndBob());
      await fixture.mirror.apply(testEntry(aliceDevice, 'mine'));
      expect(fixture.clipboard.applied, ['mine']);
      await fixture.close();
    });
  });

  group('a clipboard mode', () {
    test('knows whether it captures at all', () {
      expect(ClipboardMode.off.captures, isFalse);
      expect(ClipboardMode.stage.captures, isTrue);
      expect(ClipboardMode.mirror.captures, isTrue);
    });

    test('round-trips through its wire name', () {
      for (final mode in ClipboardMode.values) {
        expect(ClipboardMode.fromWireName(mode.wireName), mode);
      }
      expect(
        () => ClipboardMode.fromWireName('nothing'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

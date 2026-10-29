import 'package:test/test.dart';

import 'package:local_transfer/core/clipboard/clipboard_capability.dart';
import 'package:local_transfer/core/host/close_behaviour.dart';
import 'package:local_transfer/core/identity/fingerprint.dart';
import 'package:local_transfer/core/identity/owner_group.dart';
import 'package:local_transfer/core/profile/device_profile.dart';
import 'package:local_transfer/core/update/update_check_interval.dart';

Fingerprint _fp(String seed) {
  // 64 hex characters derived from a readable seed, so test intent stays
  // visible: _fp('a') is a stable, distinct identity.
  final hex = seed.codeUnitAt(0).toRadixString(16).padLeft(2, '0') * 32;
  return Fingerprint(hex);
}

DateTime get _now => DateTime.utc(2026, 9, 30, 8);

void main() {
  group('DeviceProfile', () {
    test('a new profile is alone in its own group', () {
      final self = _fp('a');
      final profile = DeviceProfile(
        self: self,
        alias: 'Desk',
        platform: DevicePlatform.windows,
      );
      expect(profile.group.isAlone, isTrue);
      expect(profile.group.contains(self), isTrue);
    });

    test('a hostile alias is sanitised the same way a peer name would be', () {
      final profile = DeviceProfile(
        self: _fp('a'),
        alias: '  Desk\x1b[31m  ',
        platform: DevicePlatform.windows,
      );
      expect(profile.alias, 'Desk[31m');
    });

    test('an empty alias falls back, it does not crash', () {
      final profile = DeviceProfile(
        self: _fp('a'),
        alias: '   ',
        platform: DevicePlatform.windows,
      );
      expect(profile.alias, 'Unnamed device');
    });

    group('recent emojis', () {
      test('a new profile has no recents', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        expect(profile.recentEmojis, isEmpty);
      });

      test('remembering moves the face to the front and persists', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.rememberEmoji('😀');
        profile.rememberEmoji('😂');
        profile.rememberEmoji('😀');
        expect(profile.recentEmojis, ['😀', '😂']);

        final decoded = DeviceProfile.fromJson(profile.toJson());
        expect(decoded.recentEmojis, ['😀', '😂']);
      });

      test('a face outside the table never enters the strip', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
          recentEmojis: ['😀', '👻', '😂'],
        );
        expect(profile.recentEmojis, ['😀', '😂']);
        profile.rememberEmoji('👻');
        expect(profile.recentEmojis, ['😀', '😂']);
      });

      test('a profile written before the key exists reads with no recents', () {
        final json = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        ).toJson();
        json.remove('recentEmojis');
        expect(DeviceProfile.fromJson(json).recentEmojis, isEmpty);
      });
    });

    group('favorites', () {
      test('marking and unmarking is reflected in isFavorite', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        final peer = _fp('b');
        expect(profile.isFavorite(peer), isFalse);
        profile.setFavorite(peer, value: true);
        expect(profile.isFavorite(peer), isTrue);
        profile.setFavorite(peer, value: false);
        expect(profile.isFavorite(peer), isFalse);
      });

      test('marking twice cannot create duplicates', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.setFavorite(_fp('b'), value: true);
        profile.setFavorite(_fp('b'), value: true);
        expect(profile.favorites, hasLength(1));
      });

      test('self can never be a favorite', () {
        final self = _fp('a');
        final profile = DeviceProfile(
          self: self,
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.setFavorite(self, value: true);
        expect(profile.isFavorite(self), isFalse);
      });

      test('group members are not silently favourites', () {
        final self = _fp('a');
        final member = _fp('b');
        final profile = DeviceProfile(
          self: self,
          alias: 'Desk',
          platform: DevicePlatform.windows,
          group: OwnerGroup(self: self, members: [member]),
        );
        expect(profile.group.contains(member), isTrue);
        expect(profile.isFavorite(member), isFalse);
      });
    });

    group('known devices', () {
      test('noteDevice records and refreshes a peer', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        final peer = _fp('b');
        profile.noteDevice(
          KnownDevice(
            fingerprint: peer,
            alias: 'Phone',
            platform: DevicePlatform.android,
          ),
        );
        expect(profile.known(peer)!.alias, 'Phone');
        profile.noteDevice(
          KnownDevice(
            fingerprint: peer,
            alias: 'Renamed',
            platform: DevicePlatform.android,
            lastSeen: _now,
          ),
        );
        expect(profile.known(peer)!.alias, 'Renamed');
        expect(profile.knownDevices, hasLength(1));
      });

      test('self is never recorded as a known device', () {
        final self = _fp('a');
        final profile = DeviceProfile(
          self: self,
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.noteDevice(
          KnownDevice(
            fingerprint: self,
            alias: 'Me',
            platform: DevicePlatform.windows,
          ),
        );
        expect(profile.knownDevices, isEmpty);
      });

      test('forgetDevice removes every trace of a peer and keeps others', () {
        final self = _fp('a');
        final doomed = _fp('b');
        final kept = _fp('c');
        final profile = DeviceProfile(
          self: self,
          alias: 'Desk',
          platform: DevicePlatform.windows,
          group: OwnerGroup(self: self, members: [doomed, kept]),
          favorites: {doomed, kept},
          clipboardPeers: {doomed, kept},
          known: {
            doomed.hex: KnownDevice(
              fingerprint: doomed,
              alias: 'Doomed',
              platform: DevicePlatform.android,
            ),
            kept.hex: KnownDevice(
              fingerprint: kept,
              alias: 'Kept',
              platform: DevicePlatform.windows,
            ),
          },
        );

        profile.forgetDevice(doomed);

        expect(profile.known(doomed), isNull);
        expect(profile.isFavorite(doomed), isFalse);
        expect(profile.isClipboardPeer(doomed), isFalse);
        expect(profile.group.contains(doomed), isFalse);
        expect(profile.known(kept), isNotNull);
        expect(profile.isFavorite(kept), isTrue);
        expect(profile.isClipboardPeer(kept), isTrue);
        expect(profile.group.contains(kept), isTrue);
      });
    });

    group('the clipboard-sharing whitelist', () {
      test('starts empty, so pairing a Device shares nothing', () {
        // Separate from the group on purpose: joining an Owner Group is about
        // holding a Session, and says nothing about reading this clipboard.
        final self = _fp('a');
        final member = _fp('b');
        final profile = DeviceProfile(
          self: self,
          alias: 'Desk',
          platform: DevicePlatform.windows,
          group: OwnerGroup(self: self, members: [member]),
        );
        expect(profile.group.contains(member), isTrue);
        expect(profile.clipboardPeers, isEmpty);
        expect(profile.isClipboardPeer(member), isFalse);
      });

      test('adding and removing a peer is reflected in isClipboardPeer', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        final peer = _fp('b');
        profile.setClipboardPeer(peer, value: true);
        expect(profile.isClipboardPeer(peer), isTrue);
        expect(profile.clipboardPeers, [peer]);
        profile.setClipboardPeer(peer, value: false);
        expect(profile.isClipboardPeer(peer), isFalse);
        expect(profile.clipboardPeers, isEmpty);
      });

      test('adding the same peer twice cannot create duplicates', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.setClipboardPeer(_fp('b'), value: true);
        profile.setClipboardPeer(_fp('b'), value: true);
        expect(profile.clipboardPeers, hasLength(1));
      });

      test('self can never be on its own whitelist', () {
        final self = _fp('a');
        final profile = DeviceProfile(
          self: self,
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.setClipboardPeer(self, value: true);
        expect(profile.isClipboardPeer(self), isFalse);
      });

      test('the list survives a JSON round trip', () {
        final self = _fp('a');
        final profile = DeviceProfile(
          self: self,
          alias: 'Desk',
          platform: DevicePlatform.windows,
          clipboardPeers: {_fp('b'), _fp('c')},
        );
        final restored = DeviceProfile.fromJson(profile.toJson());
        expect(restored.clipboardPeers, profile.clipboardPeers);
        expect(restored.clipboardPeers, hasLength(2));
      });

      test('a profile JSON missing the list decodes to an empty one', () {
        // Saved by a build that predates the whitelist: the safe reading is
        // "nothing is shared", never "everything is".
        final restored = DeviceProfile.fromJson({
          'self': _fp('a').hex,
          'alias': 'Desk',
          'platform': 'windows',
        });
        expect(restored.clipboardPeers, isEmpty);
      });

      test('a non-string entry in the list is rejected, not ignored', () {
        expect(
          () => DeviceProfile.fromJson({
            'self': _fp('a').hex,
            'alias': 'Desk',
            'platform': 'windows',
            'clipboardPeers': [42],
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('the incoming folder', () {
      test('starts unset, so the platform default applies', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        expect(profile.incomingDirectory, isNull);
      });

      test('remembers the folder the user chose', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.setIncomingDirectory('D:/shared/inbox');
        expect(profile.incomingDirectory, 'D:/shared/inbox');
      });

      test('trims, and an empty answer goes back to the default', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        profile.setIncomingDirectory('  D:/shared/inbox  ');
        expect(profile.incomingDirectory, 'D:/shared/inbox');
        // Whitespace is how the screen says "no choice". A null-and-empty
        // distinction would be one the settings screen cannot show.
        profile.setIncomingDirectory('   ');
        expect(profile.incomingDirectory, isNull);
        profile.setIncomingDirectory(null);
        expect(profile.incomingDirectory, isNull);
      });

      test('a chosen folder survives a JSON round trip', () {
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
          incomingDirectory: 'D:/shared/inbox',
        );
        final restored = DeviceProfile.fromJson(profile.toJson());
        expect(restored.incomingDirectory, 'D:/shared/inbox');
      });

      test('an unset folder is written as absent, not as null', () {
        // "Unset" and "cleared" are the same fact, so they get the same
        // spelling: the key is left out, and any build reads it as the
        // platform default.
        final profile = DeviceProfile(
          self: _fp('a'),
          alias: 'Desk',
          platform: DevicePlatform.windows,
        );
        expect(profile.toJson().containsKey('incomingDirectory'), isFalse);
      });

      test('a profile JSON missing the key decodes to unset', () {
        final restored = DeviceProfile.fromJson({
          'self': _fp('a').hex,
          'alias': 'Desk',
          'platform': 'windows',
        });
        expect(restored.incomingDirectory, isNull);
      });
    });

    group('the close button', () {
      DeviceProfile profileOf(DevicePlatform platform) =>
          DeviceProfile(self: _fp('a'), alias: 'Desk', platform: platform);

      test('defaults to hiding the window, because being reachable is the '
          'point', () {
        // The default is not a placeholder: an app whose job is receiving
        // things cannot do it after the last window closes, so the answer that
        // needs no user action is the one that keeps it running.
        expect(
          profileOf(DevicePlatform.windows).closeBehaviour,
          CloseBehaviour.minimiseToTray,
        );
      });

      test(
        'a profile written before the key existed decodes to the default',
        () {
          final restored = DeviceProfile.fromJson({
            'self': _fp('a').hex,
            'alias': 'Desk',
            'platform': 'windows',
          });
          expect(restored.closeBehaviour, CloseBehaviour.minimiseToTray);
        },
      );

      test('a value this build does not know decodes to the default', () {
        // Tolerant rather than strict: what is being read is a preference, and
        // a preference is not worth refusing to open a Device's identity file
        // over. A newer version writing a third behaviour must not make an
        // older one unable to start.
        final restored = DeviceProfile.fromJson({
          'self': _fp('a').hex,
          'alias': 'Desk',
          'platform': 'windows',
          'closeBehaviour': 'somewhere-else',
        });
        expect(restored.closeBehaviour, CloseBehaviour.minimiseToTray);
      });

      test('a value of the wrong type decodes to the default too', () {
        final restored = DeviceProfile.fromJson({
          'self': _fp('a').hex,
          'alias': 'Desk',
          'platform': 'windows',
          'closeBehaviour': 3,
        });
        expect(restored.closeBehaviour, CloseBehaviour.minimiseToTray);
      });

      test('the choice is written as its own name and read back', () {
        final profile = profileOf(DevicePlatform.windows)
          ..closeBehaviour = CloseBehaviour.quit;
        expect(profile.toJson()['closeBehaviour'], 'quit');
        expect(
          DeviceProfile.fromJson(profile.toJson()).closeBehaviour,
          CloseBehaviour.quit,
        );
      });

      test('the wire names are distinct and stable', () {
        // These two strings are a file format: they are what a profile written
        // today is read back with tomorrow, so they may be added to but not
        // renamed. Spelled out here rather than compared to themselves.
        expect(CloseBehaviour.minimiseToTray.wireName, 'tray');
        expect(CloseBehaviour.quit.wireName, 'quit');
        expect(
          CloseBehaviour.fromWireName('tray'),
          CloseBehaviour.minimiseToTray,
        );
        expect(CloseBehaviour.fromWireName('quit'), CloseBehaviour.quit);
        expect(CloseBehaviour.fromWireName('later'), isNull);
      });
    });

    group('the update-check interval', () {
      DeviceProfile profileOf(DevicePlatform platform) =>
          DeviceProfile(self: _fp('a'), alias: 'Desk', platform: platform);

      test('defaults to hourly, the quiet cadence the app ships with', () {
        expect(
          profileOf(DevicePlatform.windows).updateCheckInterval,
          UpdateCheckInterval.hourly,
        );
      });

      test(
        'a profile written before the key existed decodes to the default',
        () {
          final restored = DeviceProfile.fromJson({
            'self': _fp('a').hex,
            'alias': 'Desk',
            'platform': 'windows',
          });
          expect(restored.updateCheckInterval, UpdateCheckInterval.hourly);
        },
      );

      test('a value this build does not know decodes to the default', () {
        final restored = DeviceProfile.fromJson({
          'self': _fp('a').hex,
          'alias': 'Desk',
          'platform': 'windows',
          'updateCheckInterval': 'weekly',
        });
        expect(restored.updateCheckInterval, UpdateCheckInterval.hourly);
      });

      test('a value of the wrong type decodes to the default too', () {
        final restored = DeviceProfile.fromJson({
          'self': _fp('a').hex,
          'alias': 'Desk',
          'platform': 'windows',
          'updateCheckInterval': 3,
        });
        expect(restored.updateCheckInterval, UpdateCheckInterval.hourly);
      });

      test('the choice is written as its own name and read back', () {
        final profile = profileOf(DevicePlatform.windows)
          ..updateCheckInterval = UpdateCheckInterval.daily;
        expect(profile.toJson()['updateCheckInterval'], 'daily');
        expect(
          DeviceProfile.fromJson(profile.toJson()).updateCheckInterval,
          UpdateCheckInterval.daily,
        );
      });

      test('the wire names are distinct and stable and duration follows', () {
        expect(UpdateCheckInterval.off.wireName, 'off');
        expect(UpdateCheckInterval.hourly.wireName, 'hourly');
        expect(UpdateCheckInterval.everySixHours.wireName, 'six-hours');
        expect(UpdateCheckInterval.daily.wireName, 'daily');
        expect(UpdateCheckInterval.everyThreeDays.wireName, 'three-days');
        expect(
          UpdateCheckInterval.fromWireName('six-hours'),
          UpdateCheckInterval.everySixHours,
        );
        expect(UpdateCheckInterval.fromWireName('weekly'), isNull);
        expect(UpdateCheckInterval.off.duration, isNull);
        expect(UpdateCheckInterval.hourly.duration, const Duration(hours: 1));
        expect(
          UpdateCheckInterval.everySixHours.duration,
          const Duration(hours: 6),
        );
        expect(UpdateCheckInterval.daily.duration, const Duration(hours: 24));
        expect(
          UpdateCheckInterval.everyThreeDays.duration,
          const Duration(hours: 72),
        );
      });
    });

    test('canMirrorTo follows group membership, not favorites', () {
      final self = _fp('a');
      final member = _fp('b');
      final stranger = _fp('c');
      final profile = DeviceProfile(
        self: self,
        alias: 'Desk',
        platform: DevicePlatform.windows,
        group: OwnerGroup(self: self, members: [member]),
      );
      profile.setFavorite(stranger, value: true);
      expect(profile.canMirrorTo(member), isTrue);
      expect(profile.canMirrorTo(stranger), isFalse);
    });

    test('a JSON round trip preserves every field', () {
      final self = _fp('a');
      final member = _fp('b');
      final favourite = _fp('c');
      final profile = DeviceProfile(
        self: self,
        alias: 'Desk',
        platform: DevicePlatform.windows,
        group: OwnerGroup(self: self, members: [member]),
        favorites: {favourite},
        clipboardPeers: {_fp('e')},
        incomingDirectory: 'D:/shared/inbox',
        closeBehaviour: CloseBehaviour.quit,
        updateCheckInterval: UpdateCheckInterval.everyThreeDays,
        known: {
          _fp('d').hex: KnownDevice(
            fingerprint: _fp('d'),
            alias: 'Phone',
            platform: DevicePlatform.android,
            lastSeen: _now,
            lastAddress: '192.168.1.23',
          ),
        },
      );
      final restored = DeviceProfile.fromJson(profile.toJson());
      expect(restored.self, self);
      expect(restored.alias, 'Desk');
      expect(restored.platform, DevicePlatform.windows);
      expect(restored.group, profile.group);
      expect(restored.favorites, [favourite]);
      expect(restored.clipboardPeers, [_fp('e')]);
      expect(restored.incomingDirectory, 'D:/shared/inbox');
      expect(restored.closeBehaviour, CloseBehaviour.quit);
      expect(restored.updateCheckInterval, UpdateCheckInterval.everyThreeDays);
      final known = restored.known(_fp('d'));
      expect(known, isNotNull);
      expect(known!.alias, 'Phone');
      expect(known.platform, DevicePlatform.android);
      expect(known.lastSeen, _now);
      expect(known.lastAddress, '192.168.1.23');
    });

    test('a profile JSON missing a group decodes to a group of one', () {
      final restored = DeviceProfile.fromJson({
        'self': _fp('a').hex,
        'alias': 'Desk',
        'platform': 'windows',
      });
      expect(restored.group.isAlone, isTrue);
    });
  });

  group('KnownDevice', () {
    test('copyWith replaces only the named fields', () {
      final original = KnownDevice(
        fingerprint: _fp('b'),
        alias: 'Phone',
        platform: DevicePlatform.android,
      );
      final updated = original.copyWith(lastSeen: _now);
      expect(updated.alias, 'Phone');
      expect(updated.platform, DevicePlatform.android);
      expect(updated.lastSeen, _now);
      expect(updated.lastAddress, isNull);
    });

    test('a JSON round trip preserves every field', () {
      final original = KnownDevice(
        fingerprint: _fp('b'),
        alias: 'Phone',
        platform: DevicePlatform.android,
        lastSeen: _now,
        lastAddress: '192.168.1.23',
      );
      final restored = KnownDevice.fromJson(original.toJson());
      expect(restored.fingerprint, original.fingerprint);
      expect(restored.alias, original.alias);
      expect(restored.platform, original.platform);
      expect(restored.lastSeen, original.lastSeen);
      expect(restored.lastAddress, original.lastAddress);
    });

    test('equality is by fingerprint, so upserts compare cleanly', () {
      final a = KnownDevice(
        fingerprint: _fp('b'),
        alias: 'Phone',
        platform: DevicePlatform.android,
      );
      final b = KnownDevice(
        fingerprint: _fp('b'),
        alias: 'Phone (renamed)',
        platform: DevicePlatform.android,
      );
      expect(a, b);
    });
  });
}

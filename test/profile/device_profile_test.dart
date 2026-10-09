import 'package:test/test.dart';

import 'package:local_transfer/core/clipboard/clipboard_capability.dart';
import 'package:local_transfer/core/identity/fingerprint.dart';
import 'package:local_transfer/core/identity/owner_group.dart';
import 'package:local_transfer/core/profile/device_profile.dart';

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

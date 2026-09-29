import 'dart:convert';
import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  final device = testDevice('device-a', listenPort: 51001);

  Uint8List datagram(Object? payload) =>
      Uint8List.fromList(utf8.encode(jsonEncode(payload)));

  Uint8List beaconJson({
    Object? version = beaconVersion,
    Object? kind = 'announce',
    Object? nonce = '0123456789abcdef',
    Object? deviceJson,
  }) => datagram({
    'v': version,
    'k': kind,
    'n': nonce,
    'device': deviceJson ?? device.toJson(),
  });

  group('Beacon', () {
    test('round-trips through a datagram', () {
      final beacon = Beacon(
        kind: BeaconKind.announce,
        device: device,
        nonce: 'abcdef0123456789',
      );

      final decoded = Beacon.decode(beacon.encode());

      expect(decoded.kind, BeaconKind.announce);
      expect(decoded.nonce, 'abcdef0123456789');
      expect(decoded.device.fingerprint, device.fingerprint);
      expect(decoded.device.alias, 'device-a');
      expect(decoded.device.platform, DevicePlatform.windows);
      expect(decoded.device.listenPort, 51001);
      expect(decoded.device.capability, device.capability);
    });

    test('a probe round-trips as a probe, not as an announce', () {
      final decoded = Beacon.decode(
        Beacon(
          kind: BeaconKind.probe,
          device: device,
          nonce: '0123456789abcdef',
        ).encode(),
      );

      expect(decoded.kind, BeaconKind.probe);
    });

    test('carries presence only, never key material', () {
      // The negative guarantee: a beacon is unauthenticated and readable by
      // anyone on the link, so its payload must hold nothing a stranger could
      // use to impersonate a Device or to derive session keys.
      final encoded = utf8.decode(
        Beacon(
          kind: BeaconKind.announce,
          device: device,
          nonce: '0123456789abcdef',
        ).encode(),
      );

      final json = jsonDecode(encoded)! as Map<String, Object?>;
      expect(json.keys.toSet(), {'v', 'k', 'n', 'device'});
      final announced = json['device']! as Map<String, Object?>;
      expect(announced.keys.toSet(), {
        'fp',
        'alias',
        'platform',
        'clip',
        'port',
      });
      expect(encoded.toLowerCase(), isNot(contains('secret')));
      expect(encoded.toLowerCase(), isNot(contains('key')));
    });

    test('rejects a version this build does not speak', () {
      expect(
        () => Beacon.decode(beaconJson(version: beaconVersion + 1)),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects an unknown kind', () {
      expect(
        () => Beacon.decode(beaconJson(kind: 'shout')),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects a datagram that is not UTF-8 JSON', () {
      expect(
        () => Beacon.decode(utf8.encode('not json at all')),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => Beacon.decode([0xff, 0xfe, 0xfd, 0xfc]),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects a JSON value that is not an object', () {
      expect(
        () => Beacon.decode(utf8.encode('[1, 2, 3]')),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects a datagram above the size ceiling', () {
      expect(
        () => Beacon.decode(List<int>.filled(maxBeaconBytes + 1, 0x41)),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects a nonce that is missing or too short', () {
      for (final nonce in <Object?>[null, 42, '', 'abcdefg']) {
        expect(
          () => Beacon.decode(beaconJson(nonce: nonce)),
          throwsA(isA<ProtocolException>()),
          reason: 'nonce $nonce must be rejected',
        );
      }
    });

    test('rejects a device object that is malformed', () {
      expect(
        () => Beacon.decode(beaconJson(deviceJson: 'device')),
        throwsA(isA<ProtocolException>()),
      );
      final missingFingerprint = Map<String, Object?>.from(device.toJson())
        ..remove('fp');
      expect(
        () => Beacon.decode(beaconJson(deviceJson: missingFingerprint)),
        throwsA(isA<ProtocolException>()),
      );
    });

    test(
      'a device alias is sanitised on the way in, as it is in a handshake',
      () {
        final hostile = Beacon.decode(
          beaconJson(
            deviceJson: {
              ...device.toJson(),
              'alias': 'evil\u0000name\u001b[31m',
            },
          ),
        );

        expect(hostile.device.alias, 'evilname[31m');
        expect(hostile.device.alias, isNot(contains('\u0000')));
      },
    );
  });
}

import 'dart:async';
import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

/// A transport whose receive stream is single-subscription, like the real
/// UDP one.
///
/// The in-memory hub in the core layer broadcasts, so a second listener over
/// it is harmless - which is exactly why the memory hub cannot catch a bug
/// that only a real socket shows. This one cannot be listened to twice.
final class SingleSubscriptionTransport implements BeaconTransport {
  final StreamController<BeaconDatagram> _received =
      StreamController<BeaconDatagram>();

  @override
  Stream<BeaconDatagram> get received => _received.stream;

  @override
  void send(
    List<int> datagram, {
    required InternetAddress address,
    required int port,
  }) {}

  @override
  void broadcast(List<int> datagram) {}

  @override
  Future<void> close() async {
    if (!_received.isClosed) await _received.close();
  }
}

void main() {
  group('DiscoveryService over a single-subscription transport', () {
    test(
      'a second service over the same transport cannot listen to it',
      () async {
        // This is the shape of the defect: one transport, two services. The
        // second one throws, and the exception is what took the whole
        // application down at startup.
        final transport = SingleSubscriptionTransport();
        addTearDown(transport.close);

        final first = DiscoveryService(
          transport: transport,
          local: _descriptor(pairingPort: null),
        );
        first.start();
        addTearDown(first.close);

        final second = DiscoveryService(
          transport: transport,
          local: _descriptor(pairingPort: 47656),
        );
        addTearDown(second.close);

        expect(second.start, throwsA(isA<StateError>()));
      },
    );

    test('the same Device changing its ports keeps one service', () async {
      // The way out: a descriptor that changes is handed to the running
      // service rather than becoming a second one over the same transport.
      final transport = SingleSubscriptionTransport();
      addTearDown(transport.close);

      final service = DiscoveryService(
        transport: transport,
        local: _descriptor(pairingPort: null),
      );
      addTearDown(service.close);
      service.start();

      service.updateLocal(_descriptor(pairingPort: 47656));

      expect(service.local.pairingPort, 47656);
      // And the service is still the only listener: nothing threw, and the
      // descriptor really was swapped.
      expect(service.isRunning, isTrue);
    });
  });
}

DeviceDescriptor _descriptor({required int? pairingPort}) => DeviceDescriptor(
  fingerprint: Fingerprint('a' * 64),
  alias: 'Desk',
  platform: DevicePlatform.windows,
  capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
  listenPort: 47655,
  pairingPort: pairingPort,
);

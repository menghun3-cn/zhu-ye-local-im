import 'package:local_transfer/core/core.dart';

import '../support/harness.dart';

/// Two Devices with a Session each, split by a hub.
final class HubPair {
  HubPair(this.aliceDevice, this.bobDevice, this.aliceHub, this.bobHub);

  final DeviceDescriptor aliceDevice;
  final DeviceDescriptor bobDevice;
  final SessionHub aliceHub;
  final SessionHub bobHub;

  /// An engine over Alice's transfer conversation.
  TransferEngine engineAtAlice() => TransferEngine(channel: aliceHub.transfers);

  /// An engine over Bob's transfer conversation.
  TransferEngine engineAtBob() => TransferEngine(channel: bobHub.transfers);

  Future<void> close() async {
    await aliceHub.close();
    await bobHub.close();
  }
}

/// Builds the pair, completing both handshakes before returning.
Future<HubPair> connectedHubs() async {
  final aliceDevice = testDevice('alice');
  final bobDevice = testDevice('bob');
  final secret = PairingSecret.fromBytes(List.filled(32, 7));
  final transport = MemoryTransportPair();
  final links = await Future.wait([
    SecureLink.establish(
      transport: transport.a,
      role: LinkRole.initiator,
      local: aliceDevice,
      secret: secret,
    ),
    SecureLink.establish(
      transport: transport.b,
      role: LinkRole.responder,
      local: bobDevice,
      secret: secret,
    ),
  ]);
  return HubPair(
    aliceDevice,
    bobDevice,
    SessionHub(links[0]),
    SessionHub(links[1]),
  );
}

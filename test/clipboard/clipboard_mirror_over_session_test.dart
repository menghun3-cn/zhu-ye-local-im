import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../session/support.dart';
import '../support/harness.dart';
import 'support.dart';

/// A Device with a mirror over its own clipboard and its Session's clipboard
/// conversation.
final class MirroringDevice {
  MirroringDevice({
    required this.device,
    required this.peer,
    required this.hub,
    required OwnerGroup group,
    ClipboardMode mode = ClipboardMode.mirror,
    Set<Fingerprint> allowedPeers = const {},
    bool allowEveryoneInGroup = false,
  }) : clipboard = MemorySystemClipboard() {
    mirror = ClipboardMirror(
      group: group,
      // See `MirrorFixture` for why the whitelist is spelled out rather than
      // defaulted: the tests about the *other* gates ask for it explicitly, so
      // a passing assertion cannot be an empty whitelist's doing.
      allowedPeers: allowEveryoneInGroup ? group.members.toSet() : allowedPeers,
      capability: ClipboardCapability.forPlatform(device.platform),
      clipboard: clipboard,
      mode: mode,
    );
    mirror.attachPeer(fingerprint: peer, channel: hub.clipboard);
    mirror.start();
  }

  final DeviceDescriptor device;
  final Fingerprint peer;
  final SessionHub hub;
  final MemorySystemClipboard clipboard;
  late final ClipboardMirror mirror;

  Future<void> close() async {
    await mirror.close();
    await clipboard.close();
  }
}

/// Builds a pair of Devices that have paired with each other.
Future<(MirroringDevice, MirroringDevice, HubPair)> connectedMirrors() async {
  final pair = await connectedHubs();
  final alice = MirroringDevice(
    device: pair.aliceDevice,
    peer: pair.aliceHub.peer,
    hub: pair.aliceHub,
    group: OwnerGroup(
      self: pair.aliceDevice.fingerprint,
      members: [pair.bobDevice.fingerprint],
    ),
    // Each side has added the other, which is what sharing requires: neither
    // list is self-granting.
    allowedPeers: {pair.bobDevice.fingerprint},
  );
  final bob = MirroringDevice(
    device: pair.bobDevice,
    peer: pair.bobHub.peer,
    hub: pair.bobHub,
    group: OwnerGroup(
      self: pair.bobDevice.fingerprint,
      members: [pair.aliceDevice.fingerprint],
    ),
    allowedPeers: {pair.aliceDevice.fingerprint},
  );
  return (alice, bob, pair);
}

void main() {
  group('mirroring over a real Session', () {
    test('lands a copy on the other Device, and does not bounce back', () async {
      final (alice, bob, pair) = await connectedMirrors();

      alice.clipboard.copy('copied on alice');
      await until(() => bob.clipboard.applied.length == 1, description: '对端应用');

      expect(bob.clipboard.applied.single, 'copied on alice');
      // Bob's platform reported a change when the entry was applied. Mirroring
      // that change back would start a loop with no end, so give the round trip
      // time to happen and then check the clipboard was written exactly once —
      // the copy itself.
      await settle();
      expect(alice.clipboard.history, ['copied on alice']);
      expect(alice.clipboard.applied, isEmpty);

      await alice.close();
      await bob.close();
      await pair.close();
    });

    test('carries a copy only to Devices in the Owner Group', () async {
      final pair = await connectedHubs();
      // Alice's mirror knows Bob's Session, but Bob is not in her group.
      // Bob *is* on her whitelist, though, so what stops the copy is the
      // group and not an empty list.
      final alice = MirroringDevice(
        device: pair.aliceDevice,
        peer: pair.aliceHub.peer,
        hub: pair.aliceHub,
        group: OwnerGroup(self: pair.aliceDevice.fingerprint),
        allowedPeers: {pair.bobDevice.fingerprint},
      );
      final bobClipboard = MemorySystemClipboard();
      final bobMirror = ClipboardMirror(
        group: OwnerGroup(self: pair.bobDevice.fingerprint),
        allowedPeers: {pair.aliceDevice.fingerprint},
        capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
        clipboard: bobClipboard,
        mode: ClipboardMode.mirror,
      );
      bobMirror.attachPeer(
        fingerprint: pair.bobHub.peer,
        channel: pair.bobHub.clipboard,
      );
      bobMirror.start();

      alice.clipboard.copy('a password');
      await settle();
      expect(bobClipboard.applied, isEmpty);

      await alice.close();
      await bobMirror.close();
      await bobClipboard.close();
      await pair.close();
    });

    test(
      'keeps working alongside a file Transfer on the same Session',
      () async {
        final (alice, bob, pair) = await connectedMirrors();
        final sender = pair.engineAtAlice();
        final receiver = pair.engineAtBob();
        final received = <IncomingTransfer>[];
        receiver.incoming.listen((transfer) async {
          received.add(transfer);
          await transfer.reject(RejectionReason.declined);
        });

        alice.clipboard.copy('copied on alice');
        await sender.sendText('something typed on alice');

        await until(() => received.isNotEmpty, description: '一次传输');
        await until(
          () => bob.clipboard.applied.length == 1,
          description: '对端应用',
        );

        expect(received.single.text, 'something typed on alice');
        expect(bob.clipboard.applied.single, 'copied on alice');

        await alice.close();
        await bob.close();
        await pair.close();
      },
    );
  });
}

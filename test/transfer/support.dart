import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:local_transfer/core/core.dart';

import '../support/harness.dart';

/// SHA-256 of [bytes] as lowercase hex, for Offers a test builds by hand.
String sha256Hex(List<int> bytes) => toHex(sha256.convert(bytes).bytes);

/// The sinks one accepted Offer wrote into, by item id.
final class MemoryReceipt {
  MemoryReceipt(this.transfer, this.sinks);

  /// The Transfer that was accepted.
  final IncomingTransfer transfer;

  /// Where each item's bytes went.
  final Map<String, MemoryPayloadSink> sinks;

  /// The bytes that arrived for [itemId].
  Uint8List bytesOf(String itemId) => sinks[itemId]!.bytes;

  /// The bytes that arrived for [itemId], read as text.
  String textOf(String itemId) => utf8.decode(bytesOf(itemId));

  /// The body of a text or clipboard payload, which travels in the Offer.
  String? get inlineText => transfer.text;
}

/// Accepts every item of [transfer] into memory.
///
/// The sinks are handed back so a test can read what arrived, and so a test can
/// write a prefix into one first and watch the sender resume from it.
Future<MemoryReceipt> acceptIntoMemory(IncomingTransfer transfer) async {
  final sinks = <String, MemoryPayloadSink>{};
  for (final item in transfer.items) {
    if (item.hasDigest) sinks[item.id] = MemoryPayloadSink();
  }
  await transfer.accept(
    itemIds: [for (final item in transfer.items) item.id],
    sinks: sinks,
  );
  return MemoryReceipt(transfer, sinks);
}

/// A Device with a Session to another Device and a Transfer engine over it.
final class Peer {
  Peer(this.device, this.link, this.engine);

  /// What this Device announced in the handshake.
  final DeviceDescriptor device;

  /// The established Session.
  final SecureLink link;

  /// The Transfer engine running on that Session.
  final TransferEngine engine;
}

/// A receiver that answers Offers the way an uninterested app would not: it
/// takes everything, in memory, and keeps what arrived.
///
/// Exists because most transfer behaviour is only observable from the far end:
/// what a test checks is not that a send call returned, but that the bytes the
/// other Device ended up holding are the bytes that were offered.
final class MemoryReceiver {
  MemoryReceiver(this.peer) {
    peer.engine.incoming.listen(_onOffer);
  }

  /// The Device doing the receiving.
  final Peer peer;

  /// Offers that have arrived, in order.
  final List<IncomingTransfer> offers = [];

  /// What each accepted Offer produced.
  final List<MemoryReceipt> receipts = [];

  /// When set, every new Offer is refused with this reason instead of accepted.
  RejectionReason? refuseWith;

  /// Waits until [count] Offers have been answered.
  Future<void> answered(int count) =>
      until(() => receipts.length + rejected >= count, description: '回答数');

  /// How many Offers have been refused.
  int rejected = 0;

  Future<void> _onOffer(IncomingTransfer transfer) async {
    offers.add(transfer);
    final reason = refuseWith;
    if (reason != null) {
      rejected++;
      await transfer.reject(reason);
      return;
    }
    receipts.add(await acceptIntoMemory(transfer));
  }
}

/// Two Devices with a Session and an engine each, talking in memory.
final class PeerPair {
  PeerPair(this.alice, this.bob);

  final Peer alice;
  final Peer bob;

  /// A receiver that accepts everything Alice sends.
  MemoryReceiver receiverAtBob() => MemoryReceiver(bob);

  /// A receiver that accepts everything Bob sends.
  MemoryReceiver receiverAtAlice() => MemoryReceiver(alice);

  Future<void> close() async {
    await alice.engine.close();
    await bob.engine.close();
    await alice.link.close();
    await bob.link.close();
  }
}

/// Builds the pair, completing both handshakes before returning.
Future<PeerPair> connectedPeers({
  TransferLimits limits = TransferLimits.defaults,
}) async {
  final alice = testDevice('alice');
  final bob = testDevice('bob');
  final secret = PairingSecret.fromBytes(List.filled(32, 7));
  final transport = MemoryTransportPair();
  final links = await Future.wait([
    SecureLink.establish(
      transport: transport.a,
      role: LinkRole.initiator,
      local: alice,
      secret: secret,
    ),
    SecureLink.establish(
      transport: transport.b,
      role: LinkRole.responder,
      local: bob,
      secret: secret,
    ),
  ]);
  return PeerPair(
    Peer(
      alice,
      links[0],
      TransferEngine(channel: SecureLinkChannel(links[0]), limits: limits),
    ),
    Peer(
      bob,
      links[1],
      TransferEngine(channel: SecureLinkChannel(links[1]), limits: limits),
    ),
  );
}

/// A [TransferChannel] a test drives by hand.
///
/// Stands in for a peer, so a test can push in exactly the messages and slices
/// a broken or hostile Device would have produced, and read back everything
/// this side sent without a socket in the way.
final class FakeChannel implements TransferChannel {
  final StreamController<WireMessage> _messages =
      StreamController<WireMessage>();
  final StreamController<ChunkFrame> _chunks = StreamController<ChunkFrame>();

  /// Control messages this side has sent.
  final List<WireMessage> sent = [];

  /// Payload slices this side has sent.
  final List<ChunkFrame> sentChunks = [];

  /// Notes passed to [TransferEngine.onNotice].
  final List<String> notices = [];

  /// Delivered to the engine as if the peer had sent it.
  void deliver(WireMessage message) => _messages.add(message);

  /// Delivered to the engine as if the peer had sent it.
  void deliverChunk(ChunkFrame frame) => _chunks.add(frame);

  /// The first message of type [T] this side sent, or null.
  T? sentOf<T extends WireMessage>() {
    for (final message in sent) {
      if (message is T) return message;
    }
    return null;
  }

  /// An engine reading from and writing to this channel.
  TransferEngine engineWith({
    TransferLimits limits = TransferLimits.defaults,
    int? randomSeed,
  }) => TransferEngine(
    channel: this,
    limits: limits,
    onNotice: notices.add,
    random: randomSeed == null ? null : Random(randomSeed),
  );

  @override
  Stream<WireMessage> get messages => _messages.stream;

  @override
  Stream<ChunkFrame> get chunks => _chunks.stream;

  @override
  Future<void> send(WireMessage message) async {
    sent.add(message);
  }

  @override
  Future<void> sendChunk({
    required String transferId,
    required String itemId,
    required int offset,
    required List<int> data,
  }) async {
    sentChunks.add(
      ChunkFrame(
        transferId: transferId,
        itemId: itemId,
        offset: offset,
        data: Uint8List.fromList(data),
      ),
    );
  }

  /// Closes both directions, as a dead Session would.
  Future<void> close() async {
    await _messages.close();
    await _chunks.close();
  }
}

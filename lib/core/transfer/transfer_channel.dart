import '../protocol/frame.dart';
import '../protocol/messages.dart';
import '../security/secure_link.dart';

/// The slice of an established Session that a Transfer needs.
///
/// Transfers are written against this rather than against [SecureLink] so their
/// state machines can be driven without a socket and without a handshake: a
/// test can hand a channel the exact messages a hostile or buggy peer would
/// have sent, and the only thing the transfer layer depends on is two streams
/// and two send calls.
abstract interface class TransferChannel {
  /// Control messages from the peer. Single-subscription.
  Stream<WireMessage> get messages;

  /// Bulk payload slices from the peer. Single-subscription.
  Stream<ChunkFrame> get chunks;

  /// Sends a control message to the peer.
  Future<void> send(WireMessage message);

  /// Sends one slice of an item's byte stream.
  Future<void> sendChunk({
    required String transferId,
    required String itemId,
    required int offset,
    required List<int> data,
  });
}

/// Adapts the [SecureLink] of an established Session to [TransferChannel].
final class SecureLinkChannel implements TransferChannel {
  SecureLinkChannel(this.link);

  /// The Session this channel speaks over.
  final SecureLink link;

  @override
  Stream<WireMessage> get messages => link.messages;

  @override
  Stream<ChunkFrame> get chunks => link.chunks;

  @override
  Future<void> send(WireMessage message) => link.send(message);

  @override
  Future<void> sendChunk({
    required String transferId,
    required String itemId,
    required int offset,
    required List<int> data,
  }) => link.sendChunk(
    transferId: transferId,
    itemId: itemId,
    offset: offset,
    data: data,
  );
}

/// Sends [message], tolerating a transport that is already gone.
///
/// Used for the messages that end a Transfer — a refusal, a cancellation, a
/// verification report. The Transfer is over either way, so a link that has
/// already died failing to say so is not worth turning into a second error.
Future<void> sendQuietly(TransferChannel channel, WireMessage message) async {
  try {
    await channel.send(message);
  } on Object {
    // Best effort by design; see above.
  }
}

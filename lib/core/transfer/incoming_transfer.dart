import 'dart:async';

import '../protocol/frame.dart';
import '../protocol/messages.dart';
import 'payload_sink.dart';
import 'transfer.dart';
import 'transfer_channel.dart';

/// The receiver's side of one Transfer.
///
/// An incoming Transfer is inert until somebody answers it. The engine hands it
/// to the app, the app decides, and only then does the sender learn it may
/// start. Nothing is created on disk, no byte is counted and no commitment is
/// made before that decision — which is the whole reason the Offer exists as a
/// separate round trip rather than the sender simply streaming.
final class IncomingTransfer extends Transfer {
  /// Internal: constructed by `TransferEngine`.
  IncomingTransfer.internal({
    required super.id,
    required super.kind,
    required super.items,
    super.text,
    required this._channel,
  }) : super(direction: TransferDirection.incoming);

  final TransferChannel _channel;
  final Map<String, PayloadSink> _sinks = {};
  late final Map<String, PayloadItem> _byId = {
    for (final item in items) item.id: item,
  };

  /// Where each accepted item's bytes are being written.
  Map<String, PayloadSink> get sinks => Map.unmodifiable(_sinks);

  /// Whether the Offer can still be answered.
  bool get isDecidable => state == TransferState.awaitingDecision;

  /// Accepts [itemIds] and says where each item's bytes should go.
  ///
  /// [sinks] must name a sink for every accepted item that has a byte stream of
  /// its own. How many bytes a sink already holds becomes the offset this
  /// Device asks the sender to start from, so handing over the partial file
  /// kept from an interrupted attempt resumes it instead of starting again.
  ///
  /// Throws [ArgumentError] on an answer that does not fit the Offer, and
  /// [StateError] if the Offer has already been answered.
  Future<void> accept({
    required List<String> itemIds,
    Map<String, PayloadSink> sinks = const {},
  }) async {
    if (!isDecidable) {
      throw StateError('the offer has already been answered');
    }
    if (itemIds.isEmpty) {
      throw ArgumentError.value(
        itemIds,
        'itemIds',
        'an empty acceptance is a refusal; call reject() instead',
      );
    }

    final accepted = <PayloadItem>[];
    for (final itemId in itemIds) {
      final item = _byId[itemId];
      if (item == null) {
        throw ArgumentError.value(
          itemId,
          'itemIds',
          'the offer names no such item',
        );
      }
      if (accepted.contains(item)) {
        throw ArgumentError.value(
          itemId,
          'itemIds',
          'the item is listed twice',
        );
      }
      accepted.add(item);
    }

    for (final entry in sinks.entries) {
      if (!accepted.any((item) => item.id == entry.key)) {
        throw ArgumentError(
          'a sink was given for "${entry.key}", which is not accepted',
        );
      }
    }
    for (final item in accepted) {
      final sink = sinks[item.id];
      if (item.hasDigest) {
        if (sink == null) {
          throw ArgumentError(
            'item "${item.id}" streams bytes and needs a sink to write them '
            'into',
          );
        }
        if (sink.bytesWritten > item.size) {
          throw ArgumentError(
            'the sink for "${item.id}" already holds ${sink.bytesWritten} '
            'bytes, more than the ${item.size} the offer declares',
          );
        }
      } else if (sink != null) {
        throw ArgumentError(
          'item "${item.id}" carries its body in the offer, so it takes no '
          'sink',
        );
      }
    }

    _sinks.addAll(sinks);
    final resume = <String, int>{
      for (final entry in _sinks.entries)
        if (entry.value.bytesWritten > 0) entry.key: entry.value.bytesWritten,
    };
    final already = resume.values.fold(0, (sum, bytes) => sum + bytes);
    acceptItems(accepted, alreadyTransferred: already);

    try {
      await _channel.send(
        AcceptMessage(
          transferId: id,
          acceptedItemIds: [for (final item in accepted) item.id],
          resumeOffsets: resume,
        ),
      );
    } on Object catch (error) {
      finish(TransferFailed(reason: RejectionReason.ioError, detail: '$error'));
    }
  }

  /// Declines the Offer. The sender is told why.
  ///
  /// Throws [StateError] if the Offer has already been answered.
  Future<void> reject([
    RejectionReason reason = RejectionReason.declined,
  ]) async {
    if (!isDecidable) {
      throw StateError('the offer has already been answered');
    }
    finish(TransferRejected(reason));
    await sendQuietly(_channel, RejectMessage(transferId: id, reason: reason));
  }

  /// Abandons the Transfer and tells the sender why.
  ///
  /// Bytes already written are left where they are: they are what makes the
  /// attempt resumable.
  Future<void> cancel([
    RejectionReason reason = RejectionReason.declined,
  ]) async {
    if (isSettled) return;
    finish(TransferCancelled(reason, byPeer: false));
    await sendQuietly(_channel, CancelMessage(transferId: id, reason: reason));
  }

  /// Internal: a slice of payload arrived.
  Future<void> onChunk(ChunkFrame frame) async {
    if (isSettled) return;
    if (state != TransferState.transferring) {
      await _fail(
        const TransferFailed(
          reason: RejectionReason.refused,
          detail: 'a slice arrived before the offer was answered',
        ),
      );
      return;
    }
    final item = _byId[frame.itemId];
    if (item == null) {
      await _fail(
        TransferFailed(
          reason: RejectionReason.refused,
          detail:
              'a slice arrived for item "${frame.itemId}", which the offer '
              'does not name',
        ),
      );
      return;
    }
    final sink = _sinks[frame.itemId];
    if (sink == null) {
      await _fail(
        TransferFailed(
          reason: RejectionReason.refused,
          itemId: item.id,
          detail: 'a slice arrived for an item that was not accepted',
        ),
      );
      return;
    }
    final end = frame.offset + frame.data.length;
    if (end > item.size) {
      await _fail(
        TransferFailed(
          reason: RejectionReason.corrupt,
          itemId: item.id,
          detail:
              'a slice ends at $end, past the ${item.size} bytes the offer '
              'declares',
        ),
      );
      return;
    }
    try {
      await sink.write(frame.offset, frame.data);
    } on ProtocolException catch (error) {
      await _fail(
        TransferFailed(
          reason: RejectionReason.corrupt,
          itemId: item.id,
          detail: error.message,
        ),
      );
      return;
    } on Object catch (error) {
      await _fail(
        TransferFailed(
          reason: RejectionReason.ioError,
          itemId: item.id,
          detail: '$error',
        ),
      );
      return;
    }
    addTransferred(frame.data.length);
  }

  /// Internal: the sender says every accepted item is on the wire.
  ///
  /// This is where an item becomes a fact: each one has to be the declared
  /// length and hash to the digest the sender promised before any byte moved.
  /// Only then is the sender told the copy is good.
  Future<void> onComplete(CompleteMessage message) async {
    if (isSettled) return;
    if (state != TransferState.transferring) {
      await _fail(
        const TransferFailed(
          reason: RejectionReason.refused,
          detail: 'the sender finished a transfer that was never answered',
        ),
      );
      return;
    }
    setState(TransferState.verifying);

    final digests = <String, String>{};
    for (final item in acceptedItems) {
      final sink = _sinks[item.id];
      if (sink == null) continue;
      if (sink.bytesWritten != item.size) {
        await _fail(
          TransferFailed(
            reason: RejectionReason.corrupt,
            itemId: item.id,
            detail:
                'received ${sink.bytesWritten} of the ${item.size} bytes the '
                'offer declares',
          ),
        );
        return;
      }
      final String actual;
      try {
        actual = await sink.digest();
      } on Object catch (error) {
        await _fail(
          TransferFailed(
            reason: RejectionReason.ioError,
            itemId: item.id,
            detail: '$error',
          ),
        );
        return;
      }
      final expected = item.digest;
      if (expected != null && actual != expected) {
        await _fail(
          TransferFailed(
            reason: RejectionReason.corrupt,
            itemId: item.id,
            detail:
                'the bytes received hash to $actual, the offer says $expected',
          ),
        );
        return;
      }
      digests[item.id] = actual;
    }

    finish(TransferCompleted(digests: digests));
    await sendQuietly(
      _channel,
      VerifiedMessage(transferId: id, digests: digests),
    );
  }

  /// Internal: the sender reported a failure.
  void onFailed(FailedMessage message) {
    finish(TransferFailed(reason: message.reason, itemId: message.itemId));
  }

  /// Internal: the sender abandoned the Transfer.
  void onCancel(CancelMessage message) {
    finish(TransferCancelled(message.reason, byPeer: true));
  }

  /// Internal: the Session failed or ended before the Transfer did.
  @override
  void onChannelError(Object error) {
    finish(TransferFailed(detail: '$error'));
  }

  @override
  void onSettled() {
    unawaited(_closeSinks());
  }

  Future<void> _fail(TransferFailed failure) async {
    if (isSettled) return;
    finish(failure);
    final reason = failure.reason;
    if (reason == null) return;
    await sendQuietly(
      _channel,
      FailedMessage(transferId: id, reason: reason, itemId: failure.itemId),
    );
  }

  Future<void> _closeSinks() async {
    for (final sink in _sinks.values) {
      try {
        await sink.close();
      } on Object {
        // Best effort: a handle that will not close is not worth turning a
        // finished transfer into a failed one, and the partial bytes are
        // deliberately left behind for a resume either way.
      }
    }
  }
}

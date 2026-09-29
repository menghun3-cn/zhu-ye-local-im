import 'dart:async';
import 'dart:math' as math;

import '../protocol/messages.dart';
import 'byte_source.dart';
import 'transfer.dart';
import 'transfer_channel.dart';
import 'transfer_limits.dart';

/// One item a caller wants to send.
final class OutgoingItem {
  OutgoingItem({required this.name, required this.source});

  /// The name the receiver will show. It is sanitised on arrival, so a caller
  /// may pass whatever name it happens to have.
  final String name;

  /// The bytes to send.
  final ByteSource source;
}

/// The sender's side of one Transfer.
///
/// Owns the Offer, waits for the answer, streams the accepted items, and then
/// waits for the receiver to say what it verified. It ends when the outcome is
/// known, and only then: a Transfer that has stopped sending is not finished
/// until the bytes have been checked at the far end.
final class OutgoingTransfer extends Transfer {
  /// Internal: constructed by `TransferEngine`, which has already hashed the
  /// sources and put those digests in the Offer.
  OutgoingTransfer.internal({
    required super.id,
    required super.kind,
    required super.items,
    super.text,
    required this._channel,
    required this._limits,
    required this._sources,
    required this._digests,
  }) : super(direction: TransferDirection.outgoing);

  final TransferChannel _channel;
  final TransferLimits _limits;
  final Map<String, ByteSource> _sources;
  final Map<String, String> _digests;
  final Map<String, int> _resumeOffsets = {};
  Timer? _timer;

  /// Internal: starts the clock on an Offer nobody has answered.
  void watchAcceptance() {
    _timer = Timer(_limits.acceptanceTimeout, () {
      if (state == TransferState.awaitingDecision) {
        finish(
          TransferFailed(
            detail:
                'the peer did not answer the offer within '
                '${_limits.acceptanceTimeout.inSeconds}s',
          ),
        );
      }
    });
  }

  /// Internal: the receiver answered the Offer.
  ///
  /// Everything in the answer is checked against the Offer first. An
  /// acceptance naming an item that was never offered, or a resume offset past
  /// the end of one, is a peer that is confused or lying, and both are much
  /// clearer here than as a curious failure halfway through the payload.
  Future<void> onAccept(AcceptMessage message) async {
    if (isSettled) return;
    if (state != TransferState.awaitingDecision) {
      finish(
        TransferFailed(detail: 'the peer answered an offer that was answered'),
      );
      return;
    }
    _timer?.cancel();

    final byId = {for (final item in items) item.id: item};
    final accepted = <PayloadItem>[];
    for (final itemId in message.acceptedItemIds) {
      final item = byId[itemId];
      if (item == null) {
        finish(
          TransferFailed(
            detail:
                'the peer accepted item "$itemId", which the offer does not '
                'name',
          ),
        );
        return;
      }
      accepted.add(item);
    }
    if (accepted.isEmpty) {
      // Accepting nothing is what refusing looks like from the sender's side.
      finish(const TransferRejected(RejectionReason.declined));
      return;
    }

    var already = 0;
    for (final entry in message.resumeOffsets.entries) {
      final item = byId[entry.key];
      if (item == null || !accepted.contains(item)) {
        finish(
          TransferFailed(
            detail:
                'the peer asked to resume item "${entry.key}", which it did '
                'not accept',
          ),
        );
        return;
      }
      if (entry.value < 0 || entry.value > item.size) {
        finish(
          TransferFailed(
            detail:
                'the peer asked to resume item "${entry.key}" at '
                '${entry.value} of ${item.size} bytes',
          ),
        );
        return;
      }
      _resumeOffsets[entry.key] = entry.value;
      already += entry.value;
    }

    acceptItems(accepted, alreadyTransferred: already);
    await _sendAcceptedItems();
  }

  /// Internal: the peer declined the Offer.
  void onReject(RejectMessage message) {
    finish(TransferRejected(message.reason));
  }

  /// Internal: the receiver reported the result of its own verification.
  void onVerified(VerifiedMessage message) {
    if (isSettled) return;
    if (state != TransferState.verifying) {
      finish(
        TransferFailed(detail: 'the peer confirmed an unfinished transfer'),
      );
      return;
    }
    _timer?.cancel();

    final confirmed = <String, String>{};
    for (final item in acceptedItems) {
      final sent = _digests[item.id];
      if (sent == null) continue;
      final reported = message.digests[item.id];
      if (reported == null) {
        finish(
          TransferFailed(
            reason: RejectionReason.corrupt,
            itemId: item.id,
            detail:
                'the receiver did not report a digest for every item it '
                'accepted',
          ),
        );
        return;
      }
      if (reported != sent) {
        // The receiver's own hash disagrees with the sender's. Either the
        // bytes changed in flight or one end is lying; both mean the copy is
        // not the one that was offered.
        finish(
          TransferFailed(
            reason: RejectionReason.corrupt,
            itemId: item.id,
            detail:
                'the bytes that arrived hash to $reported, the bytes sent '
                'hash to $sent',
          ),
        );
        return;
      }
      confirmed[item.id] = sent;
    }
    finish(TransferCompleted(digests: confirmed));
  }

  /// Internal: the receiver reported a failure.
  void onFailed(FailedMessage message) {
    finish(TransferFailed(reason: message.reason, itemId: message.itemId));
  }

  /// Internal: the peer abandoned the Transfer.
  void onCancel(CancelMessage message) {
    finish(TransferCancelled(message.reason, byPeer: true));
  }

  /// Internal: the Session failed or ended before the Transfer did.
  @override
  void onChannelError(Object error) {
    finish(TransferFailed(detail: '$error'));
  }

  /// Abandons the Transfer and tells the peer why.
  Future<void> cancel([
    RejectionReason reason = RejectionReason.declined,
  ]) async {
    if (isSettled) return;
    finish(TransferCancelled(reason, byPeer: false));
    await sendQuietly(_channel, CancelMessage(transferId: id, reason: reason));
  }

  @override
  void onSettled() {
    _timer?.cancel();
    _timer = null;
    unawaited(_closeSources());
  }

  Future<void> _sendAcceptedItems() async {
    try {
      for (final item in acceptedItems) {
        final source = _sources[item.id];
        // A text or clipboard payload has no byte stream: its body arrived
        // inside the Offer and there is nothing to stream.
        if (source == null) continue;
        var offset = _resumeOffsets[item.id] ?? 0;
        while (offset < item.size) {
          final count = math.min(transferChunkBytes, item.size - offset);
          final data = await source.read(offset, count);
          if (data.isEmpty) {
            finish(
              TransferFailed(
                reason: RejectionReason.ioError,
                itemId: item.id,
                detail:
                    'the source of item "${item.id}" ended at $offset of '
                    '${item.size} bytes',
              ),
            );
            return;
          }
          await _channel.sendChunk(
            transferId: id,
            itemId: item.id,
            offset: offset,
            data: data,
          );
          offset += data.length;
          addTransferred(data.length);
        }
      }

      setState(TransferState.verifying);
      await _channel.send(CompleteMessage(transferId: id));
      _timer = Timer(_limits.verificationTimeout, () {
        if (state == TransferState.verifying) {
          finish(
            TransferFailed(
              detail:
                  'the receiver did not confirm the transfer within '
                  '${_limits.verificationTimeout.inSeconds}s',
            ),
          );
        }
      });
    } on Object catch (error) {
      finish(TransferFailed(reason: RejectionReason.ioError, detail: '$error'));
    }
  }

  Future<void> _closeSources() async {
    for (final source in _sources.values) {
      try {
        await source.close();
      } on Object {
        // Best effort: the handle a source would not release is the operating
        // system's problem now, and failing the Transfer over it would not
        // make anything better.
      }
    }
  }
}

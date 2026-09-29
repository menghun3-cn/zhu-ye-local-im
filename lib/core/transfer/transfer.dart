import 'dart:async';

import '../protocol/messages.dart';

/// How many payload bytes a Transfer puts in one chunk.
///
/// A protocol constant rather than a policy knob. A slice has to survive
/// framing and one sealed record, so its size is part of what two builds agree
/// on: 64 KiB stays far below the frame ceiling while keeping per-chunk framing
/// and AEAD overhead below a tenth of a percent, which is small enough that a
/// long transfer is not meaningfully more expensive than a raw stream.
const int transferChunkBytes = 64 * 1024;

/// Which side of a Transfer this Device is on.
enum TransferDirection {
  /// This Device is sending the payload.
  outgoing,

  /// This Device is receiving the payload.
  incoming,
}

/// Where a Transfer has got to.
///
/// The distinction that matters is between [awaitingDecision] — where nothing
/// has been agreed and no byte has moved — and everything after it. A receiver
/// that has not accepted an Offer has made no commitment and written nothing.
enum TransferState {
  /// Offered, or received as an Offer, and not yet answered.
  awaitingDecision,

  /// Accepted on both sides; payload bytes are moving.
  transferring,

  /// Every byte is across and each side is checking digests.
  verifying,

  /// Every accepted item arrived and matched its digest.
  completed,

  /// The receiver declined the Offer.
  rejected,

  /// One side abandoned the Transfer.
  cancelled,

  /// The Transfer could not complete.
  failed;

  /// Whether the Transfer has ended, whatever the ending was.
  bool get isSettled => switch (this) {
    TransferState.awaitingDecision ||
    TransferState.transferring ||
    TransferState.verifying => false,
    TransferState.completed ||
    TransferState.rejected ||
    TransferState.cancelled ||
    TransferState.failed => true,
  };
}

/// A Transfer's state and byte counts at one moment.
final class TransferProgress {
  const TransferProgress({
    required this.state,
    required this.transferredBytes,
    required this.totalBytes,
  });

  /// Where the Transfer has got to.
  final TransferState state;

  /// Payload bytes across so far.
  ///
  /// Counts bytes a resumed Transfer already held, so both ends of a resumed
  /// transfer report the same numbers and the same fraction.
  final int transferredBytes;

  /// Payload bytes the accepted items add up to.
  final int totalBytes;

  /// Bytes across as a fraction of the total, in `0..1`.
  double get fraction {
    if (totalBytes <= 0) return 1;
    return (transferredBytes / totalBytes).clamp(0, 1);
  }

  @override
  String toString() =>
      'TransferProgress(${state.name}, $transferredBytes/$totalBytes)';
}

/// How a Transfer ended.
///
/// One sealed family rather than a nullable reason plus a boolean, because
/// "finished", "the peer said no", "somebody gave up" and "it broke" are
/// mutually exclusive and each carries different detail.
sealed class TransferOutcome {
  const TransferOutcome();
}

/// Every accepted item arrived and matched the digest in its Offer.
final class TransferCompleted extends TransferOutcome {
  const TransferCompleted({required this.digests});

  /// Item id to SHA-256 of the bytes that arrived, as lowercase hex.
  ///
  /// Covers the items that have a byte stream of their own. The body of a text
  /// or clipboard payload travels inside the Offer, which the record layer has
  /// already authenticated, so there is nothing left to check for it.
  final Map<String, String> digests;

  @override
  String toString() => 'TransferCompleted(${digests.length} digests)';
}

/// The receiver declined the Offer.
final class TransferRejected extends TransferOutcome {
  const TransferRejected(this.reason);

  /// Why it was declined.
  final RejectionReason reason;

  @override
  String toString() => 'TransferRejected(${reason.wireName})';
}

/// One side abandoned the Transfer.
final class TransferCancelled extends TransferOutcome {
  const TransferCancelled(this.reason, {required this.byPeer});

  /// Why it was abandoned.
  final RejectionReason reason;

  /// Whether the peer asked for it, rather than this Device.
  final bool byPeer;

  @override
  String toString() => 'TransferCancelled(${reason.wireName}, byPeer: $byPeer)';
}

/// The Transfer could not complete.
final class TransferFailed extends TransferOutcome {
  const TransferFailed({this.reason, this.itemId, this.detail});

  /// The reason the peer reported, when the failure came back as a `failed`
  /// message.
  ///
  /// Null when this Device gave up on its own — a timeout, a transport that
  /// died, a source that ended early — because then there is no wire reason to
  /// report and inventing one would misdescribe what happened.
  final RejectionReason? reason;

  /// The offending item, when the failure is item-scoped.
  final String? itemId;

  /// What went wrong, for logs. Never shown to a peer.
  final String? detail;

  @override
  String toString() =>
      'TransferFailed(${reason?.wireName ?? 'local'}'
      '${itemId == null ? '' : ', item: $itemId'}'
      '${detail == null ? '' : ', $detail'})';
}

/// One Transfer, from the Offer to its outcome.
///
/// The base holds what both sides need and share: what was offered, how far it
/// has got, and how it ended. What differs — who proposes, who decides, which
/// direction bytes flow — lives in [OutgoingTransfer] and [IncomingTransfer].
abstract base class Transfer {
  Transfer({
    required this.id,
    required this.direction,
    required this.kind,
    required List<PayloadItem> items,
    this.text,
  }) : items = List<PayloadItem>.unmodifiable(items) {
    _updates = StreamController<TransferProgress>.broadcast(
      onListen: _listenerArrived,
    );
    _totalBytes = this.items.fold(0, (sum, item) => sum + item.size);
  }

  /// Identifies the Transfer for its whole life, and names its bytes on the
  /// wire.
  final String id;

  /// Which side of the Transfer this Device is on.
  final TransferDirection direction;

  /// What kind of Payload the Transfer carries.
  final PayloadKind kind;

  /// The items as the Offer described them.
  final List<PayloadItem> items;

  /// The body of a text or clipboard Payload, which travels inside the Offer.
  final String? text;

  // Built in the constructor body rather than here: a field initialiser cannot
  // reference the instance method that sends a late listener its first
  // snapshot.
  late final StreamController<TransferProgress> _updates;
  final Completer<TransferOutcome> _outcome = Completer<TransferOutcome>();

  TransferState _state = TransferState.awaitingDecision;
  int _transferred = 0;
  late int _totalBytes;
  List<PayloadItem> _accepted = const [];

  /// Where the Transfer has got to.
  TransferState get state => _state;

  /// Payload bytes across so far.
  int get transferredBytes => _transferred;

  /// Payload bytes the accepted items add up to.
  ///
  /// Before an Offer is answered this is every item on offer; afterwards it is
  /// only the items the receiver took.
  int get totalBytes => _totalBytes;

  /// The items the receiver agreed to take. Empty until an Offer is answered.
  List<PayloadItem> get acceptedItems => _accepted;

  /// Whether the Transfer has ended.
  bool get isSettled => _state.isSettled;

  /// The current state and byte counts.
  TransferProgress get progress => TransferProgress(
    state: _state,
    transferredBytes: _transferred,
    totalBytes: _totalBytes,
  );

  /// Emits after every change of state or byte count.
  ///
  /// The first listener is sent the current snapshot immediately, so a view
  /// that subscribes late starts from the truth rather than from zero.
  Stream<TransferProgress> get updates => _updates.stream;

  /// Completes once, when the Transfer ends.
  Future<TransferOutcome> get outcome => _outcome.future;

  /// Internal: ends the Transfer. Later calls are ignored.
  void finish(TransferOutcome outcome) {
    if (_outcome.isCompleted) return;
    _state = _stateFor(outcome);
    _emit();
    _outcome.complete(outcome);
    onSettled();
    unawaited(_updates.close());
  }

  /// Internal: sets the state without ending the Transfer.
  void setState(TransferState state) {
    if (_outcome.isCompleted) return;
    _state = state;
    _emit();
  }

  /// Internal: narrows the Transfer to the items that were accepted.
  ///
  /// [alreadyTransferred] is the payload a resumed Transfer inherits, counted
  /// from the start of the accepted items so both ends report the same numbers.
  void acceptItems(List<PayloadItem> accepted, {int alreadyTransferred = 0}) {
    if (_outcome.isCompleted) return;
    _accepted = List<PayloadItem>.unmodifiable(accepted);
    _totalBytes = _accepted.fold(0, (sum, item) => sum + item.size);
    // An item whose body travelled inside the Offer is already here. Counting
    // it as outstanding would leave a text transfer stuck at zero percent for
    // its whole life, and would make a finished one look unfinished.
    _transferred =
        alreadyTransferred +
        _accepted
            .where((item) => !item.hasDigest)
            .fold(0, (sum, item) => sum + item.size);
    _state = TransferState.transferring;
    _emit();
  }

  /// Internal: adds [bytes] to the count and notifies listeners.
  void addTransferred(int bytes) {
    if (_outcome.isCompleted) return;
    _transferred += bytes;
    _emit();
  }

  /// Internal: the Session failed, or ended before this Transfer did.
  ///
  /// Declared here so that whoever is tearing a Session down can end everything
  /// it was carrying without knowing which direction each Transfer ran in.
  void onChannelError(Object error);

  /// Called once, when the Transfer ends, to release whatever it was holding.
  void onSettled() {}

  void _emit() {
    if (_updates.isClosed) return;
    _updates.add(
      TransferProgress(
        state: _state,
        transferredBytes: _transferred,
        totalBytes: _totalBytes,
      ),
    );
  }

  void _listenerArrived() => _emit();

  static TransferState _stateFor(TransferOutcome outcome) => switch (outcome) {
    TransferCompleted() => TransferState.completed,
    TransferRejected() => TransferState.rejected,
    TransferCancelled() => TransferState.cancelled,
    TransferFailed() => TransferState.failed,
  };

  @override
  String toString() =>
      'Transfer($id, ${direction.name}, ${kind.wireName}, $_state, '
      '$_transferred/$_totalBytes)';
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../identity/fingerprint.dart';
import '../protocol/messages.dart';
import 'byte_source.dart';
import 'incoming_transfer.dart';
import 'outgoing_transfer.dart';
import 'transfer.dart';
import 'transfer_channel.dart';
import 'transfer_limits.dart';

/// Runs Transfers over one Session.
///
/// One engine per Session, because the engine owns the single subscription to
/// the Session's control and chunk streams. Those streams are
/// single-subscription: a second listener elsewhere in the app would not get a
/// copy of the frames, it would silently take them.
///
/// The engine routes, it does not decide. Whether an Offer is welcome is the
/// app's call, and it is asked before any byte moves — the one thing the engine
/// answers on its own is an Offer that breaks the size limits, which has to be
/// refused before the app could sensibly be asked at all.
///
/// ## One worker, in arrival order
///
/// Control messages and payload slices arrive on two separate streams, and the
/// engine funnels both into one queue that is drained a task at a time. It has
/// to: a `complete` means "every byte of every item is on the wire", so it may
/// only be handled once the slices before it have actually been written. Two
/// loops reading the two streams concurrently would let a `complete` overtake a
/// slice that was still being written to disk, and the receiver would then fail
/// a transfer whose bytes had all arrived.
final class TransferEngine {
  TransferEngine({
    required this._channel,
    this._limits = TransferLimits.defaults,
    this.onNotice,
    Random? random,
  }) : _random = random ?? Random.secure() {
    unawaited(_pumpMessages());
    unawaited(_pumpChunks());
  }

  final TransferChannel _channel;
  final TransferLimits _limits;
  final Random _random;

  /// Called with a readable line when the engine refuses or drops something.
  ///
  /// For logs and for whoever is debugging a pair of Devices. The peer only
  /// ever learns the wire reason; this is where the actual explanation goes.
  final void Function(String message)? onNotice;

  final StreamController<IncomingTransfer> _incoming =
      StreamController<IncomingTransfer>();
  final Map<String, OutgoingTransfer> _outgoingTransfers = {};
  final Map<String, IncomingTransfer> _incomingTransfers = {};
  final Set<String> _usedIds = {};
  final List<Future<void> Function()> _queue = [];
  Future<void>? _draining;
  bool _closed = false;

  /// Offers from the peer, in arrival order.
  ///
  /// An Offer waits here until it is answered, so a listener that subscribes a
  /// moment late still sees the offers that arrived first.
  Stream<IncomingTransfer> get incoming => _incoming.stream;

  /// The outgoing Transfers this Session is running, by transfer id.
  Map<String, OutgoingTransfer> get outgoing =>
      Map.unmodifiable(_outgoingTransfers);

  /// The incoming Transfers waiting to be answered, by transfer id.
  Map<String, IncomingTransfer> get pending =>
      Map.unmodifiable(_incomingTransfers);

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Offers [text] to the peer.
  Future<OutgoingTransfer> sendText(String text) =>
      _sendInline(PayloadKind.text, text);

  /// Offers clipboard content to a peer in the same Owner Group.
  ///
  /// A separate payload kind from text so that a receiver can tell content
  /// mirrored from another Device apart from content a person typed and chose
  /// to send. The two are applied very differently on arrival.
  Future<OutgoingTransfer> sendClipboard(String text) =>
      _sendInline(PayloadKind.clipboard, text);

  /// Offers [items] to the peer as one file payload.
  ///
  /// Every item is read through once here, to hash it. The digest in an Offer
  /// is a promise about bytes that have not moved yet, so the sender has to
  /// have seen them first.
  Future<OutgoingTransfer> sendFiles(List<OutgoingItem> items) async {
    if (items.isEmpty) {
      throw ArgumentError.value(
        items,
        'items',
        'a file offer needs at least one item',
      );
    }
    final descriptors = <PayloadItem>[];
    final sources = <String, ByteSource>{};
    final digests = <String, String>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final itemId = 'i$index';
      final digest = await digestOfSource(item.source);
      descriptors.add(
        PayloadItem(
          id: itemId,
          name: item.name,
          size: item.source.length,
          digest: digest,
        ),
      );
      sources[itemId] = item.source;
      digests[itemId] = digest;
    }
    return _start(
      kind: PayloadKind.file,
      items: descriptors,
      sources: sources,
      digests: digests,
    );
  }

  /// Stops routing.
  ///
  /// Live Transfers are failed, never quietly dropped. The Session itself is
  /// left alone: it belongs to whoever opened it, and it may still be carrying
  /// clipboard messages this engine knows nothing about.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _abandonAll('the transfer engine was closed');
    unawaited(_incoming.close());
  }

  Future<OutgoingTransfer> _sendInline(PayloadKind kind, String text) async {
    final itemId = kind.wireName;
    return _start(
      kind: kind,
      text: text,
      items: [
        PayloadItem(id: itemId, name: itemId, size: utf8.encode(text).length),
      ],
    );
  }

  Future<OutgoingTransfer> _start({
    required PayloadKind kind,
    required List<PayloadItem> items,
    Map<String, ByteSource> sources = const {},
    Map<String, String> digests = const {},
    String? text,
  }) async {
    if (_closed) {
      throw StateError('the transfer engine is closed');
    }
    final id = _newTransferId();
    final transfer = OutgoingTransfer.internal(
      id: id,
      kind: kind,
      items: items,
      text: text,
      channel: _channel,
      limits: _limits,
      sources: sources,
      digests: digests,
    );
    // Registered before the Offer goes out: a fast peer can answer before the
    // send future has completed, and an answer naming an unknown transfer is
    // dropped.
    _outgoingTransfers[id] = transfer;
    _forgetWhenSettled(transfer);
    try {
      await _channel.send(
        OfferMessage(transferId: id, kind: kind, items: items, text: text),
      );
    } on Object catch (error) {
      transfer.onChannelError(error);
      return transfer;
    }
    transfer.watchAcceptance();
    return transfer;
  }

  Future<void> _pumpMessages() async {
    try {
      await for (final message in _channel.messages) {
        if (_closed) break;
        _submit(() => _route(message));
      }
    } on Object catch (error) {
      _abandonAll('the session failed while receiving messages: $error');
      return;
    }
    // Anything already queued is still real work: a `complete` that arrived a
    // moment before the stream ended describes bytes that did arrive, and
    // failing a transfer over it would be wrong.
    await _settled();
    _abandonAll('the session ended');
  }

  Future<void> _pumpChunks() async {
    try {
      await for (final frame in _channel.chunks) {
        if (_closed) break;
        _submit(() async {
          final transfer = _incomingTransfers[frame.transferId];
          if (transfer != null) await transfer.onChunk(frame);
        });
      }
    } on Object catch (error) {
      _abandonAll('the session failed while receiving payload: $error');
      return;
    }
    await _settled();
    _abandonAll('the session ended');
  }

  Future<void> _route(WireMessage message) async {
    if (_closed) return;
    switch (message) {
      case OfferMessage():
        await _onOffer(message);
      case AcceptMessage():
        final transfer = _outgoingTransfers[message.transferId];
        if (transfer == null) {
          _noteUnknown('accept', message.transferId);
          return;
        }
        await transfer.onAccept(message);
      case RejectMessage():
        final transfer = _outgoingTransfers[message.transferId];
        if (transfer == null) {
          _noteUnknown('reject', message.transferId);
          return;
        }
        transfer.onReject(message);
      case CompleteMessage():
        final transfer = _incomingTransfers[message.transferId];
        if (transfer == null) {
          _noteUnknown('complete', message.transferId);
          return;
        }
        await transfer.onComplete(message);
      case VerifiedMessage():
        final transfer = _outgoingTransfers[message.transferId];
        if (transfer == null) {
          _noteUnknown('verified', message.transferId);
          return;
        }
        transfer.onVerified(message);
      case FailedMessage():
        final outgoing = _outgoingTransfers[message.transferId];
        if (outgoing != null) {
          outgoing.onFailed(message);
          return;
        }
        final incoming = _incomingTransfers[message.transferId];
        if (incoming == null) {
          _noteUnknown('failed', message.transferId);
          return;
        }
        incoming.onFailed(message);
      case CancelMessage():
        final outgoing = _outgoingTransfers[message.transferId];
        if (outgoing != null) {
          outgoing.onCancel(message);
          return;
        }
        final incoming = _incomingTransfers[message.transferId];
        if (incoming == null) {
          _noteUnknown('cancel', message.transferId);
          return;
        }
        incoming.onCancel(message);
      case HelloMessage():
      case HelloAckMessage():
      case SessionConfirmMessage():
      case PairAdmitMessage():
      case PairConfirmedMessage():
      case ClipboardMessage():
      case ErrorMessage():
        // Not the transfer layer's business: the handshake is history by the
        // time an engine exists, mirroring has its own listener, and a protocol
        // error is reported per Transfer rather than session-wide.
        break;
    }
  }

  Future<void> _onOffer(OfferMessage offer) async {
    // One id, one meaning, for the life of the Session. A peer that reused an
    // id could otherwise make the receiver answer an Offer on behalf of a
    // Transfer that is still running.
    if (!_usedIds.add(offer.transferId)) {
      onNotice?.call(
        'refused an offer reusing transfer id "${offer.transferId}"',
      );
      await _refuse(offer.transferId);
      return;
    }
    final violation = _limits.violationOf(offer);
    if (violation != null) {
      onNotice?.call('refused an offer: $violation');
      await _refuse(offer.transferId);
      return;
    }
    final transfer = IncomingTransfer.internal(
      id: offer.transferId,
      kind: offer.kind,
      items: offer.items,
      text: offer.text,
      channel: _channel,
    );
    _incomingTransfers[offer.transferId] = transfer;
    _forgetWhenSettled(transfer);
    _incoming.add(transfer);
  }

  Future<void> _refuse(String transferId) => sendQuietly(
    _channel,
    RejectMessage(transferId: transferId, reason: RejectionReason.refused),
  );

  void _forgetWhenSettled(Transfer transfer) {
    unawaited(
      transfer.outcome.then((_) {
        _outgoingTransfers.remove(transfer.id);
        _incomingTransfers.remove(transfer.id);
      }),
    );
  }

  void _abandonAll(String detail) {
    final live = <Transfer>[
      ..._outgoingTransfers.values,
      ..._incomingTransfers.values,
    ];
    _outgoingTransfers.clear();
    _incomingTransfers.clear();
    for (final transfer in live) {
      transfer.onChannelError(detail);
    }
  }

  void _noteUnknown(String type, String transferId) {
    onNotice?.call(
      'a "$type" message named transfer "$transferId", which this session is '
      'not running',
    );
  }

  /// Adds [task] to the single queue that routes frames in arrival order.
  void _submit(Future<void> Function() task) {
    _queue.add(task);
    _draining ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeAt(0);
        await task();
      }
    } on Object catch (error) {
      _abandonAll('the session failed while routing a frame: $error');
    } finally {
      _draining = null;
      if (_queue.isNotEmpty) _draining = _drain();
    }
  }

  /// Completes once everything submitted so far has been routed.
  Future<void> _settled() async {
    while (_draining != null) {
      await _draining;
    }
  }

  /// A transfer id the peer cannot collide with by guessing.
  ///
  /// Random rather than sequential: two Devices that start sending at the same
  /// moment must not pick the same id, and an id a hostile peer can predict is
  /// one it can race with a message of its own.
  String _newTransferId() {
    while (true) {
      final id = toHex(_randomBytes(12));
      if (_usedIds.add(id)) return id;
    }
  }

  Uint8List _randomBytes(int count) {
    final bytes = Uint8List(count);
    for (var index = 0; index < count; index++) {
      bytes[index] = _random.nextInt(256);
    }
    return bytes;
  }
}

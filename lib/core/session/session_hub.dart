import 'dart:async';

import '../clipboard/clipboard_channel.dart';
import '../identity/fingerprint.dart';
import '../protocol/frame.dart';
import '../protocol/messages.dart';
import '../security/secure_link.dart';
import '../transfer/transfer_channel.dart';

/// One Session, split between the conversations that share it.
///
/// A [SecureLink] exposes a single-subscription `messages` stream, so whatever
/// reads it first is the only thing that will ever read it: a second listener
/// does not get a copy, it silently loses every frame. A Session carries more
/// than one conversation — the transfer engine routes its own messages, and
/// Clipboard Mirroring carries [ClipboardMessage]s alongside them — so exactly
/// one object has to own the stream and fan it out. That object is this one.
///
/// The hub only *sorts*; it does not interpret. A message whose type belongs to
/// no conversation here is still handed to the transfer view, which is where
/// the engine already decides what to do with types it does not route.
///
/// Payload slices are passed straight through rather than intercepted: the
/// transfer engine is their only consumer, and a second controller in the path
/// would copy nothing but add a buffer that has to be drained.
final class SessionHub {
  SessionHub(this._link) {
    _subscription = _link.messages.listen(
      _dispatch,
      onError: _fail,
      onDone: _finish,
    );
  }

  final SecureLink _link;

  late final StreamSubscription<WireMessage> _subscription;

  final StreamController<WireMessage> _transferMessages =
      StreamController<WireMessage>();
  final StreamController<ClipboardMessage> _clipboardMessages =
      StreamController<ClipboardMessage>();

  bool _closed = false;

  /// The Session being split.
  SecureLink get link => _link;

  /// The Fingerprint the peer announced.
  ///
  /// A claim, not a fact: [SecureLink] proves the peer knows the Pairing
  /// Secret, not which Device it is. A caller that gates on it has to have
  /// pinned it first.
  Fingerprint get peer => _link.peer.fingerprint;

  /// The transfer conversation, for a [TransferEngine] to route.
  TransferChannel get transfers => _HubTransferChannel(this);

  /// The clipboard conversation, for a Clipboard Mirror to apply.
  ClipboardChannel get clipboard => _HubClipboardChannel(this);

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Tears the Session down: the subscription, both views, and the link.
  ///
  /// Closes the link as well as the views, because the hub is what owns it —
  /// a session with no hub has nobody left to route it.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    // Deliberately not awaited: a controller's close future only completes
    // once its done event has been delivered, which never happens for a view
    // nobody subscribed to. Awaiting here would deadlock closing a Session
    // whose clipboard conversation was never used.
    unawaited(_transferMessages.close());
    unawaited(_clipboardMessages.close());
    await _link.close();
  }

  void _dispatch(WireMessage message) {
    if (_closed) return;
    switch (message) {
      case ClipboardMessage():
        _clipboardMessages.add(message);
      case HelloMessage():
      case HelloAckMessage():
        // The handshake is history by the time a hub exists: both sides sent
        // theirs before the link was returned.
        break;
      default:
        _transferMessages.add(message);
    }
  }

  void _fail(Object error, StackTrace stack) {
    if (_closed) return;
    _transferMessages.addError(error, stack);
    _clipboardMessages.addError(error, stack);
    _finish();
  }

  void _finish() {
    if (!_closed) _closed = true;
    unawaited(_transferMessages.close());
    unawaited(_clipboardMessages.close());
  }
}

final class _HubTransferChannel implements TransferChannel {
  _HubTransferChannel(this._hub);

  final SessionHub _hub;

  @override
  Stream<WireMessage> get messages => _hub._transferMessages.stream;

  @override
  Stream<ChunkFrame> get chunks => _hub._link.chunks;

  @override
  Future<void> send(WireMessage message) => _hub._link.send(message);

  @override
  Future<void> sendChunk({
    required String transferId,
    required String itemId,
    required int offset,
    required List<int> data,
  }) => _hub._link.sendChunk(
    transferId: transferId,
    itemId: itemId,
    offset: offset,
    data: data,
  );
}

final class _HubClipboardChannel implements ClipboardChannel {
  _HubClipboardChannel(this._hub);

  final SessionHub _hub;

  @override
  Stream<ClipboardMessage> get entries => _hub._clipboardMessages.stream;

  @override
  Future<void> send(ClipboardMessage message) => _hub._link.send(message);
}

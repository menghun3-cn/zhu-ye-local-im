import 'dart:async';
import 'dart:math';

import '../protocol/messages.dart';

/// How often a liveness probe goes out by default.
const Duration defaultKeepAliveInterval = Duration(seconds: 5);

/// How long a peer may go without answering before the Session is lost.
///
/// Several times [defaultKeepAliveInterval] on purpose: a probe that has
/// only just gone out has not had a chance to be answered, so the deadline
/// is measured from the *previous* answer rather than from the moment the
/// probe was sent. A peer that is merely slow is not a peer that is gone.
const Duration defaultKeepAliveTimeout = Duration(seconds: 15);

/// Keeps one Session honest about whether the peer is still there.
///
/// A TCP connection that has been black-holed — the cable pulled, the router
/// rebooted, the Wi-Fi reassociated with a network that has no route to the
/// peer — does not announce itself. The socket stays open, the operating
/// system keeps accepting the bytes that go nowhere, and the Device that
/// lost its peer goes on showing it as connected. Nothing in the Session
/// layer notices, because from the socket's point of view nothing happened.
///
/// A probe is what turns that silence into an answer. The Device sends a
/// [PingMessage] every [interval] and waits for the [PongMessage] in reply.
/// A peer that is gone never answers, so the Session is closed and reported
/// lost, and the layers above are free to open a new one.
///
/// ## Who may be probed
///
/// Whether a peer is probed at all is not this class's decision: it is the
/// Session's, and the Session asks only when the peer's handshake said it
/// understands a probe. A Device on an older build is therefore never sent a
/// message it would misread, and is not excluded from the Session for that
/// reason either — it simply goes unprobed, and its disappearance is noticed
/// the way it was before, when the socket finally errors out.
final class KeepAlive {
  /// Starts probing through [send].
  ///
  /// [send] is how a probe goes out. [onTimeout] is called when the peer
  /// stops answering, and it is what closes the Session.
  ///
  /// [interval] is how often a probe goes out and [timeout] is how long the
  /// peer may go without answering.
  ///
  /// The answers are handed in through [onMessage] rather than read off a
  /// stream of this object's own, because the Session's message stream has
  /// exactly one reader — the hub — and a second reader of a
  /// single-subscription stream silently loses every frame.
  KeepAlive({
    required Future<void> Function(WireMessage message) send,
    required void Function() onTimeout,
    this.interval = defaultKeepAliveInterval,
    this.timeout = defaultKeepAliveTimeout,
    Random? random,
  }) : // A named parameter cannot be a private field, so each is assigned
       // here. The lint that asks for an initializing formal cannot be
       // satisfied when the field is private and the parameter is named.
       // ignore: prefer_initializing_formals
       _send = send,
       // ignore: prefer_initializing_formals
       _onTimeout = onTimeout,
       _random = random ?? Random.secure();

  /// How often a probe goes out.
  final Duration interval;

  /// How long the peer may go without answering before the Session is lost.
  final Duration timeout;

  final Future<void> Function(WireMessage message) _send;
  final void Function() _onTimeout;
  final Random _random;

  Timer? _timer;
  Timer? _pending;
  int _sequence = 0;
  bool _closed = false;

  /// Whether this KeepAlive has stopped.
  bool get isClosed => _closed;

  /// Starts sending probes.
  void start() {
    if (_closed || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => _probe());
  }

  /// Stops probing.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending?.cancel();
    _pending = null;
  }

  /// Feeds a message from the peer in.
  ///
  /// The hub calls this with the messages it reads off the Session's stream.
  /// A [PongMessage] is the answer that keeps the Session alive.
  void onMessage(PongMessage message) {
    if (_closed) return;
    // Any answer counts, not only the one owed: the probes are numbered
    // so a reply can be *recognised*, and a peer that answers a probe
    // this Device has forgotten about is still a peer that is there.
    _armDeadline();
  }

  void _probe() {
    if (_closed) return;
    _sequence += 1;
    final id = '$_sequence-${_random.nextInt(1 << 20)}';
    unawaited(
      _send(PingMessage(id)).catchError((Object _) {
        // A probe that could not be written is a Session that is already
        // gone. The link's own error handling reports it, so there is
        // nothing to add here.
      }),
    );
    // The deadline is armed once and left alone until an answer comes: it
    // is measured from the last answer, not from the last probe.
    // Re-arming it on every probe would push it forward for as long as the
    // peer kept ignoring the probes, and a peer that never answers would
    // never be given up on.
    if (_pending != null) return;
    _armDeadline();
  }

  /// Starts the clock on how long the peer may stay silent.
  ///
  /// The deadline is a timer of its own, so it is judged by the same clock
  /// that runs the probe. A comparison against a wall clock would be
  /// judged by a *different* clock, and a test that drives its own — a
  /// widget test, which advances time as fast as it likes — would then see
  /// a Session given up on that had every chance to answer.
  ///
  /// It is measured from the last answer, not from the last probe: a probe
  /// that has only just gone out has not had its chance yet, and a peer
  /// that is merely slow is not a peer that is gone.
  void _armDeadline() {
    _pending?.cancel();
    _pending = Timer(timeout, () {
      if (_closed) return;
      _pending = null;
      // The peer has stopped answering. The Session is closed rather than
      // left open: it is not usable any more, and the layers above need to
      // hear that it is gone so they can open a new one.
      _onTimeout();
    });
  }
}

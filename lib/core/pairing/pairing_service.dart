import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../clipboard/clipboard_capability.dart';
import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';
import '../identity/owner_group.dart';
import '../identity/owner_identity.dart';
import '../identity/pairing_secret.dart';
import '../profile/device_profile.dart';
import '../profile/profile_store.dart';
import '../protocol/messages.dart';
import '../security/hkdf.dart';
import '../security/secure_link.dart';
import '../transport/byte_transport.dart';

/// The TCP port a Device listens on while it has a Pairing invitation open.
///
/// Fixed, for the same reason the Session port is: the Device whose user types
/// the code has to have somewhere to send it, and there is nothing to negotiate
/// with beforehand. Deliberately distinct from the Session port and from the
/// discovery port, so a Pairing can never be mistaken for a Session and the UDP
/// listener is untouched.
const int defaultPairingPort = 47656;

/// Raised when a Pairing cannot be completed.
///
/// Every way a Pairing can fail — a code that does not match, a peer that never
/// confirms, a peer whose key does not hash to the identity it announced, two
/// Devices that already belong to different groups — arrives as this one type,
/// because a UI has one thing to say about all of them: this Device was not
/// paired.
final class PairingException implements Exception {
  const PairingException(this.message, {this.unreachable = false});

  /// Why the Pairing failed, for logs and for the UI.
  final String message;

  /// Whether the failure was that the other Device could not be reached at all.
  ///
  /// Split out because it is the one failure a user can usually fix, and the
  /// fix is not in this application: a dial that never arrived is a Device that
  /// is not running, on another network, or behind a firewall that drops
  /// incoming connections. The distinction cannot be recovered from [message] —
  /// that carries the operating system's own words, verbatim and untranslated —
  /// so it is carried here instead, where a UI can act on it.
  final bool unreachable;

  @override
  String toString() => 'PairingException: $message';
}

/// What a completed Pairing produced.
final class PairingOutcome {
  const PairingOutcome({
    required this.peer,
    required this.sas,
    required this.group,
    required this.sessionSecret,
  });

  /// The Device that was admitted.
  final KnownDevice peer;

  /// The short authentication string this Pairing derived.
  ///
  /// Nobody reads it. It is carried because it is what the admission was
  /// signed over, and a caller holding the outcome may want to log it.
  final String sas;

  /// The Owner Group this Device now belongs to.
  final OwnerGroup group;

  /// The secret Sessions inside the group are authenticated with.
  ///
  /// Returned rather than only stored because the caller's [LinkManager] was
  /// built with the previous value — null, on a Device that had never paired.
  /// A Pairing that does not hand this back produces a Device that looks paired
  /// and cannot talk to anybody.
  final Uint8List sessionSecret;

  @override
  String toString() =>
      'PairingOutcome(${peer.fingerprint.short()}, "${peer.alias}", sas: $sas)';
}

/// A Pairing that has reached the point where a human has to decide.
///
/// Everything cryptographic is already done by the time this is handed out: the
/// link is authenticated with the Pairing secret, the peer's Owner key has been
/// checked against the identity it announced, and both sides have agreed on the
/// group secret. What remains is the one thing only a person can do — say
/// whether this Device belongs in the group.
abstract interface class PairingAttempt {
  /// The Device on the other end, as it proved itself.
  KnownDevice get peer;

  /// The short authentication string this Pairing derived.
  ///
  /// Signed over, never displayed: see [SecureLink.shortAuthenticationString].
  String get sas;

  /// Whether this attempt is still live.
  bool get isOpen;

  /// Records that the user allowed this Pairing, and finishes it once the peer
  /// has allowed it too.
  ///
  /// Nothing is written before the peer's confirmation arrives. A user who
  /// allows on one Device and cancels on the other must not leave a
  /// half-paired state behind, where one side believes in a group the other
  /// knows nothing about.
  Future<PairingOutcome> confirm();

  /// Abandons the Pairing. Neither side is admitted.
  Future<void> cancel();
}

/// A Pairing this Device is hosting by code: it shows a code and waits for
/// somebody to type it.
///
/// The code path is the fallback, not the flow a user meets: a Device that is
/// *answering requests* (see [PairingService.receive]) is reached by tapping its
/// name in a list, and no code is exchanged at all. This class is what remains
/// for the case where there is no list to tap — a Device Discovery cannot see.
final class PairingInvitation {
  PairingInvitation._(this._service, {required this.code, required this.port}) {
    // A failure is delivered to whoever is waiting on [attempt]. A caller that
    // is *not* waiting — a screen the user navigated away from, a test that
    // only cancels — must not have it surface as an unhandled error, which Dart
    // reports to the zone rather than dropping. This attaches a second, silent
    // listener; anybody awaiting [attempt] still sees the failure.
    unawaited(_attempt.future.then<void>((_) {}, onError: (Object _) {}));
  }

  final PairingService _service;

  /// The code the other Device's user types. Ten Crockford base32 symbols.
  final String code;

  /// The port the invitation listens on.
  final int port;

  final Completer<Socket> _connected = Completer<Socket>();
  final Completer<PairingAttempt> _attempt = Completer<PairingAttempt>();
  final Completer<void> _done = Completer<void>();
  Future<void>? _release;

  /// Completes once a peer has connected and the question is ready to be asked.
  ///
  /// Fails with [PairingException] when the peer's attempt went wrong, and also
  /// when the invitation is withdrawn before anybody connects — so a UI that
  /// simply awaits this never hangs.
  Future<PairingAttempt> get attempt => _attempt.future;

  /// Completes when the invitation is over, one way or another.
  Future<void> get done => _done.future;

  /// Withdraws the invitation. A Device that connects afterwards is dropped,
  /// and [attempt] fails rather than waiting for a peer that is no longer
  /// wanted.
  Future<void> cancel() => _release ??= _withdraw();

  Future<void> _withdraw() async {
    await _service._detach(this);
    if (!_attempt.isCompleted) {
      _attempt.completeError(
        const PairingException(
          'the invitation was withdrawn before anybody '
          'paired',
        ),
      );
    }
    // Completing this last: it is what unblocks a listener that is still
    // sitting on `connected.future`, which would otherwise be left suspended
    // for the lifetime of the process.
    if (!_connected.isCompleted) {
      _connected.completeError(
        const PairingException('the invitation was withdrawn'),
      );
    }
    if (!_done.isCompleted) _done.complete();
  }
}

/// A Device that has dialled this one and is waiting for a person to decide.
///
/// A request is emitted the moment the caller has completed the handshake, and
/// **before anything has been given to it**. That ordering is the whole point of
/// the type: on an open Pairing the handshake secret is a well-known constant,
/// so any Device on the link can complete it — what such a caller must not be
/// able to obtain is this Device's group secret. Nothing offers that until
/// somebody taps through [admit], and a request nobody answers is refused
/// rather than left holding a link.
///
/// The wait is bounded: see [PairingService.requestTimeout].
abstract interface class PairingRequest {
  /// The Device asking, as it claimed itself during the handshake.
  ///
  /// A claim, not a proof. Anyone can complete a handshake against a well-known
  /// secret and call itself anything, so an Alias from here is worth exactly
  /// what a screen says it is worth — a label. What keeps that from being the
  /// last word is that the person on this end is asked and answers;
  /// [PairingAttempt.peer] is the same Device after it has proved it holds the
  /// key it announced.
  DeviceDescriptor get caller;

  /// Lets [caller] through, and runs the admission exchange.
  ///
  /// The two Devices sign over the session, check each other's keys and settle
  /// on a group secret. What comes back is still only an opportunity to
  /// confirm — nothing is admitted until both users do.
  ///
  /// Throws [PairingException] when the peer's admission does not check out,
  /// and [StateError] when the request has already been settled.
  Future<PairingAttempt> admit();

  /// Turns [caller] away. Neither side is admitted, and nothing is written.
  ///
  /// Safe to call when the request has already settled, so a screen that is
  /// being torn down can refuse without having to know what it already did.
  Future<void> refuse();
}

/// Pairs this Device with another, one Pairing at a time.
///
/// A Pairing runs on its own temporary link, never through a Session: the
/// Session port is authenticated with the group secret, and the whole point of
/// a Pairing is that the two Devices do not share one yet. So the two sides meet
/// on [defaultPairingPort], and when it is over that link is gone.
///
/// ## Two ways in, and which one is the flow
///
/// * **[receive]** — this Device answers requests, always. Somebody picks this
///   Device out of a list and taps Pair beside it; this Device asks its user,
///   and that one answer is the whole of the decision. This is the flow,
///   because it is the one that asks nothing of the user being paired *with*
///   beyond a tap on a question.
/// * **[invite]** — this Device shows a code and the other user types it. A
///   fallback for a peer Discovery cannot see and the two users can still talk
///   to each other, not a second way in: it derives the handshake secret's
///   strength from ten typed symbols, where [receive] stands on the fact that
///   the callers have to be answered one at a time by a person.
///
/// What a Pairing actually decides:
///
/// * **Who the peer is.** The Fingerprint the peer announced is checked against
///   the Owner key it signs with, so the identity is proven rather than
///   claimed. An Alias is not proof of anything — it is whatever a Device chose
///   to call itself — so the Fingerprint is the part worth checking out of band
///   if the stakes are high.
/// * **That a person meant it.** Each side shows its user the peer as it
///   identified itself, and asks. Both have to answer yes. The answering user
///   verifies nothing about the request, and is not asked to: this is the step
///   that keeps admission a human decision rather than an automatic one.
/// * **What the group secret is.** Two Devices pairing for the first time on a
///   code each derive it from the code, so nothing travels; on a request the
///   answering Device mints one and hands it over inside the sealed link. A
///   Device joining an existing group is handed the group's secret.
/// * **Who else is in the group.** The peer hands over its roster, so joining
///   an established group joins the whole group.
///
/// ## What the digits are, and are not
///
/// Every Pairing still derives a short authentication string and still signs
/// over it — see [SecureLink.shortAuthenticationString]. What it is not is a
/// check the users perform, and it was never a good one: both screens agree on
/// it **whatever peer dialled**, because it is derived from the handshake and
/// the Fingerprint a caller announces is a claim. A comparison across two
/// screens catches a third Device relaying between the two people, and nothing
/// more. Nothing shows it now, so what stands between a Device on the link and
/// this group is the answering user's own answer to the question — and on a
/// request the handshake secret is a *public constant*, so there was never
/// anything else it could be.
///
/// The bound that does matter is the code's ~50 bits: an attacker who records a
/// typed-code Pairing can test code guesses offline against it. That is a
/// property of the code, not of any comparison, and the reason the code path is
/// a fallback rather than the preferred one.
///
/// Only after the user confirms on *both* Devices is anything written.
///
/// ## Rebuilding what depends on the secret
///
/// A successful Pairing changes [local]'s group secret. Any [LinkManager] or
/// beacon already built from the old value is now wrong, and [changes] is how a
/// caller notices: rebuild them from the emitted profile, or from
/// [PairingOutcome.sessionSecret], which is the same value.
final class PairingService {
  /// A service over [local], persisting everything it changes through [store].
  PairingService({
    required this.local,
    required this.store,
    this.handshakeTimeout = const Duration(seconds: 15),
    this.confirmationTimeout = const Duration(seconds: 240),
    this.requestTimeout = const Duration(minutes: 2),
    this.onNotice,
  });

  /// This Device's identity and profile, kept current by every successful
  /// Pairing.
  LocalProfile local;

  /// Where [local] is written.
  final ProfileStore store;

  /// How long a Pairing handshake may take.
  final Duration handshakeTimeout;

  /// How long to wait for the peer's user to confirm, once this side has.
  ///
  /// Generous on purpose: the whole point of the step is that a person on the
  /// other Device has to read the question and answer it, which may mean
  /// walking over to that Device.
  final Duration confirmationTimeout;

  /// How long a [PairingRequest] may sit unanswered before it is refused.
  ///
  /// Bounded rather than open-ended because the caller is *waiting*: a request
  /// nobody answers would leave the other user watching a spinner until the
  /// process died. Two minutes is long enough to notice a prompt and walk over
  /// to a screen, and short enough that a Device nobody is sitting at stops
  /// collecting diallers.
  final Duration requestTimeout;

  /// Where a failure that is not anybody's request is reported.
  ///
  /// The listener dying is the case: a Device that can no longer be dialled
  /// should say so somewhere a user will see rather than only via [isReceiving]
  /// going false on a screen that is not being redrawn.
  final void Function(String message)? onNotice;

  final StreamController<LocalProfile> _changes =
      StreamController<LocalProfile>.broadcast();
  final StreamController<PairingRequest> _requests =
      StreamController<PairingRequest>.broadcast();
  final Set<_Attempt> _attempts = {};

  ServerSocket? _server;
  PairingInvitation? _invitation;
  _Receiving? _receiving;
  bool _closed = false;

  /// Emits the profile whenever a Pairing changes it.
  Stream<LocalProfile> get changes => _changes.stream;

  /// Devices asking to pair with this one, in arrival order.
  ///
  /// Empty until [receive] has been called. A request is emitted once the
  /// caller's handshake has completed and before it has been offered anything:
  /// see [PairingRequest].
  ///
  /// Whoever is listening has to answer, because the caller is blocked until
  /// then. With nobody listening at all the request is refused on the spot
  /// rather than left hanging — there is no screen for it to appear on.
  Stream<PairingRequest> get requests => _requests.stream;

  /// Whether an invitation is currently open.
  bool get isInviting => _invitation != null;

  /// Whether this Device is answering Pairing requests.
  bool get isReceiving => _receiving != null;

  /// The port requests are answered on, or null when not receiving.
  int? get receivingPort => _receiving?.port;

  /// This Device, as it announces itself on a Pairing link.
  ///
  /// Rebuilt from the profile on every use rather than cached: a Pairing that
  /// admitted a peer changed the profile underneath it, and the next Pairing
  /// must announce the current alias.
  ///
  /// No listening port travels here. The port in a descriptor says where to
  /// open a Session, and this Device is not accepting Sessions on the Pairing
  /// port — the link that carries this descriptor is a Pairing, not a Session.
  DeviceDescriptor get _descriptor => DeviceDescriptor(
    fingerprint: local.identity.fingerprint,
    alias: local.profile.alias,
    platform: local.profile.platform,
    capability: ClipboardCapability.forPlatform(local.profile.platform),
  );

  /// Opens an invitation and returns the code to show.
  ///
  /// One at a time, on purpose: the code is the only thing protecting the
  /// exchange, and two live codes would mean two live secrets derived from two
  /// guesses an attacker could combine. [port] defaults to
  /// [defaultPairingPort]; pass 0 for any free port, which is what a test
  /// wants.
  ///
  /// A Device cannot do this while it is answering requests: both want
  /// [defaultPairingPort], and a caller that arrives on a request listener has
  /// shown no code to be checked against. [stopReceiving] first. The code path
  /// is a fallback for a peer Discovery cannot find, not a second way in.
  Future<PairingInvitation> invite({int port = defaultPairingPort}) async {
    if (isReceiving) {
      throw StateError(
        'this Device is answering Pairing requests on $receivingPort: '
        'stopReceiving() first',
      );
    }
    return _listen(code: PairingSecret.generateCode(), port: port);
  }

  /// Starts answering Pairing requests on [port], and keeps answering.
  ///
  /// This is the receiving side of the click-to-pair flow, and it is a
  /// *listener* rather than an invitation with a lifetime. An invitation that
  /// exists only while a window is open can only be reached by somebody who
  /// remembered to open that window, which is a step the user of the other
  /// Device can neither see nor perform — and it made "add a Device" something
  /// that had to be done to a screen rather than to a Device.
  ///
  /// What replaces the window as the bound is [PairingRequest]: dialling this
  /// Device puts a question on its screen and nothing else. A caller gets an
  /// answer, a refusal, or — past [requestTimeout] with nobody looking — a
  /// closed link. It is never handed this Device's group secret to hold while
  /// the user thinks about it.
  ///
  /// Idempotent for a port already being listened on; a [port] of 0 binds any
  /// free port, which is what a test wants. Returns the port bound.
  ///
  /// Throws [PairingException] when the port cannot be bound — a second copy of
  /// the app on one host is the case that matters — which a caller is expected
  /// to report and carry on without rather than treat as fatal: a Device that
  /// cannot be dialled is still a Device that can dial.
  Future<int> receive({int port = defaultPairingPort}) async {
    if (_closed) throw StateError('this PairingService is closed');
    final open = _invitation;
    if (open != null) {
      throw StateError('an invitation is already open on ${open.port}');
    }
    final answering = _receiving;
    if (answering != null) {
      if (answering.port == port) return answering.port;
      throw StateError(
        'already answering Pairing requests on ${answering.port}',
      );
    }
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } on SocketException catch (error) {
      throw PairingException(
        'cannot answer Pairing requests on port $port: ${error.message}',
      );
    }
    final receiving = _Receiving(server);
    _receiving = receiving;
    server.listen(
      (socket) => unawaited(_answer(socket, receiving)),
      onError: (Object error) {
        // The listener is gone; saying so through [isReceiving] is more honest
        // than leaving a Device that reports it is answering and is not.
        _receiving = null;
        onNotice?.call('the pairing listener failed: $error');
      },
      cancelOnError: false,
    );
    return receiving.port;
  }

  /// Stops answering Pairing requests.
  ///
  /// A caller already past the prompt is left to finish: refusing it would
  /// cancel a Pairing the user is in the middle of. Turning the listener off
  /// is a statement about the next caller, not about the one on screen.
  Future<void> stopReceiving() async {
    final receiving = _receiving;
    if (receiving == null) return;
    _receiving = null;
    await receiving.close();
  }

  /// Answers one caller: complete the handshake, then hand it to a person.
  ///
  /// The handshake is finished *before* anybody is asked, for a reason the
  /// prompt depends on: the name to show comes from the descriptor exchanged
  /// there. Nothing travels the other way — see [_negotiate] for what would,
  /// and for why none of it may happen until [PairingRequest.admit].
  Future<void> _answer(Socket socket, _Receiving receiving) async {
    if (!receiving.beginHandshake()) {
      // Too many half-open diallers already. Bounded rather than accepted,
      // because a listener that answers every caller waits on each one for
      // [handshakeTimeout] and a hostile Device can open them faster than that.
      socket.destroy();
      return;
    }
    final transport = SocketByteTransport.fromSocket(socket);
    final SecureLink link;
    try {
      link = await SecureLink.establish(
        transport: transport,
        role: LinkRole.responder,
        local: _descriptor,
        secret: PairingSecret.openPairing(),
        timeout: handshakeTimeout,
      );
    } on Object {
      // A caller that cannot complete the handshake is not running this
      // protocol, and there is nothing to ask a user about. The transport is
      // closed here because `establish` hands that duty to its caller.
      await transport.close();
      return;
    } finally {
      receiving.endHandshake();
    }

    final request = _Caller(
      service: this,
      link: link,
      receiving: receiving,
      caller: link.peer.device,
    );
    // Nobody to ask, or somebody already being asked: the caller is turned away
    // rather than left holding a link that no screen is going to look at. The
    // second case is a Pairing at a time, still — two in flight would both
    // commit to the same profile, and the rosters they write would each be
    // missing the other's Device.
    if (_closed ||
        !identical(_receiving, receiving) ||
        !_requests.hasListener ||
        !receiving.prompt(request)) {
      await request.refuse();
      return;
    }
    _requests.add(request);
    request.expireAfter(requestTimeout);
  }

  Future<PairingInvitation> _listen({
    required String code,
    required int port,
  }) async {
    if (_closed) throw StateError('this PairingService is closed');
    final open = _invitation;
    if (open != null) {
      throw StateError('an invitation is already open on ${open.port}');
    }
    final secret = PairingSecret.fromCode(code);
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } on SocketException catch (error) {
      throw PairingException(
        'cannot listen for a Pairing on port $port: ${error.message}',
      );
    }
    final invitation = PairingInvitation._(this, code: code, port: server.port);
    _server = server;
    _invitation = invitation;

    server.listen(
      (socket) {
        if (invitation._connected.isCompleted) {
          // A second caller while the first Pairing is still in progress has
          // no code this Device is showing; dropping it is the only honest
          // answer.
          socket.destroy();
          return;
        }
        invitation._connected.complete(socket);
      },
      onError: (Object error) {
        if (!invitation._connected.isCompleted) {
          invitation._connected.completeError(
            PairingException('the listener failed: $error'),
          );
        }
      },
      cancelOnError: false,
    );

    unawaited(_accept(secret, invitation));
    return invitation;
  }

  /// Pairs with a Device showing [code] at [host].
  ///
  /// Resolves once the two Devices are ready for their users to be asked; call
  /// [PairingAttempt.confirm] afterwards to finish.
  Future<PairingAttempt> join({
    required String host,
    required String code,
    int port = defaultPairingPort,
  }) async {
    final PairingSecret secret;
    try {
      secret = PairingSecret.fromCode(code);
    } on FormatException catch (error) {
      throw PairingException('that is not a Pairing code: ${error.message}');
    }
    return _dial(secret: secret, host: host, port: port, openPairing: false);
  }

  /// Pairs with a Device that is answering requests at [host], with no code.
  ///
  /// This is the initiating side of the click-to-pair flow: [host] is a Device
  /// Discovery saw, which the user picked by name. What stands in place of the
  /// code is the other user's answer: a well-known handshake secret means any
  /// Device on the link can start a Pairing, and the question that Device is
  /// shown — and answers — is what keeps admission a human decision.
  ///
  /// Resolving is therefore not the same as being paired, and it is not
  /// immediate either: it waits for the *other* user to allow the request. A
  /// caller that gives up before then gets a [PairingException] rather than an
  /// attempt to confirm.
  Future<PairingAttempt> joinOpen({
    required String host,
    int port = defaultPairingPort,
  }) => _dial(
    secret: PairingSecret.openPairing(),
    host: host,
    port: port,
    openPairing: true,
  );

  Future<PairingAttempt> _dial({
    required PairingSecret secret,
    required String host,
    required int port,
    required bool openPairing,
  }) async {
    if (_closed) throw StateError('this PairingService is closed');
    final SocketByteTransport transport;
    try {
      transport = await SocketByteTransport.connect(host, port);
    } on SocketException catch (error) {
      // Marked unreachable so a UI can say what to check. A dial that never
      // lands is a Device that is not running, on another network, or behind a
      // firewall that drops incoming connections — none of which is a fault in
      // this application, and all of which are the user's to fix.
      throw PairingException(
        'cannot reach $host:$port: ${error.message}',
        unreachable: true,
      );
    }
    final SecureLink link;
    try {
      link = await SecureLink.establish(
        transport: transport,
        role: LinkRole.initiator,
        local: _descriptor,
        secret: secret,
        timeout: handshakeTimeout,
      );
    } on HandshakeException catch (error) {
      throw PairingException(
        'the other Device did not accept the code: ${error.message}',
      );
    }
    return _negotiate(
      link: link,
      role: LinkRole.initiator,
      secret: secret,
      openPairing: openPairing,
    );
  }

  /// Closes the service: the listener, the invitation, any attempt still in
  /// flight, and the change stream.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await stopReceiving();
    final invitation = _invitation;
    if (invitation != null) await invitation.cancel();
    for (final attempt in _attempts.toList()) {
      await attempt.cancel();
    }
    if (!_requests.isClosed) await _requests.close();
    if (!_changes.isClosed) await _changes.close();
  }

  /// Accepts the one peer this invitation will ever take.
  Future<void> _accept(
    PairingSecret secret,
    PairingInvitation invitation,
  ) async {
    try {
      final socket = await invitation._connected.future;
      final link = await SecureLink.establish(
        transport: SocketByteTransport.fromSocket(socket),
        role: LinkRole.responder,
        local: _descriptor,
        secret: secret,
        timeout: handshakeTimeout,
      );
      final attempt = await _negotiate(
        link: link,
        role: LinkRole.responder,
        secret: secret,
        openPairing: false,
      );
      if (!invitation._attempt.isCompleted) {
        invitation._attempt.complete(attempt);
      }
    } on Object catch (error) {
      if (!invitation._attempt.isCompleted) {
        invitation._attempt.completeError(_asPairingFailure(error));
      }
    } finally {
      await invitation.cancel();
    }
  }

  /// Stops listening for the invitation, if it is still the open one.
  ///
  /// Called by [PairingInvitation._withdraw]; a no-op for an invitation that
  /// has already been detached, so the inviter's own teardown and a caller's
  /// cancellation cannot race each other into closing somebody else's socket.
  Future<void> _detach(PairingInvitation invitation) async {
    if (!identical(_invitation, invitation)) return;
    _invitation = null;
    final server = _server;
    _server = null;
    if (server != null) await server.close();
  }

  /// Runs the admission exchange and returns the attempt a user decides on.
  ///
  /// What each side sends depends on its role as well as its state. The
  /// initiator speaks first, offering whatever group secret it has. The
  /// responder reads first, because on an open Pairing what it offers depends
  /// on what the peer brought:
  ///
  /// * already in a group — offer its own secret, whatever the peer did;
  /// * fresh, and the peer brought one — offer nothing, and adopt the peer's
  ///   (a fresh Device joining an established group);
  /// * fresh, and the peer brought nothing — mint a fresh secret and offer
  ///   *that*, so the group the two Devices form does not rest on the
  ///   well-known open-Pairing constant. Two unrelated Pairings then share
  ///   nothing, where a constant-derived secret would put every fresh pair
  ///   worldwide in one implicit group.
  ///
  /// On a typed-code Pairing the both-fresh case keeps deriving the secret
  /// from the code, exactly as before.
  ///
  /// Returns the concrete [_Attempt] rather than the interface: the receive
  /// path attaches an [onFinished] hook to it, so a caller that answered the
  /// prompt but never finished the Pairing still gives its slot back.
  Future<_Attempt> _negotiate({
    required SecureLink link,
    required LinkRole role,
    required PairingSecret secret,
    required bool openPairing,
  }) async {
    final peerClaim = link.peer.device;
    final sas = link.shortAuthenticationString;
    final context = _pairingContext(
      local.profile.self,
      peerClaim.fingerprint,
      sas,
    );

    // The read is started before anything is sent. The initiator sends right
    // away; the responder waits to read first — see the doc above for why.
    final incoming = StreamIterator<WireMessage>(link.messages);
    final theirs = _readAdmission(link, incoming, openPairing: openPairing);

    final Uint8List? mineSecret;
    if (role == LinkRole.initiator) {
      mineSecret = local.groupSecret;
      await link.send(await _admission(context, mineSecret));
    } else {
      final peerAdmit = await theirs;
      final brought = peerAdmit.groupSecret;
      mineSecret =
          local.groupSecret ??
          ((brought == null && openPairing)
              ? randomBytes(PairingSecret.keyBytes)
              : null);
      await link.send(await _admission(context, mineSecret));
    }
    final admit = await theirs;

    if (admit.fingerprint != peerClaim.fingerprint) {
      await link.close();
      throw PairingException(
        'the peer announced ${peerClaim.fingerprint.short()} but its key '
        'hashes to ${admit.fingerprint.short()}',
      );
    }
    if (!await OwnerIdentity.verify(
      admit.publicKey,
      context,
      admit.signature,
    )) {
      await link.close();
      throw const PairingException(
        'the peer did not prove it holds the key it announced',
      );
    }

    final theirSecret = admit.groupSecret;
    if (mineSecret != null &&
        theirSecret != null &&
        !constantTimeEquals(mineSecret, theirSecret)) {
      await link.close();
      throw const PairingException(
        'both Devices already belong to different groups',
      );
    }

    final attempt = _Attempt(
      this,
      link,
      incoming,
      role,
      sas: sas,
      peer: KnownDevice(
        fingerprint: admit.fingerprint,
        // The signed alias, not the one from the handshake: this is the value
        // the peer proved it chose, so it is the one worth remembering.
        alias: admit.alias,
        platform: peerClaim.platform,
      ),
      peerMembers: admit.members,
      sessionSecret: mineSecret ?? theirSecret ?? _deriveGroupSecret(secret),
    );
    _attempts.add(attempt);
    return attempt;
  }

  /// The admission this Device sends, signing over [context] and offering
  /// [groupSecret] — which is null exactly when this Device is forming a
  /// fresh group and the peer is to bring, or has brought, the secret.
  Future<PairAdmitMessage> _admission(
    List<int> context,
    Uint8List? groupSecret,
  ) async => PairAdmitMessage(
    publicKey: await local.identity.publicKey(),
    alias: local.profile.alias,
    signature: await local.identity.sign(context),
    groupSecret: groupSecret,
    members: local.profile.group.members,
  );

  /// Admits the peer into the group, stores the secret, and persists.
  ///
  /// Called only once both sides confirmed; see [_Attempt.confirm].
  ///
  /// The peer's roster is adopted along with the peer itself, so a Device
  /// joining an established group ends up in the whole group rather than in a
  /// group of two — otherwise the third Device in a group would refuse Mirror
  /// entries from the second, on the grounds that its own group named only the
  /// Device it paired with.
  ///
  /// Nothing is ever *removed* by this. A roster is one peer's belief about the
  /// group, and a peer holding a stale belief must not be able to undo a
  /// removal a user made. Membership therefore converges by growing; a Device
  /// that removed a member re-pairs, or removes it again where it lands.
  Future<OwnerGroup> _commit({
    required KnownDevice peer,
    required List<Fingerprint> members,
    required Uint8List sessionSecret,
  }) async {
    final profile = local.profile;
    var group = profile.group.admitted(peer.fingerprint);
    for (final member in members) {
      group = group.admitted(member);
    }
    profile.group = group;
    profile.noteDevice(peer);
    // The identity is unchanged, so what this really does is swap in the group
    // secret; the profile is the same live object every session shares.
    local = local.copyWith(profile: profile, groupSecret: sessionSecret);
    await saveLocalProfile(local, store);
    if (!_changes.isClosed) _changes.add(local);
    return group;
  }

  void _notifyAttemptFinished(_Attempt attempt) => _attempts.remove(attempt);
}

/// The Pairing context both Devices sign over.
///
/// Built from the two Fingerprints in a fixed order plus the short
/// authentication string, so both sides compute the same bytes without having
/// to agree on which role is which, and so a signature cannot be replayed out
/// of one Pairing session into another.
List<int> _pairingContext(Fingerprint a, Fingerprint b, String sas) {
  final first = a.compareTo(b) <= 0 ? a : b;
  final second = a.compareTo(b) <= 0 ? b : a;
  return utf8.encode(
    '${SecureLink.infoLabel} pair|${first.hex}|${second.hex}|$sas',
  );
}

/// The group secret two Devices derive when neither brought one.
///
/// Deterministic from the Pairing code, so the two sides agree without either
/// sending anything. It is as strong as the code that produced it — the same
/// 50 bits the Pairing handshake itself stands on — which is what makes the
/// typed code a fallback rather than the preferred way in.
Uint8List _deriveGroupSecret(PairingSecret pairing) => HkdfSha256.deriveKey(
  ikm: pairing.bytes,
  salt: utf8.encode('local-transfer group v1'),
  info: utf8.encode('group session secret'),
  length: 32,
);

/// Reads the peer's admission off a Pairing link.
///
/// [openPairing] decides what a link that closes before admitting anything
/// means. On a request it means the other user did not allow the Pairing —
/// which is an answer, and the caller deserves to read it as one rather than as
/// a peer that vanished. On a typed code it means the peer went away.
Future<PairAdmitMessage> _readAdmission(
  SecureLink link,
  StreamIterator<WireMessage> incoming, {
  required bool openPairing,
}) async {
  while (await incoming.moveNext()) {
    final message = incoming.current;
    if (message is PairAdmitMessage) return message;
    // Anything else on a Pairing link is a peer that is not running the
    // Pairing protocol; there is no reason to keep listening to it.
    await link.close();
    throw PairingException(
      'expected the peer to admit itself to the Pairing, got "${message.type}"',
    );
  }
  await link.close();
  throw PairingException(
    openPairing
        ? 'the other Device did not allow this Pairing'
        : 'the peer closed the Pairing before admitting itself',
  );
}

/// A failure a caller should see as "not paired", whatever its original type.
Object _asPairingFailure(Object error) {
  if (error is PairingException) return error;
  if (error is HandshakeException) {
    return PairingException(
      'the other Device did not accept the code: ${error.message}',
    );
  }
  return PairingException('the Pairing failed: $error');
}

/// The listener a Device answers Pairing requests on.
///
/// Holds what the single-shot invitation used to hold implicitly: who is being
/// dealt with right now, and how many strangers are allowed to be mid-handshake
/// while that happens.
final class _Receiving {
  _Receiving(this._server);

  /// How many callers may be mid-handshake at once.
  ///
  /// A listener that is always open is reachable by anything on the link, and
  /// every half-open dialler costs a task that waits `handshakeTimeout` for a
  /// peer that never speaks. Bounded so that a flood of them cannot pin the
  /// process — the cost of the bound is that the ninth simultaneous caller is
  /// dropped, which no honest pair of users will ever be.
  static const int maxHandshakes = 8;

  final ServerSocket _server;

  int _handshakes = 0;
  _Caller? _prompt;
  final Set<_Caller> _deciding = {};

  int get port => _server.port;

  /// Whether a caller is already being dealt with.
  bool get isBusy => _prompt != null || _deciding.isNotEmpty;

  /// Claims a handshake slot, or reports that there is none left.
  bool beginHandshake() {
    if (_handshakes >= maxHandshakes) return false;
    _handshakes++;
    return true;
  }

  void endHandshake() {
    if (_handshakes > 0) _handshakes--;
  }

  /// Puts [request] on screen, or reports that somebody is already there.
  ///
  /// One at a time, still: two Pairings in flight would both commit to the same
  /// profile, and the rosters they write would each be missing the other's
  /// Device. A second caller is turned away rather than queued — a queue of
  /// prompts nobody asked for is worse than an honest refusal.
  bool prompt(_Caller request) {
    if (isBusy) return false;
    _prompt = request;
    return true;
  }

  /// Moves [request] past the prompt, where it stays until it settles.
  ///
  /// Past the prompt means the user has let it through and the commit is
  /// pending — the attempt is theirs to finish or abandon from here.
  void decide(_Caller request) {
    if (identical(_prompt, request)) _prompt = null;
    _deciding.add(request);
  }

  /// Gives up whatever [request] was holding.
  void release(_Caller request) {
    if (identical(_prompt, request)) _prompt = null;
    _deciding.remove(request);
  }

  /// Stops listening, and refuses anybody still waiting to be asked about.
  Future<void> close() async {
    await _server.close();
    final waiting = _prompt;
    _prompt = null;
    if (waiting != null) await waiting.refuse();
  }
}

/// A Device waiting on the other side of a prompt.
///
/// The name it carries is what the handshake said, which is a claim; the
/// identity it is *checked* against arrives with the admission, and is what
/// [PairingAttempt.peer] reports afterwards.
final class _Caller implements PairingRequest {
  _Caller({
    required PairingService service,
    required SecureLink link,
    required _Receiving receiving,
    required this.caller,
  }) : // A named parameter cannot be a private field, so each is assigned here.
       // ignore: prefer_initializing_formals
       _service = service,
       // ignore: prefer_initializing_formals
       _link = link,
       // ignore: prefer_initializing_formals
       _receiving = receiving;

  final PairingService _service;
  final SecureLink _link;
  final _Receiving _receiving;

  @override
  final DeviceDescriptor caller;

  Timer? _expiry;
  bool _settled = false;
  bool _admitted = false;

  @override
  Future<PairingAttempt> admit() async {
    if (_settled) {
      throw StateError('this Pairing request has already been settled');
    }
    _settled = true;
    _expiry?.cancel();
    final _Attempt attempt;
    try {
      attempt = await _service._negotiate(
        link: _link,
        role: LinkRole.responder,
        secret: PairingSecret.openPairing(),
        openPairing: true,
      );
    } on Object {
      // The exchange failed, so there is no Pairing to decide on: give the
      // slot up now rather than when the link eventually times out.
      _receiving.release(this);
      rethrow;
    }
    _admitted = true;
    _receiving.decide(this);
    attempt.onFinished = () => _receiving.release(this);
    return attempt;
  }

  @override
  Future<void> refuse() async {
    if (_admitted) {
      // Past this point the link belongs to the attempt, and the way to abandon
      // it is [PairingAttempt.cancel] — killing it here would break a Pairing
      // the user is still looking at.
      return;
    }
    _settled = true;
    _expiry?.cancel();
    _receiving.release(this);
    await _link.close();
  }

  /// Refuses this request when nobody has answered it within [time].
  void expireAfter(Duration time) =>
      _expiry = Timer(time, () => unawaited(_expire()));

  Future<void> _expire() async {
    try {
      await refuse();
    } on Object {
      // Nothing to report: the caller is gone, one way or another.
    }
  }
}

/// One side's Pairing, from the user's answer to the commit.
final class _Attempt implements PairingAttempt {
  _Attempt(
    this._service,
    this._link,
    this._incoming,
    this._role, {
    required this.sas,
    required this.peer,
    required List<Fingerprint> peerMembers,
    required Uint8List sessionSecret,
  }) : // A named parameter cannot be a private field, so each is assigned here.
       // ignore: prefer_initializing_formals
       _peerMembers = peerMembers,
       // ignore: prefer_initializing_formals
       _sessionSecret = sessionSecret;

  final PairingService _service;
  final SecureLink _link;
  final StreamIterator<WireMessage> _incoming;
  final LinkRole _role;
  final List<Fingerprint> _peerMembers;
  final Uint8List _sessionSecret;

  @override
  final String sas;

  @override
  final KnownDevice peer;

  bool _settled = false;

  @override
  bool get isOpen => !_settled && !_link.isClosed;

  /// Called once when this attempt settles, whoever settles it.
  ///
  /// Attached by the receive path, which holds a slot for the Device on the
  /// other end: a user who answered the prompt and then walked away would
  /// otherwise block the next Device for the life of the process.
  void Function()? onFinished;

  @override
  Future<PairingOutcome> confirm() async {
    if (!isOpen) throw const PairingException('this Pairing is over');
    _settled = true;
    try {
      // Send first, then wait: both sides reach the same point, and neither
      // commits before it knows the other one did.
      await _link.send(const PairConfirmedMessage());
      await _awaitConfirmation();
      final group = await _service._commit(
        peer: peer,
        members: _peerMembers,
        sessionSecret: _sessionSecret,
      );
      return PairingOutcome(
        peer: peer,
        sas: sas,
        group: group,
        sessionSecret: _sessionSecret,
      );
    } on PairingException {
      rethrow;
    } on Object catch (error) {
      throw PairingException('the Pairing could not be completed: $error');
    } finally {
      _finish();
      await _link.close();
    }
  }

  @override
  Future<void> cancel() async {
    _finish();
    if (!isOpen) return;
    _settled = true;
    await _link.close();
  }

  /// Reports that this attempt is over, exactly once.
  void _finish() {
    final onFinished = this.onFinished;
    this.onFinished = null;
    onFinished?.call();
    _service._notifyAttemptFinished(this);
  }

  Future<void> _awaitConfirmation() async {
    final bool hasNext;
    try {
      hasNext = await _incoming.moveNext().timeout(
        _service.confirmationTimeout,
      );
    } on TimeoutException {
      throw PairingException(
        'the other Device did not confirm within '
        '${_service.confirmationTimeout.inSeconds}s',
      );
    }
    if (!hasNext) {
      // The peer closed the link: its user cancelled, or it gave up waiting.
      throw const PairingException(
        'the other Device ended the Pairing without confirming',
      );
    }
    final message = _incoming.current;
    if (message is! PairConfirmedMessage) {
      throw PairingException(
        'expected a Pairing confirmation, got "${message.type}"',
      );
    }
  }

  /// The role is recorded for logs; the flow above is symmetric.
  @override
  String toString() =>
      'PairingAttempt(${peer.fingerprint.short()}, '
      '${_role.wireName}, sas: $sas)';
}

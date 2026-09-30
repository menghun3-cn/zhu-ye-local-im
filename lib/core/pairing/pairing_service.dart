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
  const PairingException(this.message);

  /// Why the Pairing failed, for logs and for the UI.
  final String message;

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

  /// The six digits the two users compared.
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

/// A Pairing that has reached the point where a human has to compare codes.
///
/// Everything cryptographic is already done by the time this is handed out: the
/// link is authenticated with the typed code, the peer's Owner key has been
/// checked against the identity it announced, and both sides have agreed on the
/// group secret. What remains is the one thing only people can do — confirm
/// that the six digits on the two screens match, which is what rules out a peer
/// that guessed the code.
abstract interface class PairingAttempt {
  /// The Device on the other end, as it proved itself.
  KnownDevice get peer;

  /// The six digits both users compare.
  String get sas;

  /// Whether this attempt is still live.
  bool get isOpen;

  /// Records that the user confirmed the two codes match, and finishes the
  /// Pairing once the peer has confirmed too.
  ///
  /// Nothing is written before the peer's confirmation arrives. A user who
  /// confirms on one Device and cancels on the other must not leave a
  /// half-paired state behind, where one side believes in a group the other
  /// knows nothing about.
  Future<PairingOutcome> confirm();

  /// Abandons the Pairing. Neither side is admitted.
  Future<void> cancel();
}

/// A Pairing this Device is hosting: it shows a code and waits — or, on an
/// open Pairing, waits with no code on screen at all.
final class PairingInvitation {
  PairingInvitation._(
    this._service, {
    required String? code,
    required this.port,
  })
    // A named parameter cannot be a private field, so each is assigned here.
    // ignore: prefer_initializing_formals
    : _code = code {
    // A failure is delivered to whoever is waiting on [attempt]. A caller that
    // is *not* waiting — a screen the user navigated away from, a test that
    // only cancels — must not have it surface as an unhandled error, which Dart
    // reports to the zone rather than dropping. This attaches a second, silent
    // listener; anybody awaiting [attempt] still sees the failure.
    unawaited(_attempt.future.then<void>((_) {}, onError: (Object _) {}));
  }

  final PairingService _service;

  final String? _code;

  /// The code the other Device's user types. Ten Crockford base32 symbols.
  ///
  /// Reading this on an open Pairing — one that asked for no code — is a
  /// [StateError] rather than an empty string: an invitation either shows a
  /// code or it does not, and a blank that looks like a code would be a bug
  /// wearing a value.
  String get code {
    final value = _code;
    if (value == null) {
      throw StateError('an open Pairing shows no code');
    }
    return value;
  }

  /// Whether this invitation is waiting for a Device that will type a code.
  bool get showsCode => _code != null;

  /// The port the invitation listens on.
  final int port;

  final Completer<Socket> _connected = Completer<Socket>();
  final Completer<PairingAttempt> _attempt = Completer<PairingAttempt>();
  final Completer<void> _done = Completer<void>();
  Future<void>? _release;

  /// Completes once a peer has connected and the codes are ready to compare.
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

/// Pairs this Device with another, one Pairing at a time.
///
/// A Pairing runs on its own temporary link, never through a Session: the
/// Session port is authenticated with the group secret, and the whole point of
/// a Pairing is that the two Devices do not share one yet. So the two sides
/// meet on [defaultPairingPort] with a secret derived from a code one user
/// reads to the other, and when it is over that link is gone.
///
/// What a Pairing actually decides:
///
/// * **Who the peer is.** The Fingerprint the peer announced is checked against
///   the Owner key it signs with, so the identity is proven rather than
///   claimed. An Alias is not proof of anything — it is whatever a Device chose
///   to call itself — so the Fingerprint is the part worth comparing out of
///   band if the stakes are high.
/// * **That a person meant it.** Both users see the peer as it identified
///   itself and six digits derived from the session, and both have to confirm.
///   The digits are what makes the confirmation checkable: they come from the
///   keys the handshake derived, so two Devices agree on them without either
///   sending anything, and a Device that did not take part in *this* exchange
///   cannot know them.
/// * **What the group secret is.** Two Devices pairing for the first time each
///   derive it from the code, so nothing travels; a Device joining an existing
///   group is handed the group's secret inside the sealed link.
/// * **Who else is in the group.** The peer hands over its roster, so joining
///   an established group joins the whole group.
///
/// ## What the digits are not
///
/// A short authentication string is not a second layer of secrecy over the
/// code. A peer that knows the code completes the handshake and derives the
/// same digits as this Device, so the comparison cannot catch it; and a peer
/// that does not know the code cannot complete the handshake at all. What the
/// digits give the users is something *they* can check — the peer's identity
/// and this exchange's freshness are on screen together, and the step is what
/// keeps admission a human decision rather than an automatic one.
///
/// The bound that does matter is the code's ~50 bits: an attacker who records a
/// typed-code Pairing can test code guesses offline against it. That is a
/// property of the code, not of this comparison, and the reason the code path
/// is a fallback rather than the preferred one.
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
  /// Generous on purpose: the whole point of the step is that a human walks to
  /// the other Device and reads six digits off a screen.
  final Duration confirmationTimeout;

  final StreamController<LocalProfile> _changes =
      StreamController<LocalProfile>.broadcast();
  final Set<_Attempt> _attempts = {};

  ServerSocket? _server;
  PairingInvitation? _invitation;
  bool _closed = false;

  /// Emits the profile whenever a Pairing changes it.
  Stream<LocalProfile> get changes => _changes.stream;

  /// Whether an invitation is currently open.
  bool get isInviting => _invitation != null;

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
  Future<PairingInvitation> invite({int port = defaultPairingPort}) =>
      _listen(code: PairingSecret.generateCode(), port: port);

  /// Opens an invitation that asks for no code, and waits.
  ///
  /// This is the receiving side of the click-to-pair flow: the user of the
  /// other Device picks this Device from a list, so nothing has to be read
  /// off one screen and keyed into another. What stands in place of the code
  /// is the six digits both screens show once the peer arrives — the
  /// comparison step is not optional here, because a well-known handshake
  /// secret means any Device on the link can start a Pairing, and the digits
  /// plus the two confirmations are what keep admission a human decision.
  ///
  /// When both Devices are forming a fresh group, this Device mints the group
  /// secret and hands it to the peer inside the sealed link, so nothing about
  /// the Pairing's outcome is derivable from the well-known constant.
  Future<PairingInvitation> inviteOpen({int? port}) =>
      _listen(code: null, port: port ?? defaultPairingPort);

  Future<PairingInvitation> _listen({
    required String? code,
    required int port,
  }) async {
    if (_closed) throw StateError('this PairingService is closed');
    final open = _invitation;
    if (open != null) {
      throw StateError('an invitation is already open on ${open.port}');
    }
    final secret = code == null
        ? PairingSecret.openPairing()
        : PairingSecret.fromCode(code);
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
  /// Resolves once the two Devices are ready for the users to compare codes;
  /// call [PairingAttempt.confirm] afterwards to finish.
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

  /// Pairs with a Device that is receiving at [host], without typing a code.
  ///
  /// This is the initiating side of the click-to-pair flow: [host] is a Device
  /// whose user tapped Receive a connection, at the address Discovery saw it
  /// at. See [inviteOpen] for what stands in place of the code.
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
      throw PairingException('cannot reach $host:$port: ${error.message}');
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

  /// Closes the service: the invitation, any attempt still in flight, and the
  /// change stream.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final invitation = _invitation;
    if (invitation != null) await invitation.cancel();
    for (final attempt in _attempts.toList()) {
      await attempt.cancel();
    }
    if (!_changes.isClosed) await _changes.close();
  }

  /// Accepts the one peer this invitation will ever take.
  Future<void> _accept(
    PairingSecret secret,
    PairingInvitation invitation,
  ) async {
    final openPairing = invitation._code == null;
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
        openPairing: openPairing,
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
  Future<PairingAttempt> _negotiate({
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
    final theirs = _readAdmission(link, incoming);

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
/// 50 bits the Pairing itself stands on, and the reason codes are compared
/// before admission rather than trusted.
Uint8List _deriveGroupSecret(PairingSecret pairing) => HkdfSha256.deriveKey(
  ikm: pairing.bytes,
  salt: utf8.encode('local-transfer group v1'),
  info: utf8.encode('group session secret'),
  length: 32,
);

/// Reads the peer's admission off a Pairing link.
Future<PairAdmitMessage> _readAdmission(
  SecureLink link,
  StreamIterator<WireMessage> incoming,
) async {
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
  throw const PairingException(
    'the peer closed the Pairing before admitting itself',
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

/// One side's Pairing, from the code comparison to the commit.
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
      _service._notifyAttemptFinished(this);
      await _link.close();
    }
  }

  @override
  Future<void> cancel() async {
    _service._notifyAttemptFinished(this);
    if (!isOpen) return;
    _settled = true;
    await _link.close();
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

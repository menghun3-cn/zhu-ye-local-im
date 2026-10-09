import 'dart:async';
import 'dart:io';

import '../core/core.dart';
import 'views.dart';

export 'views.dart';

/// The one object a user interface talks to.
///
/// Everything below this lives in `lib/core` and knows nothing about a screen;
/// everything above it is a widget tree that draws what this reports and calls
/// what this exposes. That split is the reason this file imports no Flutter:
/// the whole application — discovery, pairing, Sessions, Transfers, clipboard
/// mirroring — can therefore be driven from a plain `dart test`, over real
/// sockets, with no widget tree and no rendering engine involved.
///
/// ## What it owns
///
/// * a [DiscoveryService] over an injected [BeaconTransport];
/// * a [PairingService] over an injected [ProfileStore], answering Pairing
///   requests for as long as the profile says to;
/// * a [LinkManager] — but only once this Device holds a group secret, because
///   a Device with no secret has nothing to authenticate a peer with, so it
///   serves no Sessions and announces no port;
/// * one [TransferEngine] per live Session;
/// * a [ClipboardMirror] over an injected [SystemClipboard].
///
/// ## What it does not do
///
/// It never answers an incoming *file* Transfer on the user's behalf. An offer
/// arrives on [incoming] and appears in [transfers] with [TransferView.offer]
/// set; only [acceptInto] or [reject] settles it.
///
/// Text is the exception, and deliberately so: a text offer is accepted the
/// moment it arrives, without a prompt. There is nothing to decide — a text
/// item carries its body inside the offer, takes no sink, and lands nowhere on
/// disk, so accepting one asks the user a question with no consequence either
/// way. Files stay prompted because they are the case the question exists for:
/// they write bytes into the user's folders, and the answer is *where*, which
/// only the user knows.
///
/// It never answers a Pairing request on the user's behalf either. A Device that
/// dialled this one arrives on [pairingRequests] and waits there; only
/// [PairingRequest.admit] or [PairingRequest.refuse] settles it. That is the
/// whole reason a Device can answer requests while nobody is sitting at it: the
/// listener is permanent, but nothing is admitted without a tap.
final class LocalTransferController {
  /// Builds a controller over the seams a platform provides.
  ///
  /// [beaconTransport], [clipboard] and [store] are held rather than created:
  /// the app passes the real ones, and a test passes in-memory ones, with no
  /// branch between the two. [sessionListenPort] and [pairingPort] accept 0,
  /// which binds any free port — what a test wants, and what a second copy of
  /// the app on one host would need.
  LocalTransferController({
    required ProfileStore store,
    required BeaconTransport beaconTransport,
    required SystemClipboard clipboard,
    DevicePlatform platform = DevicePlatform.windows,
    String? alias,
    int sessionListenPort = defaultSessionPort,
    int pairingPort = defaultPairingPort,
    ClipboardMode clipboardMode = ClipboardMode.off,
    DateTime Function()? clock,
  }) : // A named parameter cannot be a private field, so each of these is
       // assigned here. The lint that asks for an initializing formal cannot be
       // satisfied when the field is private and the parameter is named.
       // ignore: prefer_initializing_formals
       _store = store,
       _beacon = beaconTransport,
       _systemClipboard = clipboard,
       // ignore: prefer_initializing_formals
       _platform = platform,
       // ignore: prefer_initializing_formals
       _alias = alias,
       // ignore: prefer_initializing_formals
       _sessionListenPort = sessionListenPort,
       // ignore: prefer_initializing_formals
       _pairingPort = pairingPort,
       // ignore: prefer_initializing_formals
       _clipboardMode = clipboardMode,
       _clock = clock ?? DateTime.now;

  final ProfileStore _store;
  final BeaconTransport _beacon;
  final SystemClipboard _systemClipboard;
  final DevicePlatform _platform;
  final String? _alias;
  final int _sessionListenPort;
  final int _pairingPort;
  final ClipboardMode _clipboardMode;
  final DateTime Function() _clock;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Offers waiting for the user to answer them — a file, never a text.
  ///
  /// A broadcast controller does **not** hold on to an event that has not been
  /// delivered yet: the event is kept alive by whatever [add] captured, and
  /// falls out of reach the moment that is the only reference left. So a caller
  /// that adds an offer and then drops its own last reference to it has created
  /// a race with its own listeners. [_pruneTransfers] obeys that rule rather
  /// than relying on this stream to be patient.
  final StreamController<IncomingTransfer> _incoming =
      StreamController<IncomingTransfer>.broadcast();
  final StreamController<PairingRequest> _pairingRequests =
      StreamController<PairingRequest>.broadcast();
  final Map<String, _WiredSession> _wired = {};
  final List<_Tracked> _transfers = [];
  final List<StreamSubscription<Object?>> _watch = [];
  final List<String> _notices = [];

  LocalProfile? _local;
  PairingService? _pairing;
  DiscoveryService? _discovery;
  LinkManager? _manager;
  ClipboardMirror? _clipboard;
  StreamSubscription<Object?>? _discoveryWatch;
  StreamSubscription<LinkEvent>? _linkWatch;
  String? _discoveryKey;
  String? _managerKey;
  PairingSecret? _managerSecret;
  List<DiscoveredPeer> _discovered = const [];
  bool _started = false;
  bool _closed = false;

  /// Fires whenever anything a UI renders has changed.
  ///
  /// Coarse on purpose — a single "something moved" tick, not one stream per
  /// field — so a widget rebuilds once per change rather than subscribing to a
  /// dozen streams and racing them.
  Stream<void> get changes => _changes.stream;

  /// Offers that are waiting for this Device to answer them.
  ///
  /// The live [IncomingTransfer] rather than a view, because answering one
  /// means calling it.
  ///
  /// Text never reaches this stream: it is answered on arrival (see the class
  /// doc), so by the time a listener could act the offer is already settled.
  /// What arrives here is what genuinely needs an answer — files, whose
  /// landing directory only the user can name.
  Stream<IncomingTransfer> get incoming => _incoming.stream;

  /// Devices asking to pair with this one, in arrival order.
  ///
  /// A question rather than an event: whoever is listening has to answer it,
  /// because the Device on the other end is waiting. Emitted only while this
  /// Device is answering requests — see [acceptsPairingRequests].
  Stream<PairingRequest> get pairingRequests => _pairingRequests.stream;

  /// Everything that went wrong in a way that was not fatal, newest last.
  ///
  /// Refusals and notices the core layers report through `onNotice` land here,
  /// so a UI can show them without the app layer inventing its own error
  /// vocabulary for things that are not errors.
  List<String> get notices => List.unmodifiable(_notices);

  /// The clipboard entries this Device has staged but not applied.
  List<ClipboardEntry> get stagedEntries => _mirror.stagedEntries;

  /// Clipboard entries that arrive while staging.
  Stream<ClipboardEntry> get staged => _mirror.staged;

  /// Clipboard entries this Device put on the system clipboard.
  Stream<ClipboardEntry> get applied => _mirror.applied;

  /// How the clipboard is being treated.
  ClipboardMode get clipboardMode => _mirror.mode;

  /// Whether a Session can be held at all, i.e. whether this Device paired.
  bool get isPaired => _local?.hasGroupSecret ?? false;

  /// Whether a peer can be dialled, i.e. whether this Device is serving.
  bool get isServing => _manager?.isServing ?? false;

  /// Whether this Device is set to answer Pairing requests at all.
  ///
  /// The user's intent. Distinct from [isAcceptingPairings], which is whether
  /// the listener is actually up: the two differ when the port is taken — by a
  /// second copy of this app on one host, which cannot be dialled either.
  bool get acceptsPairingRequests =>
      _local?.profile.acceptsPairingRequests ?? false;

  /// Whether this Device is answering Pairing requests right now.
  bool get isAcceptingPairings => _pairing?.isReceiving ?? false;

  /// The port Pairing requests are answered on, or null when not answering.
  int? get pairingPort => _pairing?.receivingPort;

  /// The port Sessions are accepted on, or null when not serving.
  int? get listenPort => _manager?.listenPort;

  /// The Sessions currently open, most recently established first.
  List<ManagedSession> get sessions => _manager?.sessions ?? const [];

  /// What this Device says about itself.
  SelfView get self {
    final local = _requireLocal();
    return SelfView(
      fingerprint: local.profile.self,
      alias: local.profile.alias,
      platform: local.profile.platform,
      capability: ClipboardCapability.forPlatform(local.profile.platform),
      isPaired: local.hasGroupSecret,
      groupLength: local.profile.group.length,
      openSessions: _wired.length,
    );
  }

  /// Every Device this one knows of, from every source it has.
  ///
  /// Connected peers first, then by name: a list that reorders as devices come
  /// and go is worse than useless when the user is trying to click one.
  List<PeerView> get peers {
    final local = _local;
    if (local == null) return const [];
    final profile = local.profile;
    final facts = <String, _PeerFacts>{};

    _PeerFacts at(Fingerprint fingerprint) =>
        facts.putIfAbsent(fingerprint.hex, () => _PeerFacts(fingerprint));

    // Weakest knowledge first; each later source overwrites what it knows.
    for (final member in profile.group.members) {
      if (member == profile.self) continue;
      at(member);
    }
    for (final known in profile.knownDevices) {
      final entry = at(known.fingerprint);
      entry
        ..alias = known.alias
        ..platform = known.platform
        ..address = known.lastAddress
        ..lastSeen = known.lastSeen;
    }
    for (final discovered in _discovered) {
      final entry = at(discovered.fingerprint);
      entry
        ..alias = discovered.device.alias
        ..platform = discovered.device.platform
        ..address = discovered.address.address
        ..sessionPort = discovered.sessionPort
        ..lastSeen ??= discovered.lastSeen;
    }
    for (final wired in _wired.values) {
      final session = wired.session;
      final entry = at(session.peer);
      entry
        ..alias = session.handshake.device.alias
        ..platform = session.handshake.device.platform
        // The address the Session is actually running on, which is the one
        // piece of knowledge here that is not a memory: Discovery may have
        // restarted and a Known Device record may never have been written, but
        // a live Session is where the peer demonstrably is. Falling back to
        // what is already known keeps the record rather than blanking it.
        ..address = session.address?.address ?? entry.address
        ..sessionPort = session.handshake.device.listenPort ?? entry.sessionPort
        ..connected = true
        ..lastSeen = _clock().toUtc();
    }

    final views = [
      for (final entry in facts.values)
        PeerView(
          fingerprint: entry.fingerprint,
          alias: entry.alias,
          platform: entry.platform,
          address: entry.address,
          sessionPort: entry.sessionPort,
          isConnected: entry.connected,
          isInGroup: profile.group.contains(entry.fingerprint),
          isFavorite: profile.isFavorite(entry.fingerprint),
          lastSeen: entry.lastSeen,
        ),
    ];
    views.sort((a, b) {
      if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
      final byName = a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
      return byName != 0 ? byName : a.fingerprint.compareTo(b.fingerprint);
    });
    return views;
  }

  /// Every Transfer this Device has taken part in, newest first.
  List<TransferView> get transfers => [
    for (final tracked in _transfers.reversed) _viewOf(tracked),
  ];

  /// Loads or mints this Device's identity and brings the layers up.
  ///
  /// Must complete before anything else is used. Idempotent.
  Future<void> start() async {
    if (_closed) throw StateError('this controller is closed');
    if (_started) return;
    _started = true;
    final local = await loadOrGenerateLocalProfile(
      _store,
      platform: _platform,
      alias: _alias,
    );
    _local = local;
    final clipboard = ClipboardMirror(
      group: local.profile.group,
      capability: ClipboardCapability.forPlatform(_platform),
      clipboard: _systemClipboard,
      mode: _clipboardMode,
      onNotice: _notice,
    )..start();
    _clipboard = clipboard;
    // A staged entry is something a screen renders and a user has to answer, so
    // it has to *reach* the screen rather than wait for an unrelated rebuild to
    // happen to carry it there. The mirror reports it on its own stream and not
    // through `onNotice` — it is a waiting item, not a notice — so the tick that
    // says "something moved" is wired up here. Without it the Clipboard surface
    // sits on a stale list until the user navigates away and back.
    _watch.add(clipboard.staged.listen((_) => _notify()));
    final pairing = PairingService(
      local: local,
      store: _store,
      onNotice: _notice,
    );
    _pairing = pairing;
    _watch.add(
      pairing.changes.listen(
        _onProfileChanged,
        // Not `_notice` directly: a stream's error handler has to accept an
        // Object, and that mismatch is a run-time failure rather than a
        // compile-time one.
        onError: (Object error) => _notice('pairing failed: $error'),
      ),
    );
    // Requests are forwarded into this controller's own stream rather than
    // handed out directly: a listener that subscribes before `start` has
    // finished would otherwise be talking to a service that does not exist yet,
    // and would never hear the first request.
    _watch.add(pairing.requests.listen(_pairingRequests.add));
    await _syncLayers();
    await _syncPairingListener();
    _notify();
  }

  /// Stops listening, drops every Session, and releases the layers.
  ///
  /// The injected [SystemClipboard] and [BeaconTransport] are **not** closed:
  /// this controller did not create them and does not own them.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _teardownSessionLayer();
    await _discoveryWatch?.cancel();
    _discoveryWatch = null;
    final discovery = _discovery;
    _discovery = null;
    _discoveryKey = null;
    if (discovery != null) await discovery.close();
    for (final subscription in _watch) {
      await subscription.cancel();
    }
    _watch.clear();
    await _pairing?.close();
    await _clipboard?.close();
    if (!_incoming.isClosed) await _incoming.close();
    if (!_pairingRequests.isClosed) await _pairingRequests.close();
    if (!_changes.isClosed) await _changes.close();
  }

  /// Sets whether this Device answers Pairing requests, and persists it.
  ///
  /// Turning it off takes the listener down; turning it back on tries to bring
  /// it up. Either way the preference is written, so a Device that was told not
  /// to answer does not quietly start answering again after a restart.
  Future<void> setAcceptsPairingRequests(bool value) async {
    final local = _requireLocal();
    if (local.profile.acceptsPairingRequests == value) return;
    local.profile.acceptsPairingRequests = value;
    await _syncPairingListener();
    await _persist();
    _notify();
  }

  /// Pairs with a Device that is answering requests at [host], without a code.
  ///
  /// The initiating side of the click-to-pair flow: [host] is the address
  /// Discovery saw the Device at, and the exchange ends wherever the other
  /// user's answer leaves it — refused, or resolved to an attempt this side
  /// then confirms. [port] defaults to the well-known Pairing port, which is
  /// where a Device answers requests — the port to dial is the *peer's*, not
  /// this Device's own binding, which is why it is not read from this
  /// controller's configuration.
  ///
  /// Resolving is not being paired: it waits for the other user to allow the
  /// request, and throws [PairingException] if they refuse or never answer.
  Future<PairingAttempt> pairWith({required String host, int? port}) =>
      _requirePairing().joinOpen(host: host, port: port ?? defaultPairingPort);

  /// Opens a Session with [peer] right after a Pairing has completed.
  ///
  /// The peer brings its own Session layer up as its Pairing commits, and its
  /// beacon only re-announces the port that layer listens on on its next
  /// cycle — meanwhile this Device's own discovery has restarted to carry the
  /// new port, with an empty registry until then. So the first dial can
  /// arrive too early in two ways: nothing listening there yet, or no
  /// address known for the peer at all. A dial that fails for either reason
  /// is retried with a bound, re-resolving the target each time, rather than
  /// left to the user to click again on a race they did not cause. A Session
  /// that is already open is returned as it stands.
  Future<ManagedSession> connectAfterPairing(Fingerprint peer) async {
    if (_manager == null) await _syncLayersInTurn();
    Object? failure;
    for (var tries = 0; tries < 24; tries++) {
      final existing = _wired[peer.hex]?.session;
      if (existing != null) return existing;
      try {
        return await connect(peer);
      } on HandshakeException catch (error) {
        failure = error;
      } on SocketException catch (error) {
        failure = error;
      } on AppStateException catch (error) {
        // Discovery has not re-learnt where the peer listens yet; the next
        // announce fixes that, which is what waiting is for.
        failure = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw failure!;
  }

  /// Changes the Alias this Device announces.
  ///
  /// Costs every open Session: what a peer pins is the descriptor a Device
  /// announced, and that descriptor is fixed for the life of a [LinkManager],
  /// so a new name means a new manager and a fresh Session. The group secret is
  /// untouched, so no re-pairing is needed — peers redial and are recognised.
  Future<void> rename(String alias) async {
    final local = _requireLocal();
    final sanitised = DeviceDescriptor.sanitiseAlias(alias);
    if (local.profile.alias == sanitised) return;
    local.profile.alias = sanitised;
    await _persist();
    await _syncLayers();
    _notify();
  }

  /// Sets whether Transfers to [peer] skip the per-Transfer confirmation.
  void setFavorite(Fingerprint peer, {required bool value}) {
    _requireLocal().profile.setFavorite(peer, value: value);
    unawaited(_persist());
    _notify();
  }

  /// Opens a Session with [peer] at the address Discovery last saw it at.
  ///
  /// Throws [AppStateException] when nothing is known about where to dial, when
  /// this Device is not paired, and when a Session is already open; throws
  /// [HandshakeException] when the dial fails.
  Future<ManagedSession> connect(Fingerprint peer) async {
    if (_wired.containsKey(peer.hex)) {
      throw AppStateException(AppRefusal.sessionAlreadyOpen, peer.short());
    }
    final manager = _requireManager();
    final target = _dialTargetFor(peer);
    if (target == null) {
      throw AppStateException(AppRefusal.peerAddressUnknown, peer.short());
    }
    return manager.connect(
      target.address,
      target.port,
      expectedFingerprint: peer,
    );
  }

  /// Opens a Session with whatever Device answers at [address]:[port].
  ///
  /// This is the Manual Address path: the user typed where to look, so nothing
  /// was discovered and there is no Fingerprint to pin. The handshake still
  /// holds — a peer has to prove it knows the Pairing Secret, so a stranger on
  /// that address is refused rather than admitted — and what is given up is
  /// only the narrower guarantee that the Device answering a *known* address is
  /// the one expected there.
  ///
  /// [port] defaults to [defaultSessionPort], which is where a Device with the
  /// standard configuration listens. Throws [AppStateException] when this
  /// Device is unpaired, when no address was given, or when the port is not a
  /// port; throws [HandshakeException] when the dial fails or the peer cannot
  /// prove it belongs in the group.
  Future<ManagedSession> connectTo({required String address, int? port}) async {
    final manager = _requireManager();
    final host = address.trim();
    if (host.isEmpty) {
      throw const AppStateException(AppRefusal.noAddressGiven);
    }
    final target = port ?? defaultSessionPort;
    if (target <= 0 || target > 65535) {
      throw AppStateException(AppRefusal.portNotAPort, '$target');
    }
    return manager.connect(host, target);
  }

  /// Sends [text] to a peer as a Transfer.
  Future<OutgoingTransfer> sendText(String text, {Fingerprint? to}) async {
    final target = _target(to);
    final transfer = await target.engine.sendText(text);
    _track(transfer, target.peer);
    return transfer;
  }

  /// Sends [file]'s contents to a peer as a Transfer.
  Future<OutgoingTransfer> sendFile(File file, {Fingerprint? to}) async {
    // Resolved before the file is opened, so a call that cannot be sent never
    // takes a handle it will not hand over.
    final target = _target(to);
    final source = await FileByteSource.open(file);
    final OutgoingTransfer transfer;
    try {
      transfer = await target.engine.sendFiles([
        OutgoingItem(name: _baseName(file.path), source: source),
      ]);
    } on Object {
      // The engine takes ownership of a source only once the Transfer exists;
      // one that failed to be offered would otherwise leak its file handle.
      await source.close();
      rethrow;
    }
    _track(transfer, target.peer);
    return transfer;
  }

  /// Sends [file] to a peer as an image message.
  ///
  /// The bytes take the same road as [sendFile] — a digest, a sink, a
  /// verification — and only the kind on the offer differs, so that the far
  /// side draws the picture rather than naming a file. There is no thumbnail
  /// or downscale here: re-encoding a photograph to save bandwidth would
  /// change the bytes the sender chose to send, and a transfer tool that
  /// silently altered its payload would be lying about its digest.
  Future<OutgoingTransfer> sendImage(File file, {Fingerprint? to}) async {
    final target = _target(to);
    final source = await FileByteSource.open(file);
    final OutgoingTransfer transfer;
    try {
      transfer = await target.engine.sendImages([
        OutgoingItem(name: _baseName(file.path), source: source),
      ]);
    } on Object {
      await source.close();
      rethrow;
    }
    // Recorded as the tracked Transfer's path straight away, unlike a received
    // image: this file is the user's own and already whole on disk, so there is
    // nothing to wait for.
    _track(transfer, target.peer, localPath: file.path);
    return transfer;
  }

  /// Sends [items] to a peer as one Transfer.
  Future<OutgoingTransfer> sendFiles(
    List<OutgoingItem> items, {
    Fingerprint? to,
  }) async {
    final target = _target(to);
    final transfer = await target.engine.sendFiles(items);
    _track(transfer, target.peer);
    return transfer;
  }

  /// Accepts everything [transfer] offers, writing file bytes under [directory].
  ///
  /// Names come from the peer and are therefore sanitised by
  /// [incomingPathFor]; a name that would collide with an existing file is
  /// numbered rather than overwriting it.
  ///
  /// This is the file path: a text offer is accepted by the controller on
  /// arrival and is never awaiting a decision by the time a UI could call this,
  /// so passing one throws [AppRefusal.offerAlreadyAnswered].
  Future<void> acceptInto(
    IncomingTransfer transfer,
    Directory directory,
  ) async {
    if (!transfer.isDecidable) {
      throw const AppStateException(AppRefusal.offerAlreadyAnswered);
    }
    final sinks = <String, PayloadSink>{};
    final landed = <String, String>{};
    var accepted = false;
    try {
      for (final item in transfer.items) {
        // Only an item with a digest carries a byte stream to write; a text or
        // clipboard item arrives inline and takes no sink.
        if (!item.hasDigest) continue;
        final path = incomingPathFor(directory, item.name);
        sinks[item.id] = await FilePayloadSink.open(path);
        landed[item.id] = path.path;
      }
      await transfer.accept(
        itemIds: [for (final item in transfer.items) item.id],
        sinks: sinks,
      );
      accepted = true;
    } finally {
      if (!accepted) {
        for (final sink in sinks.values) {
          await sink.close();
        }
      }
    }
    // The bytes are verified and closed by now — `accept` does not return until
    // they are — so it is only here that a received image has a path worth
    // drawing. Recorded for the first landed item because that is what an image
    // message carries; a multi-file offer leaves this null and keeps its names.
    if (landed.isNotEmpty) {
      _recordLocalPath(transfer, landed.values.first);
    }
    _notify();
  }

  /// Points the tracked record for [transfer] at [path], if one exists.
  ///
  /// The record is looked up rather than passed in because `acceptInto` takes
  /// the [IncomingTransfer] the UI holds, not the wrapper the controller made.
  void _recordLocalPath(Transfer transfer, String path) {
    for (final tracked in _transfers) {
      if (identical(tracked.transfer, transfer)) {
        tracked.localPath = path;
        return;
      }
    }
  }

  /// Refuses [transfer].
  Future<void> reject(
    IncomingTransfer transfer, [
    RejectionReason reason = RejectionReason.declined,
  ]) async {
    await transfer.reject(reason);
    _notify();
  }

  /// Changes how the clipboard is treated, starting or stopping the watcher.
  void setClipboardMode(ClipboardMode mode) {
    _mirror.setMode(mode);
    _notify();
  }

  /// Puts a staged entry on the system clipboard.
  Future<void> applyStaged(ClipboardEntry entry) async {
    await _mirror.apply(entry);
    _notify();
  }

  // ---------------------------------------------------------------- internals

  Future<void> _syncLayers() async {
    final local = _local;
    if (local == null || _closed) return;
    final secret = local.groupSecret;
    if (secret == null) {
      // Nothing to authenticate with, so nothing to serve: an unpaired Device
      // announces no port, and a peer that dials it anyway is refused.
      await _teardownSessionLayer();
      await _syncDiscovery(null);
      return;
    }
    final key = _keyOf(local);
    final wanted = PairingSecret.fromBytes(secret);
    final secretChanged =
        _managerSecret == null || !_managerSecret!.matches(wanted);
    if (_manager == null || _managerKey != key || secretChanged) {
      await _teardownSessionLayer();
      final manager = LinkManager(
        local: _descriptorOf(local.profile),
        sessionSecret: wanted,
      );
      await manager.serve(port: _sessionListenPort);
      _manager = manager;
      _managerKey = key;
      _managerSecret = wanted;
      _linkWatch = manager.events.listen(
        _onLinkEvent,
        onError: (Object error) => _notice('the link manager failed: $error'),
      );
    }
    await _syncDiscovery(_requireManager().advertised);
  }

  /// Makes the Pairing listener match the profile.
  ///
  /// Called wherever [acceptsPairingRequests] can have changed, so the listener
  /// and the switch cannot disagree — a Device that says it is not answering
  /// but is would be the kind of lie that costs trust in the whole screen.
  ///
  /// Failing to bind is reported rather than raised: the usual cause is a
  /// second copy of the app on one host, and that user can still dial out and
  /// pair, so an unanswerable Device is a degraded one rather than a broken
  /// one. [isAcceptingPairings] stays honest about which of the two it is.
  Future<void> _syncPairingListener() async {
    final pairing = _pairing;
    final local = _local;
    if (pairing == null || local == null || _closed) return;
    final wanted = local.profile.acceptsPairingRequests;
    if (wanted == pairing.isReceiving) return;
    try {
      if (wanted) {
        await pairing.receive(port: _pairingPort);
      } else {
        await pairing.stopReceiving();
      }
    } on Object catch (error) {
      _notice('this Device cannot answer Pairing requests: $error');
    }
  }

  Future<void> _syncDiscovery(DeviceDescriptor? advertised) async {
    final local = _requireLocal();
    final descriptor = advertised ?? _descriptorOf(local.profile);
    final key =
        '${descriptor.alias}\u0000${descriptor.listenPort}\u0000'
        '${descriptor.fingerprint.hex}';
    if (_discovery != null && _discoveryKey == key) return;
    final previous = _discovery;
    _discovery = null;
    _discoveryKey = null;
    await _discoveryWatch?.cancel();
    _discoveryWatch = null;
    // The old service has to be gone before the new one listens: a transport's
    // received stream is single-subscription, so two services over one
    // transport would fight for it.
    if (previous != null) await previous.close();
    final discovery = DiscoveryService(
      transport: _beacon,
      local: descriptor,
      clock: _clock,
    );
    _discovery = discovery;
    _discoveryKey = key;
    _discovered = discovery.currentPeers;
    _discoveryWatch = discovery.peers.listen((peers) {
      _discovered = peers;
      _notify();
    }, onError: (Object error) => _notice('discovery failed: $error'));
    discovery.start();
  }

  Future<void> _teardownSessionLayer() async {
    final manager = _manager;
    _manager = null;
    _managerKey = null;
    await _linkWatch?.cancel();
    _linkWatch = null;
    for (final wired in _wired.values.toList()) {
      await wired.dispose();
    }
    _wired.clear();
    if (manager != null) await manager.close();
  }

  void _onProfileChanged(LocalProfile next) {
    _local = next;
    _clipboard?.setGroup(next.profile.group);
    unawaited(_syncLayersSafely());
    // A profile written by something other than [setAcceptsPairingRequests] —
    // restored from disk, say — must not leave the listener behind the switch.
    unawaited(_syncPairingListener());
    _notify();
  }

  Future<void> _syncLayersSafely() async {
    try {
      await _syncLayersInTurn();
    } on Object catch (error) {
      _notice('the session layer could not be brought up: $error');
    }
  }

  Future<void> _syncChain = Future<void>.value();

  /// Runs [_syncLayers] after the run before it has finished.
  ///
  /// Two triggers can arrive together — a Pairing committing, which rebuilds
  /// the session layer on its own, and the caller that then wants a Session
  /// over that layer. Serialized like this, the second run sees the layer the
  /// first built instead of tearing it down mid-build.
  Future<void> _syncLayersInTurn() {
    final run = _syncChain.catchError((Object _) {}).then((_) => _syncLayers());
    _syncChain = run;
    return run;
  }

  void _onLinkEvent(LinkEvent event) {
    switch (event) {
      case SessionEstablished(:final session):
        _adopt(session);
      case SessionLost(:final peer):
        _drop(peer);
      case SessionRefused():
        // A refused connection is not this Device's business to report: it is
        // usually a stranger, or a peer whose Pairing Secret differs, and the
        // peer that tried is shown a failure of its own.
        break;
    }
  }

  void _adopt(ManagedSession session) {
    if (_wired.containsKey(session.peer.hex)) return;
    final engine = TransferEngine(
      channel: session.hub.transfers,
      onNotice: _notice,
    );
    final wired = _WiredSession(session: session, engine: engine);
    wired.watch(
      engine.incoming.listen(
        (offer) => _onOffer(session.peer, offer),
        onError: (Object error) =>
            _notice('a Transfer from ${session.peer.short()} failed: $error'),
      ),
    );
    _wired[session.peer.hex] = wired;
    _clipboard?.attachPeer(
      fingerprint: session.peer,
      channel: session.hub.clipboard,
    );
    _notePeer(session);
    _notify();
  }

  void _drop(Fingerprint peer) {
    final wired = _wired.remove(peer.hex);
    if (wired != null) unawaited(wired.dispose());
    _clipboard?.detachPeer(peer);
    _notify();
  }

  void _onOffer(Fingerprint peer, IncomingTransfer offer) {
    _track(offer, peer);
    // Text settles itself: a text item carries its body in the offer and takes
    // no sink, so accepting it commits nothing, writes nothing and has no
    // answer the user could give differently. Prompting for it would be a
    // question with one sensible answer, and the thing a conversation is made
    // of would stall on a tap — so it does not.
    //
    // A file is the opposite in every one of those respects: it writes bytes
    // into a folder the user picks, so it waits here like everything else.
    if (offer.kind == PayloadKind.text) {
      unawaited(_acceptInline(offer, peer));
    } else if (!_incoming.isClosed) {
      _incoming.add(offer);
    }
    _notify();
  }

  /// Accepts an offer that carries its whole body inside itself.
  ///
  /// No sinks: every item of such an offer has no digest by construction, and
  /// `accept` rejects a sink for an item that streams nothing.
  Future<void> _acceptInline(IncomingTransfer offer, Fingerprint peer) async {
    try {
      await offer.accept(itemIds: [for (final item in offer.items) item.id]);
    } on Object catch (error) {
      // A text that could not be accepted is not worth a dialog: the offer is
      // already settled by `accept`'s failure path or by the Session dying, and
      // the sender is told through its own outcome. A notice keeps it visible
      // without pretending the user has something to answer.
      _notice(
        'a text Transfer from ${peer.short()} could not be accepted: '
        '$error',
      );
    }
    _notify();
  }

  void _notePeer(ManagedSession session) {
    final device = session.handshake.device;
    _local?.profile.noteDevice(
      KnownDevice(
        fingerprint: session.peer,
        alias: device.alias,
        platform: device.platform,
        lastSeen: _clock().toUtc(),
        lastAddress: session.address?.address,
      ),
    );
    unawaited(_persist());
  }

  void _track(Transfer transfer, Fingerprint peer, {String? localPath}) {
    final tracked = _Tracked(transfer, peer, localPath: localPath);
    _transfers.add(tracked);
    final progress = transfer.updates.listen((_) => _notify());
    // Settling happens once and is what a UI cares about most, so it is worth a
    // notification even if no progress tick preceded it. The progress
    // subscription goes with it: a finished Transfer emits nothing more, and
    // holding one per Transfer for the life of the app would be a leak with a
    // list to match.
    unawaited(
      transfer.outcome.then<void>((_) {}, onError: (Object _) {}).whenComplete(
        () async {
          await progress.cancel();
          _notify();
        },
      ),
    );
    _pruneTransfers();
  }

  /// Keeps the finished-transfer list from growing without bound.
  ///
  /// Only ever drops Transfers that are **already settled**, which is what
  /// makes dropping them safe for the two things besides the list that hold on
  /// to one. The record was also the only strong reference keeping the object
  /// alive for consumers, and `_incoming` is a *broadcast* controller — a
  /// broadcast controller does not keep an undelivered event alive, so an offer
  /// whose listeners have not run yet would be collected rather than
  /// delivered, and the peer's question would vanish. A Transfer that has not
  /// settled is a question still in flight, so it is not a candidate.
  ///
  /// Above [keep] the oldest are dropped regardless, which is the bound
  /// talking: a hundred live Transfers is far past anything a person is
  /// watching, and the alternative is a list that grows for the life of the
  /// process.
  void _pruneTransfers() {
    const keep = 100;
    if (_transfers.length <= keep) return;
    _transfers.removeWhere((tracked) => tracked.transfer.isSettled);
    while (_transfers.length > keep) {
      _transfers.removeAt(0);
    }
  }

  TransferView _viewOf(_Tracked tracked) {
    final transfer = tracked.transfer;
    return TransferView(
      id: transfer.id,
      direction: transfer.direction,
      kind: transfer.kind,
      peer: tracked.peer,
      state: transfer.state,
      transferredBytes: transfer.transferredBytes,
      totalBytes: transfer.totalBytes,
      names: [for (final item in transfer.items) item.name],
      text: transfer.text,
      localPath: tracked.localPath,
      // Text is never handed out as a decision: it is answered on arrival, so
      // an offer of it is either already settled or about to be, and a UI that
      // drew a prompt for one would be drawing a question the controller has
      // already answered. Belt beside the braces of `_onOffer` — this is the
      // single place that decides what a UI is allowed to answer, so the rule
      // lives here too.
      offer:
          transfer is IncomingTransfer &&
              transfer.isDecidable &&
              transfer.kind != PayloadKind.text
          ? transfer
          : null,
    );
  }

  /// The Session to send on, resolved from an optional peer.
  ({Fingerprint peer, TransferEngine engine}) _target(Fingerprint? to) {
    if (_wired.isEmpty) {
      throw const AppStateException(AppRefusal.noPeerConnected);
    }
    final _WiredSession wired;
    final Fingerprint peer;
    if (to != null) {
      final found = _wired[to.hex];
      if (found == null) {
        throw AppStateException(AppRefusal.noSessionOpen, to.short());
      }
      wired = found;
      peer = to;
    } else if (_wired.length == 1) {
      final entry = _wired.entries.first;
      wired = entry.value;
      peer = wired.session.peer;
    } else {
      throw const AppStateException(AppRefusal.severalPeersConnected);
    }
    return (peer: peer, engine: wired.engine);
  }

  ({String address, int port})? _dialTargetFor(Fingerprint peer) {
    for (final discovered in _discovered) {
      if (discovered.fingerprint != peer) continue;
      // A port the peer advertised is the one to dial. When it has none — a
      // beacon seen before the peer came up serving — the well-known Session
      // port is the honest guess: the dial pins the peer's Fingerprint, so a
      // wrong Device on that port fails the handshake rather than receiving
      // somebody else's file.
      return (
        address: discovered.address.address,
        port: discovered.sessionPort ?? defaultSessionPort,
      );
    }
    // A Known Device remembers the address it was reached at but not the port
    // it listens on, so a redial falls back to the well-known session port.
    // Safe to guess for the same reason as above.
    final address = _local?.profile.known(peer)?.lastAddress;
    if (address == null) return null;
    return (address: address, port: defaultSessionPort);
  }

  String _keyOf(LocalProfile local) =>
      '${local.profile.alias}\u0000${local.profile.self.hex}';

  DeviceDescriptor _descriptorOf(DeviceProfile profile) => DeviceDescriptor(
    fingerprint: profile.self,
    alias: profile.alias,
    platform: profile.platform,
    capability: ClipboardCapability.forPlatform(profile.platform),
  );

  Future<void> _persist() async {
    final local = _local;
    if (local == null) return;
    try {
      await saveLocalProfile(local, _store);
    } on Object catch (error) {
      _notice('the profile could not be saved: $error');
    }
  }

  void _notice(String message) {
    _notices.add(message);
    _notify();
  }

  void _notify() {
    if (_changes.isClosed) return;
    _changes.add(null);
  }

  ClipboardMirror get _mirror {
    final mirror = _clipboard;
    if (mirror == null) {
      throw StateError('start() has not completed yet');
    }
    return mirror;
  }

  LocalProfile _requireLocal() {
    final local = _local;
    if (local == null) throw StateError('start() has not completed yet');
    return local;
  }

  PairingService _requirePairing() {
    final pairing = _pairing;
    if (pairing == null) throw StateError('start() has not completed yet');
    return pairing;
  }

  LinkManager _requireManager() {
    final manager = _manager;
    if (manager == null) {
      throw const AppStateException(AppRefusal.notPaired);
    }
    return manager;
  }
}

/// A Session with the layers wired on top of it.
final class _WiredSession {
  _WiredSession({required this.session, required this.engine});

  final ManagedSession session;
  final TransferEngine engine;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  void watch(StreamSubscription<Object?> subscription) =>
      _subscriptions.add(subscription);

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await engine.close();
  }
}

/// A Transfer and the Device it is with.
final class _Tracked {
  _Tracked(this.transfer, this.peer, {this.localPath});

  final Transfer transfer;
  final Fingerprint peer;

  /// Where this Transfer's bytes live on *this* machine, once they do.
  ///
  /// Only ever set for an image, and only once the bytes are all present:
  /// rendering a thumbnail means reading a file, and a path that is still being
  /// written to would draw a half image or fail outright. Null for a text or
  /// clipboard Transfer, which has no file, and for a file Transfer, which the
  /// conversation shows by name rather than by content.
  String? localPath;
}

/// What is known about one peer, gathered from every source before being
/// reduced to a [PeerView].
final class _PeerFacts {
  _PeerFacts(this.fingerprint);

  final Fingerprint fingerprint;
  String? alias;
  DevicePlatform? platform;
  String? address;
  int? sessionPort;
  DateTime? lastSeen;
  bool connected = false;
}

/// The last path segment of [path], under either separator convention.
String _baseName(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  return cut < 0 ? path : path.substring(cut + 1);
}

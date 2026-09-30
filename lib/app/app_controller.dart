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
/// * a [PairingService] over an injected [ProfileStore];
/// * a [LinkManager] — but only once this Device holds a group secret, because
///   a Device with no secret has nothing to authenticate a peer with, so it
///   serves no Sessions and announces no port;
/// * one [TransferEngine] per live Session;
/// * a [ClipboardMirror] over an injected [SystemClipboard].
///
/// ## What it does not do
///
/// It never answers an incoming Transfer on the user's behalf. An offer arrives
/// on [incoming] and appears in [transfers] with [TransferView.offer] set; only
/// [acceptInto] or [reject] settles it.
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
  final StreamController<IncomingTransfer> _incoming =
      StreamController<IncomingTransfer>.broadcast();
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
  Stream<IncomingTransfer> get incoming => _incoming.stream;

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
        ..address ??= session.address?.address
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
    final pairing = PairingService(local: local, store: _store);
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
    await _syncLayers();
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
    if (!_changes.isClosed) await _changes.close();
  }

  /// Opens an invitation for a peer to type this Device's code into.
  ///
  /// The returned [PairingInvitation] carries the code to show and an
  /// [PairingInvitation.attempt] that resolves once a peer arrives, at which
  /// point the two users compare the short authentication strings and both
  /// call [PairingAttempt.confirm].
  Future<PairingInvitation> invite() =>
      _requirePairing().invite(port: _pairingPort);

  /// Joins a Device showing [code] at [host].
  ///
  /// [port] defaults to this controller's pairing port, which is where a Device
  /// running with the standard configuration listens. It is a parameter because
  /// the port a Device actually bound is the one to dial, and a caller that
  /// read it off the invitation — as a test with an ephemeral port must — needs
  /// to be able to say so.
  Future<PairingAttempt> join({
    required String host,
    required String code,
    int? port,
  }) => _requirePairing().join(
    host: host,
    code: code,
    port: port ?? _pairingPort,
  );

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
      throw AppStateException('a Session with ${peer.short()} is already open');
    }
    final manager = _requireManager();
    final target = _dialTargetFor(peer);
    if (target == null) {
      throw AppStateException(
        'no address is known for ${peer.short()}; '
        'it has to be discovered before it can be dialled',
      );
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
      throw const AppStateException('no address was given to dial');
    }
    final target = port ?? defaultSessionPort;
    if (target <= 0 || target > 65535) {
      throw AppStateException('$target is not a port');
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
  Future<void> acceptInto(
    IncomingTransfer transfer,
    Directory directory,
  ) async {
    if (!transfer.isDecidable) {
      throw const AppStateException('this offer has already been answered');
    }
    final sinks = <String, PayloadSink>{};
    var accepted = false;
    try {
      for (final item in transfer.items) {
        // Only an item with a digest carries a byte stream to write; a text or
        // clipboard item arrives inline and takes no sink.
        if (!item.hasDigest) continue;
        sinks[item.id] = await FilePayloadSink.open(
          incomingPathFor(directory, item.name),
        );
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
    _notify();
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
    _notify();
  }

  Future<void> _syncLayersSafely() async {
    try {
      await _syncLayers();
    } on Object catch (error) {
      _notice('the session layer could not be brought up: $error');
    }
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
    if (!_incoming.isClosed) _incoming.add(offer);
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

  void _track(Transfer transfer, Fingerprint peer) {
    _transfers.add(_Tracked(transfer, peer));
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
      offer: transfer is IncomingTransfer && transfer.isDecidable
          ? transfer
          : null,
    );
  }

  /// The Session to send on, resolved from an optional peer.
  ({Fingerprint peer, TransferEngine engine}) _target(Fingerprint? to) {
    if (_wired.isEmpty) {
      throw const AppStateException('no peer is connected');
    }
    final _WiredSession wired;
    final Fingerprint peer;
    if (to != null) {
      final found = _wired[to.hex];
      if (found == null) {
        throw AppStateException('no Session is open with ${to.short()}');
      }
      wired = found;
      peer = to;
    } else if (_wired.length == 1) {
      final entry = _wired.entries.first;
      wired = entry.value;
      peer = wired.session.peer;
    } else {
      throw const AppStateException(
        'more than one peer is connected; the one to send to has to be named',
      );
    }
    return (peer: peer, engine: wired.engine);
  }

  ({String address, int port})? _dialTargetFor(Fingerprint peer) {
    for (final discovered in _discovered) {
      if (discovered.fingerprint != peer) continue;
      final port = discovered.sessionPort;
      if (port == null) continue;
      return (address: discovered.address.address, port: port);
    }
    // A Known Device remembers the address it was reached at but not the port
    // it listens on, so a redial falls back to the well-known session port.
    // Safe to guess: the dial pins the peer's Fingerprint, so a wrong Device on
    // that port fails the handshake rather than receiving somebody else's file.
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
      throw const AppStateException(
        'this Device is not paired, so it serves no Sessions',
      );
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
  _Tracked(this.transfer, this.peer);

  final Transfer transfer;
  final Fingerprint peer;
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

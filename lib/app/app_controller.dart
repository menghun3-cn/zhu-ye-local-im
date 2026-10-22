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
/// Text and images are the exceptions, and deliberately so. Both are answered
/// the moment they arrive, without a prompt, because neither raises a question
/// the user could answer differently. A text item carries its body inside the
/// offer, takes no sink, and lands nowhere on disk — accepting one asks about
/// nothing. An image does stream bytes and does land on disk, but the folder is
/// not a decision the arrival introduces: it is a setting this Device already
/// has, and the dialog an image used to raise was pre-filled with the answer it
/// was going to be given anyway. Files stay prompted because they are the case
/// that question exists for — a file is something the user goes looking for
/// later, and where it was filed is worth being asked about.
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
  /// the app on one host would need. A non-zero [sessionListenPort] or
  /// [pairingPort] is a preference rather than a requirement: when the operating
  /// system refuses it, that listener binds any free port instead.
  ///
  /// [defaultIncomingDirectory] is where an offer the controller answers on its
  /// own lands when the profile names no folder of its own to prefer. It is
  /// injected rather than looked up because where that is depends on the
  /// platform — the user's Downloads folder on Windows, the app's private
  /// directory on Android — and `lib/app` may not ask a platform anything.
  /// Null therefore means "nowhere", which is exactly what the one desktop
  /// platform this build has not implemented resolves to; see [_landingFor].
  ///
  /// [messageStore] is where the conversation is remembered between runs, and
  /// null is a real answer there too: a Device with nowhere durable to write
  /// keeps its conversation for as long as the process, exactly as it keeps its
  /// identity. It is a store of its own rather than the profile's because the
  /// two have nothing to do with each other — losing a conversation must not
  /// cost a Device its identity, and the profile is rewritten rarely while a
  /// conversation changes every time somebody types.
  LocalTransferController({
    required ProfileStore store,
    required BeaconTransport beaconTransport,
    required SystemClipboard clipboard,
    DevicePlatform platform = DevicePlatform.windows,
    String? alias,
    int sessionListenPort = defaultSessionPort,
    int pairingPort = defaultPairingPort,
    ClipboardMode clipboardMode = ClipboardMode.off,
    String? defaultIncomingDirectory,
    MessageStore? messageStore,
    HostShell? hostShell,
    DateTime Function()? clock,
    this.keepAliveInterval = defaultKeepAliveInterval,
    this.keepAliveTimeout = defaultKeepAliveTimeout,
    this.wrapSocket,
    this.dialSocket,
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
       // ignore: prefer_initializing_formals
       _defaultIncomingDirectory = defaultIncomingDirectory,
       // ignore: prefer_initializing_formals
       _messages = messageStore,
       // ignore: prefer_initializing_formals
       _hostShell = hostShell,
       _clock = clock ?? DateTime.now;

  final ProfileStore _store;
  final BeaconTransport _beacon;
  final SystemClipboard _systemClipboard;
  final DevicePlatform _platform;
  final String? _alias;
  final int _sessionListenPort;
  final int _pairingPort;
  final ClipboardMode _clipboardMode;

  /// Where a Transfer the controller answers by itself lands when the profile
  /// has not been told where to put things.
  final String? _defaultIncomingDirectory;

  /// Where the conversation is kept between runs, or null for nowhere.
  ///
  /// Held as an optional rather than a mandatory store with an in-memory
  /// fallback, because "this Device has nowhere to write" and "this Device is
  /// a test" are the same case and both are served by remembering nothing:
  /// with no store there is no history to load, nothing is archived, and the
  /// live list is the whole of the conversation — which is what every test
  /// that predates the history was written against.
  final MessageStore? _messages;

  /// The window and startup facts this host will change, or null on a platform
  /// that has none.
  ///
  /// Optional for the same reason [MessageStore] is: "this Device has no window
  /// to control" and "this Device is a test" are the same case, and both are
  /// served by doing nothing. A platform that has one answers every call, so
  /// there is no branch on the platform anywhere below here.
  final HostShell? _hostShell;

  final DateTime Function() _clock;

  /// How often a liveness probe goes out on an open Session.
  ///
  /// Zero turns the probing off, which is what a peer on a build without the
  /// probe gets — it is never sent one, and its disappearance is noticed the
  /// way it was before, when the socket finally errors out. The default is a
  /// real interval, because a Session whose peer has vanished silently is a
  /// Session that looks connected and is not.
  final Duration keepAliveInterval;

  /// How long a peer may go without answering before the Session is lost.
  ///
  /// Only a test shortens this: the shipped value is several times the
  /// probing interval, because a peer that is merely slow is not a peer that
  /// is gone.
  final Duration keepAliveTimeout;

  /// Wraps the socket an accepted Session runs on.
  ///
  /// The seam exists for the black-hole case: a connection that stays open
  /// and silently swallows everything written to it is what a lost route
  /// looks like, and it cannot be produced by closing a socket — a closed
  /// socket reports itself. Only a test replaces it.
  final ByteTransport Function(Socket socket)? wrapSocket;

  /// Dials a peer, for the seam the same reason [wrapSocket] exists.
  ///
  /// Only a test replaces it, and only to make a dial fail the way a dial
  /// fails while the network is down.
  final Future<Socket> Function(String host, int port)? dialSocket;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Offers waiting for the user to answer them — a file, never a text or an
  /// image.
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
  final List<MessageRecord> _history = [];

  /// What the user has read of the conversation, and where they were last.
  ///
  /// A value object rather than fields spread across this class, because the
  /// two facts in it are persisted together and forgotten together: see
  /// [ConversationReading]. Always present — a Device that remembers nothing
  /// still has a reading state, it simply never records anything in it, and
  /// every message in it is unread.
  ConversationReading _reading = ConversationReading();

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

  /// Whether this app is set to start with the system, as the host last
  /// reported it.
  ///
  /// Cached here rather than written to the profile because the operating
  /// system is where the entry lives; this is a reading of it, taken at
  /// startup and again after every change. See [setAutostart].
  bool _autostart = false;

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
  /// Text and images never reach this stream: both are answered on arrival (see
  /// the class doc), so by the time a listener could act the offer is already
  /// settled. What arrives here is what genuinely needs an answer — a file,
  /// whose landing directory only the user can name.
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
    //
    // With one exception, and it is the whole reason `_PeerFacts.fromDiscovery`
    // exists: a Session's handshake is the *oldest* thing here about a name —
    // it is a snapshot taken when the Session opened and never refreshed — so
    // it is applied last only for the facts a Session is the authority on
    // (where the peer is, and that it is reachable there). For the name it
    // yields to anything live, or a rename would be invisible to every peer
    // already connected to the Device that renamed itself.
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
        ..pairingPort = discovered.pairingPort
        ..lastSeen ??= discovered.lastSeen
        ..fromDiscovery = true;
    }
    for (final wired in _wired.values) {
      final session = wired.session;
      final entry = at(session.peer);
      // A handshake is a *snapshot*: what the peer called itself at the moment
      // the Session was opened. It does not change for as long as the Session
      // lives, and `rename` documents that a peer's rename costs it every open
      // Session precisely because of this. Discovery is the live answer — the
      // peer re-announces every few seconds — so where Discovery has placed
      // this Device, its name is the fresher of the two and wins. Without
      // this, renaming a Device leaves the old name on every peer that still
      // holds a Session to it, which is every peer that was connected when the
      // rename happened, and the stale name outlives the rename by as long as
      // that Session survives.
      if (!entry.fromDiscovery) {
        entry
          ..alias = session.handshake.device.alias
          ..platform = session.handshake.device.platform;
      }
      entry
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
          pairingPort: entry.pairingPort,
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

  /// Every message in every conversation this Device has had, newest first.
  ///
  /// Two sources, and the live one wins. A Transfer this process took part in
  /// is a [_Tracked] with real state and real byte counts, so a UI draws it
  /// from there — including after it ends, which is when it is archived:
  /// settling is what turns a Transfer into history, and the record stays in
  /// both lists until the live one is pruned. A message remembered from an
  /// earlier run has no live state at all, and is drawn from the record.
  ///
  /// The two are joined on [TransferView.handle] rather than by position,
  /// because for a settled message in the current run they describe the same
  /// thing and drawing it twice would be the visible bug.
  ///
  /// Newest first, because the conversation list draws itself reversed — the
  /// newest message is at the bottom, which is where a conversation is read
  /// from.
  List<TransferView> get transfers {
    final live = <String, TransferView>{};
    for (final tracked in _transfers) {
      live[_handleOf(tracked)] = _viewOf(tracked);
    }
    final views = <TransferView>[
      for (final record in _history)
        if (!live.containsKey(record.handle)) _viewOfRecord(record),
      ...live.values,
    ];
    views.sort(_newestFirst);
    return views;
  }

  /// How many messages from [peer] the user has not read.
  ///
  /// Counted from the same list the conversation draws, so a badge and the
  /// messages under it can never disagree: whatever is in [transfers] for this
  /// peer and is incoming and newer than the watermark is exactly what a user
  /// would find by opening it. Clipboard entries are left out for the same
  /// reason the conversation list leaves them out — a mirrored clipboard is not
  /// something anybody reads.
  int unreadCount(Fingerprint peer) {
    return _reading.unreadFor(peer, () sync* {
      for (final view in _historyViewsFor(peer)) {
        yield (
          incoming: view.direction == TransferDirection.incoming,
          at: view.at,
        );
      }
    }());
  }

  /// Whether this Device has ever opened [peer]'s conversation.
  ///
  /// What tells "everything here is new" from "nothing new since last time",
  /// which are the two answers a first-ever launch and an ordinary one give to
  /// the same question.
  bool hasOpenedConversation(Fingerprint peer) => _reading.hasOpened(peer);

  /// The conversation the user was last in, or null for none.
  ///
  /// What the Conversations surface opens with, so that arriving there is
  /// coming back to where you were rather than to a blank pane. Null on a
  /// Device that has never opened one, which is the honest answer and the one
  /// the empty-state hint is written for.
  Fingerprint? get lastConversation {
    final hex = _reading.lastPeer;
    if (hex == null) return null;
    return Fingerprint(hex);
  }

  /// Records that [peer]'s conversation has been read, as of now.
  ///
  /// Called when a conversation is on screen. The whole of the unread rule is
  /// in this call and the comparison it feeds: everything already there is read
  /// the moment the user is looking at it, and anything that arrives afterwards
  /// is not.
  ///
  /// Written only when the mark would actually move something — a conversation
  /// never opened before, a different one from the one opened last, or one
  /// still holding messages the watermark does not cover — and otherwise it
  /// returns before it touches the file or notifies. That has to *hold*, not
  /// merely be intended: the surface calls this from `build` through a
  /// post-frame callback, `build` runs a great many times per second, and the
  /// notification this makes is what triggers the next build. A guard that
  /// compares the new mark's time against the old one looks sufficient and is
  /// not — the clock has always moved by the next call, so every call advanced
  /// the watermark, notified and wrote, and the notification rebuilt the
  /// surface that scheduled the next call. One conversation left open on
  /// screen therefore rewrote the file once a frame, forever.
  Future<void> markConversationOpened(Fingerprint peer) async {
    final before = _reading.openedThrough(peer);
    final movedLast = _reading.lastPeer != peer.hex;
    if (before != null && !movedLast && unreadCount(peer) == 0) return;
    final now = _clock();
    _reading
      ..markOpened(peer, now)
      ..lastPeer = peer.hex;
    _notify();
    await _persistHistory();
  }

  /// Every remembered message exchanged with [peer], newest first, clipboard
  /// aside.
  ///
  /// A helper for [unreadCount] rather than a public accessor: the surface that
  /// draws a conversation already has [transfers], and handing out a second way
  /// to ask the same question would be a second thing to keep in step.
  Iterable<TransferView> _historyViewsFor(Fingerprint peer) => transfers.where(
    (view) => view.peer == peer && view.kind != PayloadKind.clipboard,
  );

  /// Orders two messages the way a conversation reads.
  ///
  /// The tie-break is not decoration: `List.sort` is not stable, so two
  /// messages stamped in the same millisecond — which a resumed Transfer and
  /// the message beside it can be — would swap places from one rebuild to the
  /// next without it, and a list that reorders itself while somebody reads it
  /// is a bug whatever order the two "should" be in.
  static int _newestFirst(TransferView a, TransferView b) {
    final byTime = b.at.compareTo(a.at);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

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
    // The window is clickable from the first frame, so the close button is told
    // what to do before anything slower happens. The runner starts out hiding
    // the window — the default — and this is the answer for a user who chose
    // otherwise; see [CloseBehaviour].
    await _hostShell?.setCloseToTray(
      local.profile.closeBehaviour == CloseBehaviour.minimiseToTray,
    );
    // Read rather than remembered: the operating system holds the entry, so
    // this one call reports both what the app last wrote and what a user has
    // changed behind its back.
    _autostart = await _hostShell?.autostartEnabled() ?? false;
    // The conversation is read before anything can add to it. Both the load
    // and the archive work on `_history`, and a Transfer that settled while the
    // file was still being read would be appended to a list that was about to
    // be replaced by what the file holds.
    await _loadHistory();
    final clipboard =
        ClipboardMirror(
            group: local.profile.group,
            capability: ClipboardCapability.forPlatform(_platform),
            clipboard: _systemClipboard,
            mode: _clipboardMode,
            onNotice: _notice,
          )
          // The whitelist starts as the profile has it, so a Device that restarts
          // keeps sharing with exactly the peers its user left on the list.
          ..setAllowedPeers(local.profile.clipboardPeers)
          ..start();
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
    _startReconnectSweep();
    _notify();
  }

  /// Stops listening, drops every Session, and releases the layers.
  ///
  /// The injected [SystemClipboard] and [BeaconTransport] are **not** closed:
  /// this controller did not create them and does not own them.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stopReconnectSweep();
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
      _requirePairing().joinOpen(
        host: host,
        port: port ?? _pairingPortAt(host) ?? defaultPairingPort,
      );

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

  /// The faces this Device's recent-emoji strip should draw, newest first.
  List<String> get recentEmojis =>
      _local?.profile.recentEmojis ?? const <String>[];

  /// Makes [face] the most recently used, and persists the strip.
  ///
  /// A face the picker does not know is refused by the profile; persisting
  /// here uses the same store everything else in the profile writes to, so a
  /// strip survives a restart. The notification is what lets a picker already
  /// on screen move the face to the front.
  void rememberEmoji(String face) {
    _requireLocal().profile.rememberEmoji(face);
    unawaited(_persist());
    _notify();
  }

  /// Whether [peer] is on this Device's clipboard-sharing whitelist.
  bool isClipboardPeer(Fingerprint peer) =>
      _local?.profile.isClipboardPeer(peer) ?? false;

  /// Where the user wants received files to land, or null for the platform's
  /// own default.
  ///
  /// The convention the shell reads: a chosen folder wins, and the seam's
  /// default is what "no choice" resolves to. The two are kept apart here
  /// rather than collapsed into one value so that clearing the choice goes
  /// back to the platform default instead of pinning whatever it was when the
  /// screen was last opened.
  String? get incomingDirectory => _local?.profile.incomingDirectory;

  /// Sets where received files should land, and persists it.
  ///
  /// Takes [path] as the user gave it. Nothing is created or checked here: a
  /// folder the user names may be on a drive that is not mounted yet, and a
  /// settings screen that refused to remember it would be one that cannot be
  /// set up before the drive is.
  Future<void> setIncomingDirectory(String? path) async {
    final local = _requireLocal();
    local.profile.setIncomingDirectory(path);
    await _persist();
    _notify();
  }

  /// What the window's close button does.
  CloseBehaviour get closeBehaviour =>
      _local?.profile.closeBehaviour ?? CloseBehaviour.minimiseToTray;

  /// Sets what the window's close button does, tells the host, and persists it.
  ///
  /// All three, in that order. The running window first because that is what
  /// the user is looking at; the profile second because that is what a restart
  /// reads. A setter that wrote one and not the other would leave the setting
  /// describing a window other than the one on screen — and the window is the
  /// one thing that cannot remember a choice about itself.
  Future<void> setCloseBehaviour(CloseBehaviour value) async {
    final local = _requireLocal();
    if (local.profile.closeBehaviour == value) return;
    local.profile.closeBehaviour = value;
    await _hostShell?.setCloseToTray(value == CloseBehaviour.minimiseToTray);
    await _persist();
    _notify();
  }

  /// How often this Device asks GitHub whether a newer build has been
  /// published.
  UpdateCheckInterval get updateCheckInterval =>
      _local?.profile.updateCheckInterval ?? UpdateCheckInterval.hourly;

  /// Sets how often the update question is asked, and persists it.
  Future<void> setUpdateCheckInterval(UpdateCheckInterval value) async {
    final local = _requireLocal();
    if (local.profile.updateCheckInterval == value) return;
    local.profile.updateCheckInterval = value;
    await _persist();
    _notify();
  }

  /// Whether this app starts with the system.
  bool get autostartEnabled => _autostart;

  /// Turns starting with the system on or off.
  ///
  /// Nothing is written to the profile: the operating system holds the entry,
  /// and a second copy of that fact could only disagree with it. What ends up
  /// in [_autostart] is read off the host *after* the change, so the switch
  /// reports what will happen rather than what was asked for — a write that
  /// failed and a user who removed the entry by hand both show up as the truth,
  /// which is what a switch with nothing behind it cannot do.
  Future<void> setAutostart(bool value) async {
    final shell = _hostShell;
    if (shell == null) return;
    await shell.setAutostart(value);
    final real = await shell.autostartEnabled();
    if (real == _autostart) return;
    _autostart = real;
    _notify();
  }

  /// Sets whether [peer] may share the clipboard with this Device, and
  /// persists it.
  ///
  /// The whitelist is the user's per-device consent, kept in the profile and
  /// mirrored into the running [ClipboardMirror] here: the profile is what a
  /// restart reads, the mirror is what the running traffic consults, and a
  /// setter that updated one and not the other would make the switch lie
  /// about itself until the next restart.
  void setClipboardPeer(Fingerprint peer, {required bool value}) {
    final local = _requireLocal();
    if (local.profile.isClipboardPeer(peer) == value) return;
    local.profile.setClipboardPeer(peer, value: value);
    _mirror.setAllowedPeers(local.profile.clipboardPeers);
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

  /// Sends [face] to a peer as an emoji Transfer.
  Future<OutgoingTransfer> sendEmoji(String face, {Fingerprint? to}) async {
    final target = _target(to);
    final transfer = await target.engine.sendEmoji(face);
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
        OutgoingItem(name: fileNameOf(file.path), source: source),
      ]);
    } on Object {
      // The engine takes ownership of a source only once the Transfer exists;
      // one that failed to be offered would otherwise leak its file handle.
      await source.close();
      rethrow;
    }
    // Recorded straight away, the way a sent image is: this file is the user's
    // own and already whole on disk, so there is nothing to wait for, and it is
    // what a "show me where this is" action resolves to.
    _track(transfer, target.peer, localPath: file.path);
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
        OutgoingItem(name: fileNameOf(file.path), source: source),
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
  /// The bytes are written to a staging name this Device makes up and only
  /// renamed to the peer's name once every byte has been verified — see
  /// [stagingPathFor] for what that buys. The final name is decided at that
  /// moment by [incomingPathFor], so a name that would collide with an existing
  /// file is numbered rather than overwritten.
  ///
  /// This is the answer a *file* is given, and it is also how the controller
  /// files an image it accepts on arrival — the same road, reached with the
  /// folder already decided (see [_acceptIntoDefault]). Text never arrives here:
  /// the controller accepts it on arrival and it is never awaiting a decision by
  /// the time a UI could call this, so passing one throws
  /// [AppRefusal.offerAlreadyAnswered].
  Future<void> acceptInto(
    IncomingTransfer transfer,
    Directory directory,
  ) async {
    if (!transfer.isDecidable) {
      throw const AppStateException(AppRefusal.offerAlreadyAnswered);
    }
    final sinks = <String, PayloadSink>{};
    final landings = <_Landing>[];
    var accepted = false;
    try {
      for (final item in transfer.items) {
        // Only an item with a digest carries a byte stream to write; a text or
        // clipboard item arrives inline and takes no sink.
        if (!item.hasDigest) continue;
        final staged = stagingPathFor(directory, item.name);
        final sink = await FilePayloadSink.open(staged);
        sinks[item.id] = sink;
        landings.add(
          _Landing(
            sink: sink,
            staged: staged,
            directory: directory,
            name: item.name,
          ),
        );
      }
      await transfer.accept(
        itemIds: [for (final item in transfer.items) item.id],
        sinks: sinks,
      );
      accepted = true;
    } finally {
      if (!accepted) await _abandonLandings(landings);
    }
    // `accept` returns once the answer is on the wire, not once the bytes are —
    // those are still to cross, and a path recorded here would name a file that
    // is empty or half written. A UI that drew from it would try to decode a
    // picture that is not there yet, fail, and have nothing to re-trigger the
    // decode when the bytes finally landed. So the path is held back until the
    // digests verify — the same standard [_Tracked]'s own doc sets — and
    // recorded then. It is kept for the first landed item because that is what
    // an image message carries; a multi-file offer leaves this null and keeps
    // its names.
    //
    // A Transfer that never completes reports no path and leaves nothing
    // behind: what it staged is deleted, because a file that never arrived
    // should not be found later under a name that says it did.
    if (landings.isNotEmpty) {
      unawaited(
        transfer.outcome.then((outcome) async {
          if (outcome is TransferCompleted) {
            final landed = await _publishLandings(landings);
            if (landed != null) _recordLocalPath(transfer, landed);
          } else {
            await _abandonLandings(landings);
          }
          _notify();
        }),
      );
    }
    _notify();
  }

  /// Moves [landings] out of their staging names and into the names they keep.
  ///
  /// Answers the first one's path — the one an image message carries — or null
  /// when none of them could be moved.
  Future<String?> _publishLandings(List<_Landing> landings) async {
    String? first;
    for (final landing in landings) {
      // A rename needs the handle gone, and awaiting the close is what makes
      // sure of it — a Transfer closes its sinks as it settles, but that runs
      // alongside this and may not have finished.
      await landing.sink.close();
      try {
        final finalPath = incomingPathFor(landing.directory, landing.name);
        await landing.staged.rename(finalPath.path);
        first ??= finalPath.path;
      } on Object {
        // A file that could not be given its name cannot be kept under a name
        // nobody chose either, and leaving it behind would be the litter this
        // arrangement exists to remove. The Transfer has already ended, so all
        // that is left to do is not litter.
        await _discardStaged(landing.staged);
      }
    }
    return first;
  }

  /// Closes and deletes everything [landings] staged.
  Future<void> _abandonLandings(List<_Landing> landings) async {
    for (final landing in landings) {
      await landing.sink.close();
      await _discardStaged(landing.staged);
    }
  }

  Future<void> _discardStaged(File staged) async {
    try {
      if (await staged.exists()) await staged.delete();
    } on Object {
      // Best effort: a staging file that will not delete is not worth turning
      // anything else into a failure, and it is named as what it is.
    }
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

  /// Removes [view]'s message from this Device's record of the conversation.
  ///
  /// One-sided, and deliberately so. "Delete a message" means "take it off my
  /// screen" in every messaging application a user has met: the file this
  /// Device received stays where it landed, and the peer is told nothing.
  /// There is no wire message for this and there should not be one — a
  /// conversation that either end could edit is a conversation nobody can
  /// trust, and the whole product rests on the two Devices reporting the same
  /// bytes.
  ///
  /// A message that is still in flight goes as well, and *without* cancelling
  /// it. Stopping a send is a different thing, and it is offered a line above
  /// in the same menu; deleting is about this Device's record rather than
  /// about the wire. The record is flagged instead, so that the ending — which
  /// arrives a moment later, from a Transfer the engine still owns — does not
  /// put the message back on screen.
  ///
  /// Written out before returning, so a message a user watched disappear does
  /// not come back after a restart. A failure to write is a notice rather than
  /// an exception, for the same reason every other failure to write is: the
  /// message is gone from the screen, which is what was asked for, and the
  /// only part at risk is whether it stays gone across runs.
  Future<void> deleteMessage(TransferView view) async {
    final handle = view.handle;
    for (final tracked in _transfers) {
      if (_handleOf(tracked) == handle) tracked.dismissed = true;
    }
    _transfers.removeWhere((tracked) => _handleOf(tracked) == handle);
    _history.removeWhere((record) => record.handle == handle);
    _pruneReading();
    _notify();
    await _persistHistory();
  }

  /// Drops reading state for peers this Device no longer holds anything for.
  ///
  /// Called after a deletion, which is the one thing that can empty a
  /// conversation. Without it the map would keep an entry per peer ever talked
  /// to and never lose one, and a Device that had been forgotten would keep a
  /// watermark that nothing could ever compare against — harmless, but a file
  /// that grows for no reason, and one that would silently resurrect an
  /// old read position if the peer came back.
  void _pruneReading() {
    _reading.retainOnly({
      for (final view in transfers)
        if (view.kind != PayloadKind.clipboard) view.peer.hex,
    });
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
        keepAliveInterval: keepAliveInterval,
        keepAliveTimeout: keepAliveTimeout,
        wrapSocket: wrapSocket,
        dialSocket: dialSocket,
      );
      await _serveSessionLayer(manager);
      _manager = manager;
      _managerKey = key;
      _managerSecret = wanted;
      _linkWatch = manager.events.listen(
        _onLinkEvent,
        onError: (Object error) => _notice('the link manager failed: $error'),
      );
    }
    await _syncDiscovery(_announcedDescriptor());
  }

  /// Starts the Session listener on the preferred port, or any free port.
  ///
  /// The fixed port is what lets a peer dial without Discovery, but it is not
  /// worth failing startup over. Windows can reserve a range for WinNAT or
  /// Hyper-V and refuse every bind inside it with `WSAEACCES`; another process
  /// can hold the port just as effectively. Discovery advertises the port the
  /// manager actually bound, so falling back keeps automatic reconnects working.
  Future<void> _serveSessionLayer(LinkManager manager) async {
    try {
      await manager.serve(port: _sessionListenPort);
    } on SocketException {
      if (_sessionListenPort == 0) rethrow;
      await manager.serve(port: 0);
      _notice(
        'session port $_sessionListenPort could not be bound; '
        'listening on ${manager.listenPort} instead',
      );
    }
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
        await _servePairingLayer(pairing);
      } else {
        await pairing.stopReceiving();
      }
    } on Object catch (error) {
      _notice('this Device cannot answer Pairing requests: $error');
    }
    await _syncDiscovery(_announcedDescriptor());
  }

  /// Starts the Pairing listener on the preferred port, or any free port.
  ///
  /// The same WinNAT and Hyper-V reservations that can deny the Session port can
  /// deny the Pairing port. A fallback keeps this Device answerable, and the
  /// actual port travels in Discovery so another Device still knows where to
  /// send the request.
  Future<void> _servePairingLayer(PairingService pairing) async {
    try {
      await pairing.receive(port: _pairingPort);
    } on PairingException {
      if (_pairingPort == 0) rethrow;
      final port = await pairing.receive(port: 0);
      _notice(
        'pairing port $_pairingPort could not be bound; '
        'answering on $port instead',
      );
    }
  }

  Future<void> _syncDiscovery(DeviceDescriptor? advertised) async {
    final local = _requireLocal();
    final descriptor = _withPairingPort(
      advertised ?? _descriptorOf(local.profile),
    );
    final key =
        '${descriptor.alias}\u0000${descriptor.listenPort}\u0000'
        '${descriptor.pairingPort}\u0000${descriptor.fingerprint.hex}';
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
      // A peer that has just appeared, or that is somewhere new, is worth
      // dialling at once, whatever the last few attempts said. The backoff
      // exists for a peer that is not answering at the address we have; a
      // peer that has announced itself has just told us it is there.
      final previous = {
        for (final peer in _discovered)
          peer.fingerprint.hex: peer.address.address,
      };
      for (final peer in peers) {
        final wasKnown = previous[peer.fingerprint.hex];
        if (wasKnown != null && wasKnown == peer.address.address) continue;
        final known = _local?.profile.known(peer.fingerprint)?.lastAddress;
        if (wasKnown == null && known == peer.address.address) continue;
        _autoDue.remove(peer.fingerprint.hex);
        _autoFailures.remove(peer.fingerprint.hex);
      }
      _discovered = peers;
      _autoConnectPeers();
      _notify();
    }, onError: (Object error) => _notice('discovery failed: $error'));
    discovery.start();
  }

  /// The peers an automatic connect is currently trying, by fingerprint hex.
  ///
  /// This is what keeps a slow attempt from stacking a second one on top of
  /// the first.
  final Set<String> _autoConnecting = {};

  /// When each peer's next automatic attempt becomes due, by fingerprint hex.
  ///
  /// Absent means "as soon as the sweep next runs". A peer that has just been
  /// discovered is dialled at once; a peer whose dial keeps failing is left
  /// alone for longer and longer, so a Device that is switched off does not
  /// cost a dial every two seconds for ever.
  ///
  /// The value is a number of *sweeps* rather than a point in time, so the
  /// pause is measured by the same clock that runs the sweep. A deadline
  /// against a wall clock would be judged by a different clock, and the two
  /// could disagree about when a peer is due.
  final Map<String, int> _autoDue = {};

  /// How many consecutive automatic attempts have failed, by fingerprint hex.
  final Map<String, int> _autoFailures = {};

  /// The timer that keeps the open Sessions in step with the paired peers.
  Timer? _reconnectTimer;

  /// How many sweeps have run since the sweep started.
  ///
  /// The count is what the retry pause is measured in, so it only ever moves
  /// when the sweep actually runs.
  int _sweeps = 0;

  /// How often the sweep looks for a peer that should be connected.
  ///
  /// Short enough that a network coming back feels immediate, long enough
  /// that the sweep costs nothing measurable: it only dials a peer that is
  /// paired and not connected, and a connected peer is left alone.
  static const Duration _reconnectInterval = Duration(seconds: 2);

  /// Opens Sessions to every paired peer Discovery has placed.
  ///
  /// A paired Device that has just been discovered is not a stranger to be
  /// introduced: the user already paired it, and the Session it needs is the
  /// same one the Connect button opens, so the controller opens it on the
  /// user's behalf. Both ends try, because neither knows which direction the
  /// network allows — a Device whose inbound is firewalled cannot be reached,
  /// but it can still do the reaching — and two dials to one peer resolve the
  /// way the Session layer always resolves a duplicate: one Session survives,
  /// and the loser finds the peer connected instead.
  ///
  /// Discovery only emits on a visible change — a peer that is new, or new
  /// where it is — so this does not fire on every routine announce. An
  /// attempt that fails is not retried here: the sweep comes back, and the
  /// pause between attempts grows with every failure, so a Device that is
  /// switched off costs less and less attention the longer it stays off. The
  /// Connect button stays on the conversation row, and a firewall is not
  /// worth a notice every time the app starts.
  void _autoConnectPeers() {
    _reconcilePeers();
  }

  /// Brings the set of open Sessions in line with the paired peers.
  ///
  /// Called on every discovery change *and* on a timer, because neither
  /// alone is enough to bring a Session back after a network outage:
  ///
  /// * Discovery reports a peer only when something a user could see about
  ///   it changes — it is new, or it is somewhere else. A peer that comes
  ///   back at the same address after a short outage changes nothing, so
  ///   discovery says nothing at all and there is no event to react to.
  /// * A lost Session is not something discovery knows about. The Session
  ///   layer reports it, and the report has to be turned into a dial — for
  ///   the peer to be dialled, something has to notice it is no longer
  ///   connected.
  ///
  /// The sweep is what covers both: it looks at the paired peers and dials
  /// the ones that are not connected, over and over, with a growing pause
  /// between attempts so a peer that is switched off costs less and less
  /// attention the longer it stays off.
  ///
  /// The peers come from the Owner Group rather than from Discovery's list,
  /// because a peer that has dropped off the link is exactly the one that
  /// has to be dialled: the Group is the record of who belongs here, and
  /// Discovery's list is the record of who is reachable *right now*.
  void _reconcilePeers() {
    final local = _local;
    if (local == null || _closed) return;
    for (final peer in local.profile.group.members) {
      if (peer == local.profile.self) continue;
      if (_wired.containsKey(peer.hex)) continue;
      // A peer that is being dialled right now is left alone: a second dial
      // to the same peer would lose the race to the one already running, and
      // losing it is reported as a failure.
      if (_autoConnecting.contains(peer.hex)) continue;
      final due = _autoDue[peer.hex];
      if (due != null && _sweeps < due) continue;
      if (!_autoConnecting.add(peer.hex)) continue;
      unawaited(_autoConnect(peer));
    }
  }

  /// One automatic connect: one dial, and a note of when to try again.
  ///
  /// Unlike [connectAfterPairing] this is not racing a peer that is
  /// certainly coming up, so a failure here is not retried immediately: the
  /// sweep comes back, and the pause between attempts grows with every
  /// failure. That is what makes a peer that is simply switched off cheap to
  /// wait for, and what lets a peer whose network has come back be reached
  /// without anybody asking.
  Future<void> _autoConnect(Fingerprint peer) async {
    try {
      await connect(peer);
      _autoFailures.remove(peer.hex);
      _autoDue.remove(peer.hex);
    } on HandshakeException {
      // Both ends of a pair auto-connect, and one dial of the two loses:
      // the Session layer closes a second Session to a peer it already
      // holds. A Session by now is the race resolving the good way.
      if (_wired.containsKey(peer.hex)) {
        _autoFailures.remove(peer.hex);
        _autoDue.remove(peer.hex);
        return;
      }
      _scheduleRetry(peer);
    } on SocketException {
      // Nothing listening where the beacon said, or the peer is
      // unreachable from here; the next sweep, or the peer's own dial,
      // is the way through.
      _scheduleRetry(peer);
    } on AppStateException catch (error) {
      if (error.refusal == AppRefusal.sessionAlreadyOpen) {
        // The peer dialled us first. The Session is up, which is what this
        // dial was for.
        _autoFailures.remove(peer.hex);
        _autoDue.remove(peer.hex);
        return;
      }
      // No address for the peer yet; the next beacon brings one.
      _scheduleRetry(peer);
    } finally {
      _autoConnecting.remove(peer.hex);
    }
  }

  /// Notes that a peer's dial failed, and when to try again.
  ///
  /// The pause grows with every failure and stops growing at half a minute,
  /// so a peer that is switched off is still retried — and is picked up
  /// within half a minute of coming back — without costing a dial every
  /// couple of seconds for ever.
  void _scheduleRetry(Fingerprint peer) {
    final failures = (_autoFailures[peer.hex] ?? 0) + 1;
    _autoFailures[peer.hex] = failures;
    // The pause is counted in sweeps, and the sweeps are the interval the
    // pause is measured against: one sweep is the shortest pause, and the
    // longest is a quarter of a minute.
    final sweeps = 1 << (failures - 1);
    _autoDue[peer.hex] =
        _sweeps + (sweeps > _maxRetrySweeps ? _maxRetrySweeps : sweeps);
  }

  /// The longest a peer that keeps failing is left alone before another try.
  static const int _maxRetrySweeps = 15;

  /// Starts the sweep that keeps the Sessions in step with the paired peers.
  void _startReconnectSweep() {
    _reconnectTimer?.cancel();
    _sweeps = 0;
    _reconnectTimer = Timer.periodic(_reconnectInterval, (_) {
      _sweeps += 1;
      _reconcilePeers();
    });
  }

  /// Stops the sweep.
  void _stopReconnectSweep() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    _clipboard?.setAllowedPeers(next.profile.clipboardPeers);
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
    // A Session that ended is a peer that should be connected again. The
    // sweep would get there on its own within a couple of seconds, but the
    // common case — a peer that restarted, or a network that blinked — is
    // one that is back almost immediately, and waiting for the sweep is a
    // visible delay in a conversation that should never have ended.
    _autoDue.remove(peer.hex);
    _autoFailures.remove(peer.hex);
    _reconcilePeers();
    _notify();
  }

  void _onOffer(Fingerprint peer, IncomingTransfer offer) {
    _track(offer, peer);
    // Some offers are not the user's to answer, and the two that are not are
    // answered here rather than by whatever draws them — the class doc says why
    // each one is not a question. Text settles without touching the disk; an
    // image is written into the folder this Device already saves to, which is
    // the answer the dialog would have been given. A file is the opposite in
    // every one of those respects: the user goes looking for it afterwards, so
    // it waits here like everything else.
    final landing = _landingFor(offer);
    if (landing == null) {
      if (!_incoming.isClosed) _incoming.add(offer);
    } else if (landing.isEmpty) {
      unawaited(_acceptInline(offer, peer));
    } else {
      unawaited(_acceptIntoDefault(offer, peer, landing));
    }
    _notify();
  }

  /// Where [offer] lands without the user being asked, or null when it is the
  /// user's to answer.
  ///
  /// The empty string is the third answer, and it is not a folder: a text item
  /// carries its body in the offer, takes no sink and writes nothing, so it
  /// lands *nowhere* — which is a fact worth telling apart from null, the
  /// answer that means "ask the user".
  String? _landingFor(IncomingTransfer offer) {
    switch (offer.kind) {
      case PayloadKind.text:
      case PayloadKind.emoji:
        return '';
      case PayloadKind.image:
        // The folder is the one received files already go to: what the user
        // chose, or the platform's own default. When there is no such folder
        // — a platform with neither — there is nothing to write into, and the
        // offer falls back to being the user's, which is the honest answer
        // rather than a picture filed into a directory nobody named.
        return _local?.profile.incomingDirectory ?? _defaultIncomingDirectory;
      case PayloadKind.file:
      case PayloadKind.clipboard:
        return null;
    }
  }

  /// Accepts an image offer into [directory], with no question asked.
  ///
  /// The same road [acceptInto] takes, reached without a dialog: the folder is
  /// created first, because "the images go to Downloads/LocalTransfer" has to
  /// be true the first time it is used.
  Future<void> _acceptIntoDefault(
    IncomingTransfer offer,
    Fingerprint peer,
    String directory,
  ) async {
    try {
      final folder = Directory(directory);
      folder.createSync(recursive: true);
      await acceptInto(offer, folder);
    } on Object catch (error) {
      // Same reasoning as a text that would not accept: the sender learns
      // through its own outcome, and there is nothing here for the user to
      // answer. A failure is visible as a failed Transfer in the conversation.
      _notice('an image from ${peer.short()} could not be accepted: $error');
    }
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
    final tracked = _Tracked(
      transfer,
      peer,
      at: _clock(),
      localPath: localPath,
    );
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
          // The Transfer has settled, so stamp the clock here — before anything
          // else that this callback does — so the duration a screen prints is
          // the interval the Transfer actually took, not the interval up to
          // whenever the list next happened to rebuild.
          tracked.settledAt = _clock();
          await progress.cancel();
          // An ending is what turns a message into history, and it is archived
          // here rather than when the Transfer was tracked because a Transfer
          // that never ended has nothing to remember: a question nobody
          // answered is a connection's state, not something that happened.
          //
          // Unless the user deleted it while it was still going. Deleting is
          // the whole of what they asked for, and writing the message back the
          // moment it ended would undo the delete a breath after it was made.
          if (!tracked.dismissed) await _remember(tracked);
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
      at: tracked.at,
      settledAt: tracked.settledAt,
      state: transfer.state,
      transferredBytes: transfer.transferredBytes,
      totalBytes: transfer.totalBytes,
      names: [for (final item in transfer.items) item.name],
      text: transfer.text,
      localPath: tracked.localPath,
      // Text and an image the controller can file are never handed out as a
      // decision: it answers both on arrival, so an offer of one that still
      // reads as decidable is an answer in flight rather than a question on
      // screen, and a UI that drew Accept/Refuse for that frame would be
      // drawing a question already being answered. Belt beside the braces of
      // `_onOffer` — this is the single place that decides what a UI is
      // allowed to answer, so the rule lives here too.
      offer: _answerableOffer(transfer),
      send: transfer is OutgoingTransfer && !transfer.isSettled
          ? transfer
          : null,
    );
  }

  /// [transfer] as an offer only the user can settle, or null for everything
  /// else.
  ///
  /// Answerable means a *file* offer, which is what the two buttons in a bubble
  /// and on a Transfers card exist for. Everything the controller settles on its
  /// own answers null here: text, and an image it has a folder to put in. See
  /// [_landingFor] — the rule the two share is consulted rather than restated, so
  /// that a platform with no folder to offer keeps its image prompt.
  IncomingTransfer? _answerableOffer(Transfer transfer) {
    if (transfer is! IncomingTransfer || !transfer.isDecidable) return null;
    return _landingFor(transfer) == null ? transfer : null;
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

  int? _pairingPortAt(String host) {
    for (final discovered in _discovered) {
      if (discovered.address.address == host) return discovered.pairingPort;
    }
    return null;
  }

  String _keyOf(LocalProfile local) =>
      '${local.profile.alias}\u0000${local.profile.self.hex}';

  DeviceDescriptor _announcedDescriptor() {
    final local = _requireLocal();
    return _withPairingPort(
      _manager?.advertised ?? _descriptorOf(local.profile),
    );
  }

  DeviceDescriptor _withPairingPort(DeviceDescriptor descriptor) {
    final pairingPort = _pairing?.receivingPort;
    if (descriptor.pairingPort == pairingPort) return descriptor;
    return DeviceDescriptor(
      fingerprint: descriptor.fingerprint,
      alias: descriptor.alias,
      platform: descriptor.platform,
      capability: descriptor.capability,
      listenPort: descriptor.listenPort,
      pairingPort: pairingPort,
    );
  }

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

  /// Reads the remembered conversation back, if there is one to read.
  ///
  /// A history that cannot be decoded is reported and then left empty rather
  /// than raised: the file is a record of things that already happened, and a
  /// Device that refused to start over one would be trading the ability to talk
  /// for the ability to scroll back. Nothing is lost by it either — the store
  /// moves the damaged bytes aside before this returns — and the sentence in
  /// [notices] is what tells the user that something happened at all.
  Future<void> _loadHistory() async {
    final store = _messages;
    if (store == null) return;
    try {
      final remembered = await loadConversation(store);
      _history
        ..clear()
        ..addAll(remembered.messages);
      _reading = remembered.reading;
    } on Object catch (error) {
      _history.clear();
      _reading = ConversationReading();
      _notice('the conversation could not be read back: $error');
    }
  }

  /// Remembers a settled Transfer, and writes the conversation out.
  ///
  /// Called once per Transfer, when it ends. Bounded by [maxRememberedMessages]
  /// from the oldest end, which is the end a person scrolls away from first.
  Future<void> _remember(_Tracked tracked) async {
    final store = _messages;
    if (store == null) return;
    final record = _recordOf(tracked);
    // Replaced rather than appended when the handle is already known. The two
    // lists are joined on that handle, so a second copy would be a message that
    // draws once and whose deletion removes one of two entries.
    _history.removeWhere((existing) => existing.handle == record.handle);
    _history.add(record);
    if (_history.length > maxRememberedMessages) {
      _history.removeRange(0, _history.length - maxRememberedMessages);
    }
    await _persistHistory();
  }

  /// Writes the conversation out through the store.
  ///
  /// A failure is a notice rather than an exception, for the same reason a
  /// failed profile save is one: the messages are still in memory and still on
  /// screen, and what the user has lost is the part that would have outlived
  /// the process. Saying so is the honest answer; failing the Transfer that
  /// just completed over it would blame the wrong thing.
  Future<void> _persistHistory() async {
    final store = _messages;
    if (store == null) return;
    try {
      await saveConversation(
        StoredConversation(messages: _history, reading: _reading),
        store,
      );
    } on Object catch (error) {
      _notice('the conversation could not be saved: $error');
    }
  }

  /// Whether the conversation is kept between runs at all.
  bool get remembersConversation => _messages != null;

  /// [tracked] as the message that will be remembered.
  MessageRecord _recordOf(_Tracked tracked) {
    final transfer = tracked.transfer;
    return MessageRecord(
      peer: tracked.peer,
      id: transfer.id,
      direction: transfer.direction,
      kind: transfer.kind,
      at: tracked.at,
      settledAt: tracked.settledAt,
      state: transfer.state,
      names: [for (final item in transfer.items) item.name],
      totalBytes: transfer.totalBytes,
      text: transfer.text,
      localPath: tracked.localPath,
    );
  }

  /// A remembered message, as a UI renders it.
  ///
  /// The live parts are absent because they no longer exist: this message
  /// belonged to a Session that ended with an earlier run of the program, and
  /// there is nothing left to answer or to stop. Everything else is either
  /// stored or implied by the ending — a settled Transfer has every accepted
  /// byte, which is why the fraction below is one rather than derived.
  TransferView _viewOfRecord(MessageRecord record) => TransferView(
    id: record.id,
    direction: record.direction,
    kind: record.kind,
    peer: record.peer,
    at: record.at,
    settledAt: record.settledAt,
    state: record.state,
    transferredBytes: record.totalBytes,
    totalBytes: record.totalBytes,
    names: record.names,
    text: record.text,
    localPath: record.localPath,
    offer: null,
    send: null,
  );

  /// What names [tracked]'s message for as long as it is remembered.
  String _handleOf(_Tracked tracked) =>
      messageHandle(tracked.peer, tracked.transfer.id);

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

/// One item's bytes on their way to the name they will keep.
///
/// A received file has two names: the one it wears while its bytes are crossing
/// — [staged], which this Device made up and which says it is unfinished — and
/// the one it ends up under, decided when the bytes have been verified. Keeping
/// both here, rather than recomputing the second, is what makes the rename a
/// single step with nothing to re-derive in between.
final class _Landing {
  _Landing({
    required this.sink,
    required this.staged,
    required this.directory,
    required this.name,
  });

  /// Where the bytes are being written.
  final PayloadSink sink;

  /// The file they are being written into.
  final File staged;

  /// The folder that will hold the finished file.
  final Directory directory;

  /// The peer's name for the item, before sanitising and any numbering.
  final String name;
}

/// A Transfer and the Device it is with.
final class _Tracked {
  _Tracked(this.transfer, this.peer, {required this.at, this.localPath});

  final Transfer transfer;
  final Fingerprint peer;

  /// When this Transfer was first tracked.
  ///
  /// Read once, at the moment the Transfer enters the conversation, from the
  /// controller's own clock. The engine's `Transfer` carries no time of its
  /// own — it is a protocol object and a protocol object has no business
  /// knowing what a wall clock says — so this is where "when was this said"
  /// is decided, and a conversation list that wants to print a time reads it
  /// from here rather than inventing one at render time.
  final DateTime at;

  /// When this Transfer ended, or null while it is still going.
  ///
  /// Written once, from the controller's clock, at the moment the Transfer
  /// settles. A duration is the one thing a finished Transfer has to say that
  /// nothing else does, and it cannot be recovered after the fact: the engine
  /// keeps no time of its own, so the interval needs both of its ends stored.
  DateTime? settledAt;

  /// Where this Transfer's bytes live on *this* machine, once they do.
  ///
  /// It answers two questions, and they have different rules about when it can
  /// be believed. A conversation draws an image from it, so a *received* image
  /// is given a path only when every byte is present — a path still being
  /// written to would draw half a picture or fail outright. A "show me where
  /// this went" action resolves it to a folder, so a received file names the
  /// first item that landed and a file the user sent names the file they chose.
  /// Null for a text or clipboard Transfer, which has no file, and for a
  /// multi-item send, whose sources do not have to name a path.
  String? localPath;

  /// Whether the user removed this message from the conversation.
  ///
  /// Set by [deleteMessage], which drops the message from the live list and
  /// the history at once. A Transfer that is still in flight outlives that —
  /// the engine owns it until it ends, and this wrapper is one of the places
  /// that reaches it from — so the flag is what keeps the ending of a deleted
  /// message from putting it back on screen. Nothing else reads it: a message
  /// deleted after it settled is simply gone, and the callback that would have
  /// archived it has already run.
  bool dismissed = false;
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
  int? pairingPort;
  DateTime? lastSeen;
  bool connected = false;

  /// Whether Discovery placed this Device, i.e. whether [alias] and [platform]
  /// were read from a beacon this Device announced rather than from a memory.
  ///
  /// The distinction exists because a beacon is re-sent every few seconds and a
  /// handshake never is. Anything a Session pinned at connect time is older
  /// than the freshest beacon by construction, so the two cannot be ranked by
  /// "which loop ran last" — this records which one actually knows more.
  bool fromDiscovery = false;
}

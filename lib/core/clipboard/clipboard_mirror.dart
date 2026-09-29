import 'dart:async';
import 'dart:collection';
import 'dart:math';

import '../identity/fingerprint.dart';
import '../identity/owner_group.dart';
import '../protocol/messages.dart';
import 'clipboard_capability.dart';
import 'clipboard_channel.dart';
import 'clipboard_entry.dart';
import 'system_clipboard.dart';

/// How a Device treats the clipboard.
///
/// The three settings control capture and application together, because a user
/// thinks of clipboard sync as one switch and not as two. What they mean in
/// terms of the two directions:
///
/// * [off] — nothing is captured and nothing is applied. The Device does not
///   even watch its clipboard.
/// * [stage] — a local copy travels to the Owner Group as usual, but an
///   incoming entry waits for the user instead of replacing the clipboard.
/// * [mirror] — a local copy travels, and an incoming entry replaces the system
///   clipboard with no user action.
///
/// Which of those are *possible* is not the user's choice: it is what
/// `ClipboardCapability` says about the platform, and it is enforced here
/// rather than merely displayed.
enum ClipboardMode {
  /// Clipboard sync is off in both directions.
  off('off'),

  /// Incoming entries wait for the user.
  stage('stage'),

  /// Incoming entries replace the clipboard automatically.
  mirror('mirror');

  const ClipboardMode(this.wireName);

  /// The value used in persisted state.
  final String wireName;

  /// Whether this mode captures local copies at all.
  bool get captures => this != ClipboardMode.off;

  /// Resolves a wire value, or throws [FormatException] if unknown.
  static ClipboardMode fromWireName(String value) {
    for (final mode in ClipboardMode.values) {
      if (mode.wireName == value) return mode;
    }
    throw FormatException('unknown clipboard mode "$value"');
  }
}

/// Keeps one Device's clipboard and its Owner Group's clipboards in step.
///
/// One mirror covers every peer this Device is talking to: echo suppression,
/// duplicate detection and ordering are properties of the *clipboard*, not of a
/// Session, and a per-peer mirror would have to relearn all three per peer and
/// would still get the two-Device loop wrong.
///
/// ## Three gates, and why each one exists
///
/// **The Owner Group gate.** An entry is captured only for peers in the group,
/// and applied only when it came from a member. This is the security boundary:
/// the Session already proves the peer knows the Pairing Secret, but a Secret
/// can be shared with a Device that has no business reading this clipboard.
///
/// **The capability gate.** Reading and writing the clipboard are governed by
/// different platform rules, so a Device can be a Mirror target without being
/// able to originate one. A platform that cannot read is never watched, and a
/// platform that cannot write refuses to apply rather than pretending.
///
/// **The origin gate.** An incoming entry must claim the peer it arrived from,
/// because the tag is what a Device uses to recognise its own content coming
/// back. A peer that relays somebody else's entry under a new tag would put
/// content into the group that never belonged to it.
final class ClipboardMirror {
  ClipboardMirror({
    required this._group,
    required this._capability,
    required this._clipboard,
    this._mode = ClipboardMode.off,
    DateTime Function()? clock,
    Random? random,
    this.onNotice,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  /// How many applied values are remembered to recognise our own echo.
  static const int _echoMemory = 16;

  /// How many entries are remembered to drop a duplicate.
  static const int _seenMemory = 256;

  /// How many staged entries are held before the oldest is dropped.
  static const int _stagedMemory = 8;

  /// The number of random bytes in an entry id.
  static const int _entryIdBytes = 12;

  OwnerGroup _group;
  final ClipboardCapability _capability;
  final SystemClipboard _clipboard;
  final DateTime Function() _clock;
  final Random _random;
  ClipboardMode _mode;

  /// Called with a readable line when an entry is refused or dropped.
  ///
  /// For logs and for whoever is debugging a pair of Devices. Nothing here is
  /// sent to the peer: mirroring has no reply, so there is nowhere to send it.
  final void Function(String message)? onNotice;

  final Map<Fingerprint, _MirrorPeer> _peers = {};
  final StreamController<ClipboardEntry> _stagedEntries =
      StreamController<ClipboardEntry>.broadcast();
  final StreamController<ClipboardEntry> _appliedEntries =
      StreamController<ClipboardEntry>.broadcast();
  final List<ClipboardEntry> _staged = [];

  /// Values this Device has applied, oldest first, to recognise our own echo.
  final Queue<String> _appliedTexts = Queue<String>();

  /// Entry ids already handled, oldest first, to drop a duplicate.
  final Queue<String> _seenEntryIds = Queue<String>();
  final Set<String> _seenEntryIdSet = {};

  /// The newest `capturedAt` accepted from each origin.
  ///
  /// Compared per origin only: Device clocks are not synchronised, so a
  /// timestamp from one Device says nothing about a timestamp from another.
  final Map<Fingerprint, DateTime> _newestSeen = {};

  StreamSubscription<String>? _watch;
  bool _running = false;
  bool _closed = false;

  /// This Device's own Fingerprint.
  Fingerprint get self => _group.self;

  /// The Devices whose clipboards are shared with this one.
  OwnerGroup get group => _group;

  /// What this platform lets the clipboard do, in each direction.
  ClipboardCapability get capability => _capability;

  /// How the clipboard is being treated.
  ClipboardMode get mode => _mode;

  /// Whether [start] has been called and [stop] has not.
  bool get isRunning => _running;

  /// Entries received in [ClipboardMode.stage], in arrival order.
  ///
  /// A list rather than only a stream because the user has to be able to see
  /// the entries that are waiting after a rebuild.
  List<ClipboardEntry> get stagedEntries => List.unmodifiable(_staged);

  /// Fires for each entry that arrives while staging.
  Stream<ClipboardEntry> get staged => _stagedEntries.stream;

  /// Fires for each entry this Device put on the system clipboard.
  ///
  /// Covers both a Mirror and an entry the user staged and then accepted, so a
  /// UI can show one history without caring which path produced it.
  Stream<ClipboardEntry> get applied => _appliedEntries.stream;

  /// Begins watching the clipboard. Idempotent.
  void start() {
    if (_closed) throw StateError('this clipboard mirror is closed');
    _running = true;
    _syncWatch();
  }

  /// Stops watching the clipboard, leaving the Owner Group as it stands.
  Future<void> stop() async {
    _running = false;
    await _syncWatch();
  }

  /// Changes how the clipboard is treated, starting or stopping the watcher as
  /// the new mode requires.
  void setMode(ClipboardMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    unawaited(_syncWatch());
  }

  /// Replaces the Owner Group, detaching any peer that is no longer in it.
  ///
  /// Called when a Pairing admits a Device or a user forgets one. Peers that
  /// remain are kept, because their Sessions are still open.
  void setGroup(OwnerGroup group) {
    _group = group;
    for (final fingerprint in _peers.keys.toList()) {
      if (!group.contains(fingerprint)) detachPeer(fingerprint);
    }
  }

  /// Starts listening to [channel] as [fingerprint]'s clipboard conversation.
  ///
  /// Re-attaching the same Fingerprint replaces the previous channel, so a
  /// Device that reconnects does not end up mirrored twice.
  void attachPeer({
    required Fingerprint fingerprint,
    required ClipboardChannel channel,
  }) {
    detachPeer(fingerprint);
    final peer = _MirrorPeer(fingerprint, channel);
    _peers[fingerprint] = peer;
    peer.subscription = channel.entries.listen(
      (message) => _onPeerEntry(peer, message),
      onError: (Object error) {
        onNotice?.call(
          'the clipboard conversation with ${fingerprint.short()} failed: '
          '$error',
        );
      },
    );
  }

  /// Stops listening to [fingerprint]'s clipboard conversation.
  void detachPeer(Fingerprint fingerprint) {
    final peer = _peers.remove(fingerprint);
    if (peer == null) return;
    final subscription = peer.subscription;
    peer.subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// Accepts a staged entry into the system clipboard.
  ///
  /// The gate is re-checked here rather than trusted from [stagedEntries],
  /// because this is the one path a caller can drive directly.
  Future<void> apply(ClipboardEntry entry) async {
    if (entry.origin != self && !_group.contains(entry.origin)) {
      onNotice?.call(
        'refused to apply an entry from ${entry.origin.short()}, which is not '
        'in this Owner Group',
      );
      return;
    }
    if (!_capability.canApply) {
      onNotice?.call('this platform cannot apply a clipboard entry');
      return;
    }
    if (entry.isEmpty) return;
    _staged.removeWhere((held) => held.entryId == entry.entryId);
    _rememberAppliedText(entry.text);
    await _clipboard.write(entry.text);
    if (!_appliedEntries.isClosed) _appliedEntries.add(entry);
  }

  /// Releases the watcher, every peer subscription, and both streams.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _running = false;
    final watch = _watch;
    _watch = null;
    if (watch != null) await watch.cancel();
    for (final fingerprint in _peers.keys.toList()) {
      detachPeer(fingerprint);
    }
    unawaited(_stagedEntries.close());
    unawaited(_appliedEntries.close());
  }

  Future<void> _syncWatch() async {
    if (_closed) return;
    // Watching a clipboard this platform cannot read would be pointless work on
    // a good day and a permission prompt on a bad one.
    final wanted = _running && _mode.captures && _capability.canOriginate;
    if (wanted == (_watch != null)) return;
    if (wanted) {
      _watch = _clipboard.changes.listen(
        _onLocalCopy,
        onError: (Object error) {
          onNotice?.call('the clipboard watcher failed: $error');
        },
      );
      return;
    }
    final watch = _watch;
    _watch = null;
    if (watch != null) await watch.cancel();
  }

  void _onLocalCopy(String text) {
    if (_closed || !_mode.captures || !_capability.canOriginate) return;
    if (text.isEmpty) return;
    // The platform reports back the write we just did. That is not a copy, and
    // sending it onward is the first step of a loop that never settles.
    if (_appliedTexts.remove(text)) return;
    final entry = ClipboardEntry(
      entryId: _newEntryId(),
      origin: self,
      text: text,
      capturedAt: _clock(),
    );
    for (final peer in _peers.values) {
      if (!_group.contains(peer.fingerprint)) continue;
      unawaited(_push(peer, entry));
    }
  }

  Future<void> _push(_MirrorPeer peer, ClipboardEntry entry) async {
    try {
      await peer.channel.send(entry.toMessage());
    } on Object catch (error) {
      onNotice?.call('could not mirror to ${peer.fingerprint.short()}: $error');
    }
  }

  void _onPeerEntry(_MirrorPeer peer, ClipboardMessage message) {
    if (_closed) return;
    final entry = ClipboardEntry.fromMessage(message);
    // Our own content, coming back. Dropped first and without a word: it is
    // what a peer that did not suppress its own echo sends, and the case is
    // routine enough that complaining about it would fill a log with noise.
    if (entry.origin == self) return;
    // Anything else must claim the peer it arrived from. The tag is how a
    // Device knows whose clipboard a value came from, so a peer relaying
    // somebody else's content under a new tag is putting into the group
    // something that never belonged to it.
    if (entry.origin != peer.fingerprint) {
      onNotice?.call(
        '${peer.fingerprint.short()} sent an entry tagged with '
        '${entry.origin.short()}, which is not the peer it came from',
      );
      return;
    }
    if (!_group.contains(entry.origin)) {
      onNotice?.call(
        'refused a clipboard entry from ${entry.origin.short()}, which is not '
        'in this Owner Group',
      );
      return;
    }
    if (!_rememberEntryId(entry.entryId)) return;
    final newest = _newestSeen[entry.origin];
    if (newest != null && !entry.capturedAt.isAfter(newest)) return;
    _newestSeen[entry.origin] = entry.capturedAt;

    switch (_mode) {
      case ClipboardMode.off:
        return;
      case ClipboardMode.stage:
        _hold(entry);
      case ClipboardMode.mirror:
        unawaited(apply(entry));
    }
  }

  void _hold(ClipboardEntry entry) {
    _staged.add(entry);
    while (_staged.length > _stagedMemory) {
      _staged.removeAt(0);
    }
    if (!_stagedEntries.isClosed) _stagedEntries.add(entry);
  }

  void _rememberAppliedText(String text) {
    _appliedTexts.addLast(text);
    while (_appliedTexts.length > _echoMemory) {
      _appliedTexts.removeFirst();
    }
  }

  /// Returns false when [entryId] has been handled before.
  bool _rememberEntryId(String entryId) {
    if (!_seenEntryIdSet.add(entryId)) return false;
    _seenEntryIds.addLast(entryId);
    while (_seenEntryIds.length > _seenMemory) {
      _seenEntryIdSet.remove(_seenEntryIds.removeFirst());
    }
    return true;
  }

  /// An id the peer cannot collide with by guessing.
  ///
  /// Random rather than derived from the text: an id built from the content
  /// would make two Devices that copied the same string look like one entry,
  /// and the second copy would be dropped as a duplicate.
  String _newEntryId() {
    final buffer = StringBuffer();
    for (var index = 0; index < _entryIdBytes; index++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

final class _MirrorPeer {
  _MirrorPeer(this.fingerprint, this.channel);

  final Fingerprint fingerprint;
  final ClipboardChannel channel;
  StreamSubscription<ClipboardMessage>? subscription;
}

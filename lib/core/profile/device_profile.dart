import '../clipboard/clipboard_capability.dart';
import '../identity/device_descriptor.dart';
import '../identity/fingerprint.dart';
import '../identity/owner_group.dart';

/// A Device this one has dealt with before, remembered so it can be reached
/// and recognised again without Discovery.
///
/// A Known Device is *observations*, not trust. Nothing here grants the peer
/// anything: membership of the Owner Group is the trust decision, and it is
/// recorded there, not here.
final class KnownDevice {
  const KnownDevice({
    required this.fingerprint,
    required this.alias,
    required this.platform,
    this.lastSeen,
    this.lastAddress,
  });

  /// The Device's stable identity.
  final Fingerprint fingerprint;

  /// The Alias the Device last announced. Self-reported, and shown as such.
  final String alias;

  /// The platform the Device last announced.
  final DevicePlatform platform;

  /// When this Device last interacted with the peer, in UTC.
  final DateTime? lastSeen;

  /// The address the peer was last reached at, if it was reached at all.
  final String? lastAddress;

  /// A copy with [alias], [platform], [lastSeen] or [lastAddress] replaced.
  KnownDevice copyWith({
    String? alias,
    DevicePlatform? platform,
    DateTime? lastSeen,
    String? lastAddress,
  }) => KnownDevice(
    fingerprint: fingerprint,
    alias: alias ?? this.alias,
    platform: platform ?? this.platform,
    lastSeen: lastSeen ?? this.lastSeen,
    lastAddress: lastAddress ?? this.lastAddress,
  );

  Map<String, Object?> toJson() => {
    'fp': fingerprint.hex,
    'alias': alias,
    'platform': platform.wireName,
    if (lastSeen != null) 'seen': lastSeen!.toUtc().toIso8601String(),
    if (lastAddress != null) 'addr': lastAddress,
  };

  static KnownDevice fromJson(Map<String, Object?> json) => KnownDevice(
    fingerprint: Fingerprint(_string(json, 'fp')),
    alias: _string(json, 'alias'),
    platform: DevicePlatform.fromWireName(_string(json, 'platform')),
    lastSeen: _optionalDateTime(json, 'seen'),
    lastAddress: _optionalString(json, 'addr'),
  );

  @override
  bool operator ==(Object other) =>
      other is KnownDevice && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;

  @override
  String toString() => 'KnownDevice(${fingerprint.short()}, "$alias")';

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('"$key" must be a string');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('"$key" must be a string when present');
    }
    return value;
  }

  static DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
    final raw = _optionalString(json, key);
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('"$key" is not an ISO-8601 timestamp: "$raw"');
    }
    return parsed;
  }
}

/// Everything this Device knows about itself and the peers it has met.
///
/// This is the model, not the machinery. Loading and saving the profile is
/// the store's concern; claiming the identity on the wire is the handshake's;
/// what is here is the *state* those layers read and write:
///
/// * `alias` and `platform` — what this Device announces about itself;
/// * `group` — the Owner Group, which decides who may receive Mirrors;
/// * `favorites` — peers the user has marked as trusted. A marker the UI shows
///   and nothing more: per-Transfer confirmation is asked of every offer, from
///   every peer, favorited or not (`LocalTransferController` never answers one
///   on the user's behalf). Deliberately weaker than group membership, and
///   deliberately not a way to skip a prompt — see
///   `2026-09-30-pairing-requests-instead-of-a-window.md`;
/// * `acceptsPairingRequests` — whether this Device answers Pairing requests at
///   all. On by default, because a Device that cannot be paired *with* is a
///   Device the user of the other one cannot add; off is what a user who does
///   not want to be asked wants;
/// * `clipboardPeers` — the peers the user has added to the clipboard-sharing
///   whitelist. Deliberately **empty by default**: group membership says a
///   Device may hold a Session, and says nothing about whether it may read
///   this clipboard. Until the user ticks a peer on the Clipboard surface,
///   nothing is mirrored in either direction (see the sharing-whitelist gate
///   in `ClipboardMirror`, the fourth of its four);
/// * `known` — every Device met, favorited or not, for redial without
///   Discovery.
///
/// Mutators mutate in place. A profile is the live state of a running
/// Device, not a value object: an app layer holds one and lets the sessions,
/// the pairing flow and the UI all read the same truth.
final class DeviceProfile {
  DeviceProfile({
    required this.self,
    required String alias,
    required this.platform,
    OwnerGroup? group,
    Set<Fingerprint> favorites = const {},
    Set<Fingerprint> clipboardPeers = const {},
    Map<String, KnownDevice> known = const {},
    this.acceptsPairingRequests = true,
  }) : alias = DeviceProfile._sanitise(alias),
       group = group ?? OwnerGroup(self: self),
       _favorites = {...favorites}
         ..removeWhere((favourite) => favourite == self),
       _clipboardPeers = {...clipboardPeers}
         ..removeWhere((peer) => peer == self),
       _known = {...known}
         ..removeWhere((_, device) => device.fingerprint == self);

  /// This Device's own Fingerprint, from its [OwnerIdentity].
  ///
  /// Present as a field rather than derived from an identity here so the
  /// profile stays serialisable and testable without key material.
  final Fingerprint self;

  /// The Alias this Device announces. Sanitised exactly as a peer-supplied
  /// one would be: the same hostile-name rules apply to a name typed into
  /// this Device's own settings screen.
  String alias;

  /// The platform this Device runs on.
  final DevicePlatform platform;

  /// The Owner Group this Device belongs to. Always contains [self].
  OwnerGroup group;

  /// Whether this Device answers Pairing requests at all.
  ///
  /// The one part of a Pairing a user can turn off. Turning it off stops this
  /// Device listening on the Pairing port, so it can still pair with somebody
  /// else — it just cannot be picked out of a list.
  bool acceptsPairingRequests;

  final Set<Fingerprint> _favorites;
  final Set<Fingerprint> _clipboardPeers;
  final Map<String, KnownDevice> _known;

  /// The Fingerprints marked as favorites, sorted.
  List<Fingerprint> get favorites => _favorites.toList()..sort();

  /// Whether [fingerprint] is a favorite.
  bool isFavorite(Fingerprint fingerprint) => _favorites.contains(fingerprint);

  /// Sets whether [fingerprint] is a favorite.
  ///
  /// Marking [self] is a no-op: favoriting yourself would let a Device skip
  /// its own confirmation prompts, which is meaningless at best.
  void setFavorite(Fingerprint fingerprint, {required bool value}) {
    if (fingerprint == self) return;
    if (value) {
      _favorites.add(fingerprint);
    } else {
      _favorites.remove(fingerprint);
    }
  }

  /// Whether [fingerprint] may receive a Mirror without user action.
  bool canMirrorTo(Fingerprint fingerprint) => group.contains(fingerprint);

  /// The Fingerprints allowed to share the clipboard with this Device, sorted.
  List<Fingerprint> get clipboardPeers => _clipboardPeers.toList()..sort();

  /// Whether [fingerprint] is on the clipboard-sharing whitelist.
  bool isClipboardPeer(Fingerprint fingerprint) =>
      _clipboardPeers.contains(fingerprint);

  /// Sets whether [fingerprint] may share the clipboard with this Device.
  ///
  /// Adding [self] is a no-op: the whitelist decides which *peers* this
  /// Device exchanges clipboard entries with, and this Device is not one of
  /// its own peers.
  void setClipboardPeer(Fingerprint fingerprint, {required bool value}) {
    if (fingerprint == self) return;
    if (value) {
      _clipboardPeers.add(fingerprint);
    } else {
      _clipboardPeers.remove(fingerprint);
    }
  }

  /// Records or refreshes what is known about a peer.
  ///
  /// The fingerprint comes from the map key *and* the entry; when they
  /// disagree the entry wins, because the entry is the claim being made about
  /// itself. Storing the peer under a fingerprint it did not announce would
  /// let one Device poison another's record.
  void noteDevice(KnownDevice device) {
    if (device.fingerprint == self) return;
    _known[device.fingerprint.hex] = device;
  }

  /// What is known about [fingerprint], or null when the Device is unknown.
  KnownDevice? known(Fingerprint fingerprint) => _known[fingerprint.hex];

  /// Every Known Device, sorted by fingerprint.
  List<KnownDevice> get knownDevices =>
      _known.values.toList()
        ..sort((a, b) => a.fingerprint.compareTo(b.fingerprint));

  Map<String, Object?> toJson() => {
    'self': self.hex,
    'alias': alias,
    'platform': platform.wireName,
    'group': group.toJson(),
    'acceptPairingRequests': acceptsPairingRequests,
    'favorites': [for (final favorite in favorites) favorite.hex],
    'clipboardPeers': [for (final peer in clipboardPeers) peer.hex],
    'known': [for (final device in knownDevices) device.toJson()],
  };

  static DeviceProfile fromJson(Map<String, Object?> json) {
    final rawGroup = json['group'];
    final rawFavorites = json['favorites'];
    final rawClipboardPeers = json['clipboardPeers'];
    final rawKnown = json['known'];
    final rawAccepts = json['acceptPairingRequests'];
    final platform = DevicePlatform.fromWireName(_string(json, 'platform'));
    final self = Fingerprint(_string(json, 'self'));
    final group = rawGroup == null
        ? null
        : OwnerGroup.fromJson(_object(rawGroup, 'group'));
    final favorites = <Fingerprint>{};
    if (rawFavorites is List) {
      for (final entry in rawFavorites) {
        if (entry is! String) {
          throw FormatException('"favorites[]" must be a string');
        }
        favorites.add(Fingerprint(entry));
      }
    }
    final clipboardPeers = <Fingerprint>{};
    if (rawClipboardPeers is List) {
      for (final entry in rawClipboardPeers) {
        if (entry is! String) {
          throw FormatException('"clipboardPeers[]" must be a string');
        }
        clipboardPeers.add(Fingerprint(entry));
      }
    }
    final known = <String, KnownDevice>{};
    if (rawKnown is List) {
      for (final entry in rawKnown) {
        final device = KnownDevice.fromJson(_object(entry, 'known[]'));
        known[device.fingerprint.hex] = device;
      }
    }
    return DeviceProfile(
      self: self,
      alias: _string(json, 'alias'),
      platform: platform,
      group: group,
      favorites: favorites,
      clipboardPeers: clipboardPeers,
      known: known,
      // A profile written before this key existed answers requests: the
      // listener is the flow, and a Device that silently stopped being
      // diallable after an upgrade would be a Device nobody can add.
      acceptsPairingRequests: rawAccepts is bool ? rawAccepts : true,
    );
  }

  @override
  String toString() =>
      'DeviceProfile(${self.short()}, "$alias", '
      '${group.length} group, ${_favorites.length} favorites, '
      '${_clipboardPeers.length} clipboard peers, '
      '${_known.length} known, '
      '${acceptsPairingRequests ? 'answering requests' : 'not answering'})';

  /// Delegated to [DeviceDescriptor.sanitiseAlias], so a name is sanitised
  /// identically wherever it enters the system: a name typed into this
  /// Device's own settings screen gets exactly the hostile-name rules a peer
  /// announces through.
  static String _sanitise(String raw) => DeviceDescriptor.sanitiseAlias(raw);
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('"$key" must be a string, got ${value.runtimeType}');
  }
  return value;
}

Map<String, Object?> _object(Object? value, String where) {
  if (value is! Map) {
    throw FormatException('$where must be an object, got ${value.runtimeType}');
  }
  return value.cast<String, Object?>();
}

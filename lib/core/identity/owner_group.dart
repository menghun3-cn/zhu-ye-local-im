import 'fingerprint.dart';

/// The set of Devices that share an Owner.
///
/// Clipboard Mirroring happens only between members of an Owner Group. That is
/// the whole reason the concept exists: "this Device may receive my files" and
/// "this Device may read everything I copy" are different levels of trust, and
/// a single Favorite flag cannot express the difference (see
/// `2026-09-29-owner-identity-gates-clipboard.md`).
///
/// A group is a set of member Fingerprints that includes [self] — this Device
/// belongs to its own group by definition. Membership is per Device rather than
/// per person because Pairing admits one Device at a time, and because a
/// Fingerprint is something a Device can prove it holds.
///
/// This is the model, not the flow. How a Device *joins* a group — a scanned QR
/// code, a typed code with short-authentication-string comparison, and the
/// persistence that survives a restart — is a separate concern, and a separate
/// increment.
final class OwnerGroup {
  /// A group owned by [self], optionally already containing [members].
  ///
  /// [self] is added whether or not it appears in [members], so a group is
  /// never empty and a Device is never outside its own group.
  OwnerGroup({required this.self, Iterable<Fingerprint> members = const []})
    : _members = {self, ...members};

  /// This Device's own Fingerprint. Always a member.
  final Fingerprint self;

  final Set<Fingerprint> _members;

  /// The members, sorted, always including [self].
  List<Fingerprint> get members => _members.toList()..sort();

  /// How many Devices share the Owner.
  int get length => _members.length;

  /// Whether the group holds only this Device.
  bool get isAlone => _members.length == 1;

  /// Whether [fingerprint] shares this Owner.
  bool contains(Fingerprint fingerprint) => _members.contains(fingerprint);

  /// A group with [fingerprint] admitted.
  ///
  /// Returns this group unchanged when it is already a member, so admitting the
  /// same Device twice cannot produce two groups that compare unequal.
  OwnerGroup admitted(Fingerprint fingerprint) => contains(fingerprint)
      ? this
      : OwnerGroup(self: self, members: {..._members, fingerprint});

  /// A group with [fingerprint] removed.
  ///
  /// Removing [self] is a no-op: a Device cannot leave its own group, and
  /// silently producing an empty one would make `contains(self)` false in a way
  /// no caller expects. Removing a Device that is not a member is also a no-op.
  OwnerGroup without(Fingerprint fingerprint) {
    if (fingerprint == self || !contains(fingerprint)) return this;
    return OwnerGroup(
      self: self,
      members: _members.where((member) => member != fingerprint),
    );
  }

  Map<String, Object?> toJson() => {
    'self': self.hex,
    'members': [for (final member in members) member.hex],
  };

  static OwnerGroup fromJson(Map<String, Object?> json) {
    final rawSelf = json['self'];
    if (rawSelf is! String) {
      throw FormatException('"self" must be a string');
    }
    final rawMembers = json['members'];
    if (rawMembers is! List) {
      throw FormatException('"members" must be a list');
    }
    final members = <Fingerprint>[];
    for (final member in rawMembers) {
      if (member is! String) {
        throw FormatException(
          '"members[]" must be a string, got ${member.runtimeType}',
        );
      }
      members.add(Fingerprint(member));
    }
    return OwnerGroup(self: Fingerprint(rawSelf), members: members);
  }

  @override
  bool operator ==(Object other) =>
      other is OwnerGroup &&
      other.self == self &&
      other._members.length == _members.length &&
      other._members.containsAll(_members);

  @override
  int get hashCode =>
      Object.hash(self, Object.hashAllUnordered(_members.toList()));

  /// Names no Fingerprints: which Devices share an Owner is not a log line.
  @override
  String toString() => 'OwnerGroup(${_members.length} devices)';
}

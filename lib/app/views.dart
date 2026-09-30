import 'dart:io';

import '../core/core.dart';

/// What this Device says about itself, for a header or a settings screen.
final class SelfView {
  const SelfView({
    required this.fingerprint,
    required this.alias,
    required this.platform,
    required this.capability,
    required this.isPaired,
    required this.groupLength,
    required this.openSessions,
  });

  /// This Device's stable identity.
  final Fingerprint fingerprint;

  /// The Alias this Device announces.
  final String alias;

  /// The platform this Device runs on.
  final DevicePlatform platform;

  /// What this Device can do with a clipboard, given [platform].
  final ClipboardCapability capability;

  /// Whether this Device holds a group secret, and can therefore hold a
  /// Session at all.
  ///
  /// False means an unpaired Device: it discovers and is discovered, but every
  /// handshake fails because it has no secret to authenticate one with.
  final bool isPaired;

  /// How many Devices are in the Owner Group, this one included.
  final int groupLength;

  /// How many Sessions are open right now.
  final int openSessions;

  /// The first bytes of the Fingerprint, for a compact label.
  String get shortFingerprint => fingerprint.short();
}

/// One Device in the list a UI shows.
///
/// Assembled from four sources with different amounts of knowledge — the Owner
/// Group (a Fingerprint and nothing else), the Known Devices record, whatever
/// Discovery last heard, and a live Session — so most fields are nullable: a
/// Device that is in the group but has never been met has a name of null, and
/// that is a fact about what this Device knows, not a gap in the UI.
final class PeerView {
  const PeerView({
    required this.fingerprint,
    required this.alias,
    required this.platform,
    required this.address,
    required this.sessionPort,
    required this.isConnected,
    required this.isInGroup,
    required this.isFavorite,
    required this.lastSeen,
  });

  /// The Device's stable identity.
  final Fingerprint fingerprint;

  /// The Alias the peer last announced. Self-reported, and shown as such.
  final String? alias;

  /// The platform the peer last announced.
  final DevicePlatform? platform;

  /// The address the peer was last seen at, if it was ever seen.
  final String? address;

  /// The port the peer accepts Sessions on, if it announced one.
  ///
  /// Null means the peer is not accepting Sessions at all — which is what an
  /// unpaired Device announces — so there is nothing to dial.
  final int? sessionPort;

  /// Whether a Session with this peer is open right now.
  final bool isConnected;

  /// Whether this peer is in the Owner Group.
  final bool isInGroup;

  /// Whether Transfers to this peer skip the per-Transfer confirmation.
  final bool isFavorite;

  /// When this Device last heard from the peer, or last had a Session with it.
  final DateTime? lastSeen;

  /// Whether there is both an address and a port to dial.
  bool get isDiallable => address != null && sessionPort != null;

  /// What to show for this peer: its Alias when it has one, its Fingerprint
  /// when it does not.
  String get displayName => alias ?? fingerprint.short();

  /// The first bytes of the Fingerprint, for a compact label.
  String get shortFingerprint => fingerprint.short();
}

/// One Transfer, as a UI renders it.
final class TransferView {
  const TransferView({
    required this.id,
    required this.direction,
    required this.kind,
    required this.peer,
    required this.state,
    required this.transferredBytes,
    required this.totalBytes,
    required this.names,
    required this.offer,
  });

  /// The Transfer's id, unique within the Session it belongs to.
  final String id;

  /// Whether this Device is sending or receiving.
  final TransferDirection direction;

  /// Whether the Transfer carries text, files, or clipboard content.
  final PayloadKind kind;

  /// The Device on the other end.
  final Fingerprint peer;

  /// Where the Transfer has got to.
  final TransferState state;

  /// Bytes moved so far.
  final int transferredBytes;

  /// Bytes in total, over every accepted item.
  final int totalBytes;

  /// The names of the items, in the order the sender listed them.
  final List<String> names;

  /// The live offer while one is waiting to be answered, else null.
  ///
  /// Handed out so a UI can call `accept` or `reject` on it; the controller
  /// will not answer an offer on the user's behalf.
  final IncomingTransfer? offer;

  /// Whether this Device has to answer before anything moves.
  bool get needsDecision =>
      offer != null && state == TransferState.awaitingDecision;

  /// How far along the Transfer is, as a fraction in `0..1`.
  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = transferredBytes / totalBytes;
    if (value <= 0) return 0;
    if (value >= 1) return 1;
    return value;
  }
}

/// A byte count as a person reads it, in binary units.
///
/// Binary because that is what everything below counts in — a chunk is 512
/// KiB, not 512 kB — and a label that quietly rescaled to decimal would
/// disagree with the protocol about a number the user can see twice.
///
/// One decimal below ten units and none above it, because a progress line is
/// read at a glance: "1.5 MiB" is worth the precision, "200 KiB" is not worth
/// the characters.
String formatBytes(int bytes) {
  assert(bytes >= 0, 'a byte count is never negative');
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  const units = ['KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final rendered = value < 10
      ? value.toStringAsFixed(1)
      : value.toStringAsFixed(0);
  return '$rendered ${units[unit]}';
}

/// Where a received file is allowed to land.
///
/// Peer-supplied names are untrusted input: a name is allowed to *name* a file
/// inside the directory the user picked, and is never allowed to escape it. The
/// two functions here are the whole of that rule, kept together so it can be
/// read and tested as one thing.
///
/// There is no path library in this project's dependencies, and a peer-supplied
/// name needs far less than one: no separator survives, so no name can address
/// anything outside the directory it lands in.
String sanitiseIncomingName(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    // Path separators from either convention, plus the characters Windows
    // refuses in a filename, plus control characters. Replacing rather than
    // dropping keeps two distinct names distinct.
    if (rune == 0x2f || rune == 0x5c) {
      buffer.write('_');
      continue;
    }
    if (rune < 0x20 || rune == 0x7f) continue;
    if (const {0x3c, 0x3e, 0x3a, 0x22, 0x7c, 0x3f, 0x2a}.contains(rune)) {
      buffer.write('_');
      continue;
    }
    buffer.writeCharCode(rune);
  }
  // Windows silently drops trailing dots and spaces, which makes two different
  // names collide on one path; a name that is only dots would address a
  // directory, not a file.
  var name = buffer.toString().replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') {
    name = 'received';
  }
  return name;
}

/// A path inside [directory] that no other file is using.
///
/// [name] is peer-supplied and is sanitised first; a clash is resolved by
/// numbering rather than by overwriting, because the existing file may be the
/// user's.
File incomingPathFor(Directory directory, String name) {
  final safe = sanitiseIncomingName(name);
  var candidate = File('${directory.path}${Platform.pathSeparator}$safe');
  if (!candidate.existsSync()) return candidate;
  final dot = safe.lastIndexOf('.');
  final stem = dot > 0 ? safe.substring(0, dot) : safe;
  final suffix = dot > 0 ? safe.substring(dot) : '';
  for (var index = 2; index < 10000; index++) {
    candidate = File(
      '${directory.path}${Platform.pathSeparator}$stem ($index)$suffix',
    );
    if (!candidate.existsSync()) return candidate;
  }
  throw AppStateException(AppRefusal.noFreeFileName, safe);
}

/// The kinds of thing the app layer refuses.
///
/// A refusal is a closed set — "you asked to send with no Session open" — so it
/// is *named* here rather than written out as a sentence. That is what lets the
/// reason reach a screen in the user's language: `lib/app` may not import
/// Flutter (see `app.dart`), so it cannot translate anything itself, and a name
/// is the only kind of answer the UI can act on.
enum AppRefusal {
  /// A Session was asked for with a peer already wired up.
  sessionAlreadyOpen,

  /// A peer was dialled that Discovery has never placed.
  peerAddressUnknown,

  /// An address was dialled with nothing in the address field.
  noAddressGiven,

  /// A port outside `1..65535`.
  portNotAPort,

  /// An offer that has already been accepted or refused.
  offerAlreadyAnswered,

  /// A send was attempted with nothing connected.
  noPeerConnected,

  /// A send named a peer with no Session to it.
  noSessionOpen,

  /// A send named no peer while several were connected.
  severalPeersConnected,

  /// Something that needs the Session layer was asked for before pairing.
  notPaired,

  /// Every candidate name in the destination folder is taken.
  noFreeFileName,
}

/// Raised when the app layer is asked for something its current state does not
/// allow — sending with no Session, dialling a peer whose address is unknown.
///
/// Distinct from the core layers' exceptions on purpose: those say what the
/// protocol did, this says what the *caller* asked for and did not get.
///
/// [detail] carries the data the refusal is about and never prose: a
/// Fingerprint, a port number, a file name. Making the sentence belongs to the
/// UI, which is the only layer that knows what language the user reads.
final class AppStateException implements Exception {
  const AppStateException(this.refusal, [this.detail]);

  /// What was refused.
  final AppRefusal refusal;

  /// What it was refused about, when the refusal names something.
  final String? detail;

  @override
  String toString() => detail == null
      ? 'AppStateException: $refusal'
      : 'AppStateException: $refusal ($detail)';
}

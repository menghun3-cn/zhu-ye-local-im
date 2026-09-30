import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'l10n/generated/app_localizations.dart';

/// How the application's words and pictures are chosen.
///
/// Every function here is a pure mapping from a fact in `lib/core` to
/// something a screen shows, deliberately kept out of the widgets: a page that
/// wrote its own switch for [TransferState] would be a second place to change
/// when a state is added, and would drift.
///
/// The pictures come from Material and the words from [AppLocalizations], and
/// the split is the same either way — a fact in, something to draw out.
/// Nothing here is a widget, so nothing here takes a `BuildContext`: the caller
/// looks the strings up once and hands them in, which is also what keeps a
/// sentence from being assembled in two places.

/// The icon for a Payload's kind.
IconData iconForKind(PayloadKind kind) => switch (kind) {
  PayloadKind.text => Icons.notes,
  PayloadKind.file => Icons.description_outlined,
  PayloadKind.clipboard => Icons.content_paste,
};

/// A short name for a Payload's kind.
String labelForKind(PayloadKind kind, AppLocalizations l10n) => switch (kind) {
  PayloadKind.text => l10n.kindText,
  PayloadKind.file => l10n.kindFiles,
  PayloadKind.clipboard => l10n.kindClipboard,
};

/// Where a Transfer has got to, in a word.
String labelForState(TransferState state, AppLocalizations l10n) =>
    switch (state) {
      TransferState.awaitingDecision => l10n.stateAwaitingDecision,
      TransferState.transferring => l10n.stateTransferring,
      TransferState.verifying => l10n.stateVerifying,
      TransferState.completed => l10n.stateCompleted,
      TransferState.rejected => l10n.stateRejected,
      TransferState.cancelled => l10n.stateCancelled,
      TransferState.failed => l10n.stateFailed,
    };

/// The icon for a Transfer's state.
IconData iconForState(TransferState state) => switch (state) {
  TransferState.awaitingDecision => Icons.help_outline,
  TransferState.transferring => Icons.sync,
  TransferState.verifying => Icons.rule,
  TransferState.completed => Icons.check_circle_outline,
  TransferState.rejected => Icons.block,
  TransferState.cancelled => Icons.cancel_outlined,
  TransferState.failed => Icons.error_outline,
};

/// The icon for a Device's platform.
///
/// [DevicePlatform.other] is drawn as a question mark rather than as one of the
/// two the product supports, because that is what it means: a Device whose
/// clipboard behaviour this version cannot promise anything about.
IconData iconForPlatform(DevicePlatform? platform) => switch (platform) {
  DevicePlatform.windows => Icons.desktop_windows_outlined,
  DevicePlatform.android => Icons.smartphone_outlined,
  DevicePlatform.other || null => Icons.devices_other_outlined,
};

/// How a peer's location reads, or why it has none.
///
/// A peer this Device holds a Session with reads as its address even when it
/// advertises no Session port: the connection is the stronger fact, and a line
/// saying "not accepting connections" beside a peer that is demonstrably
/// connected would contradict itself.
String describePeerAddress(PeerView peer, AppLocalizations l10n) {
  final address = peer.address;
  if (address == null) return l10n.neverSeen;
  final port = peer.sessionPort;
  if (port == null) {
    return peer.isConnected ? address : l10n.peerNotAccepting(address);
  }
  return '$address:$port';
}

/// Everything known about a peer, as one line under its name.
///
/// Assembled here rather than in the card that shows it: the list is a reading
/// of [PeerView], and turning that reading into words is what this file is for.
///
/// Two rules keep the line from contradicting itself. The "last seen" clause is
/// only added when there is an address to pair it with — without one it would
/// read "never seen · last seen never", the same fact said twice and the second
/// time as a contradiction. And a connected peer is never described as unseen:
/// its address is normally known, since the Session was opened to it, but it is
/// read off the transport and one that reports none would otherwise put "never
/// seen" on a Device this one is talking to right now.
String describePeerFacts(PeerView peer, AppLocalizations l10n) {
  final connected = peer.isConnected;
  final facts = <String>[
    if (peer.alias == null) l10n.peerNameNotAnnounced,
    if (peer.address != null)
      describePeerAddress(peer, l10n)
    else if (!connected)
      l10n.neverSeen,
    if (connected)
      l10n.sessionOpen
    else if (peer.address != null)
      l10n.lastSeen(describeLastSeen(peer.lastSeen, l10n)),
    if (!peer.isInGroup) l10n.notInOwnerGroup,
    if (peer.isFavorite) l10n.trusted,
  ];
  return facts.join(' · ');
}

/// When something was last heard from, as a person reads it.
String describeLastSeen(DateTime? when, AppLocalizations l10n) {
  if (when == null) return l10n.timeNever;
  final elapsed = DateTime.now().toUtc().difference(when.toUtc());
  if (elapsed.isNegative || elapsed.inSeconds < 30) return l10n.timeJustNow;
  if (elapsed.inMinutes < 2) return l10n.timeAMinuteAgo;
  if (elapsed.inHours < 1) return l10n.timeMinutesAgo(elapsed.inMinutes);
  if (elapsed.inHours < 2) return l10n.timeAnHourAgo;
  if (elapsed.inDays < 1) return l10n.timeHoursAgo(elapsed.inHours);
  if (elapsed.inDays < 2) return l10n.timeYesterday;
  return l10n.timeDaysAgo(elapsed.inDays);
}

/// What this Device can do with a clipboard, as a pair of facts.
String describeClipboardFacts(
  ClipboardCapability capability,
  AppLocalizations l10n,
) {
  final yes = l10n.yes;
  final no = l10n.no;
  return [
    l10n.clipboardCanOriginate(capability.canOriginate ? yes : no),
    l10n.clipboardCanApply(capability.canApply ? yes : no),
  ].join(' · ');
}

/// The label for how the clipboard is being treated.
String labelForClipboardMode(ClipboardMode mode, AppLocalizations l10n) =>
    switch (mode) {
      ClipboardMode.off => l10n.clipboardModeOff,
      ClipboardMode.stage => l10n.clipboardModeStage,
      ClipboardMode.mirror => l10n.clipboardModeMirror,
    };

/// What each clipboard mode means, in one line.
String describeClipboardMode(ClipboardMode mode, AppLocalizations l10n) =>
    switch (mode) {
      ClipboardMode.off => l10n.clipboardModeOffMeans,
      ClipboardMode.stage => l10n.clipboardModeStageMeans,
      ClipboardMode.mirror => l10n.clipboardModeMirrorMeans,
    };

/// A refusal from the app layer, as a sentence the user reads.
///
/// The reason travels up as an [AppRefusal] rather than as text — see its doc —
/// so this is where the two halves meet: the name says which sentence, and
/// [detail] is the Fingerprint or number that goes in it.
String describeRefusal(
  AppRefusal refusal,
  String? detail,
  AppLocalizations l10n,
) {
  final subject = detail ?? '';
  return switch (refusal) {
    AppRefusal.sessionAlreadyOpen => l10n.refusalSessionAlreadyOpen(subject),
    AppRefusal.peerAddressUnknown => l10n.refusalPeerAddressUnknown(subject),
    AppRefusal.noAddressGiven => l10n.refusalNoAddressGiven,
    AppRefusal.portNotAPort => l10n.refusalPortNotAPort(subject),
    AppRefusal.offerAlreadyAnswered => l10n.refusalOfferAlreadyAnswered,
    AppRefusal.noPeerConnected => l10n.refusalNoPeerConnected,
    AppRefusal.noSessionOpen => l10n.refusalNoSessionOpen(subject),
    AppRefusal.severalPeersConnected => l10n.refusalSeveralPeersConnected,
    AppRefusal.notPaired => l10n.refusalNotPaired,
    AppRefusal.noFreeFileName => l10n.refusalNoFreeFileName(subject),
  };
}

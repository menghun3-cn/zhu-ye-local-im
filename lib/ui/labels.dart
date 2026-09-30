import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';

/// How the application's words and pictures are chosen.
///
/// Every function here is a pure mapping from a fact in `lib/core` to
/// something a screen shows, deliberately kept out of the widgets: a page that
/// wrote its own switch for [TransferState] would be a second place to change
/// when a state is added, and would drift.

/// The icon for a Payload's kind.
IconData iconForKind(PayloadKind kind) => switch (kind) {
  PayloadKind.text => Icons.notes,
  PayloadKind.file => Icons.description_outlined,
  PayloadKind.clipboard => Icons.content_paste,
};

/// A short name for a Payload's kind.
String labelForKind(PayloadKind kind) => switch (kind) {
  PayloadKind.text => 'Text',
  PayloadKind.file => 'Files',
  PayloadKind.clipboard => 'Clipboard',
};

/// Where a Transfer has got to, in a word.
String labelForState(TransferState state) => switch (state) {
  TransferState.awaitingDecision => 'Waiting for an answer',
  TransferState.transferring => 'Transferring',
  TransferState.verifying => 'Checking',
  TransferState.completed => 'Done',
  TransferState.rejected => 'Refused',
  TransferState.cancelled => 'Cancelled',
  TransferState.failed => 'Failed',
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
String describePeerAddress(PeerView peer) {
  final address = peer.address;
  if (address == null) return 'Never seen';
  final port = peer.sessionPort;
  if (port == null) return '$address, not accepting Sessions';
  return '$address:$port';
}

/// When something was last heard from, as a person reads it.
String describeLastSeen(DateTime? when) {
  if (when == null) return 'never';
  final elapsed = DateTime.now().toUtc().difference(when.toUtc());
  if (elapsed.isNegative || elapsed.inSeconds < 30) return 'just now';
  if (elapsed.inMinutes < 2) return 'a minute ago';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} minutes ago';
  if (elapsed.inHours < 2) return 'an hour ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} hours ago';
  if (elapsed.inDays < 2) return 'yesterday';
  return '${elapsed.inDays} days ago';
}

/// The label for how the clipboard is being treated.
String labelForClipboardMode(ClipboardMode mode) => switch (mode) {
  ClipboardMode.off => 'Off',
  ClipboardMode.stage => 'Ask me',
  ClipboardMode.mirror => 'Mirror',
};

/// What each clipboard mode means, in one line.
String describeClipboardMode(ClipboardMode mode) => switch (mode) {
  ClipboardMode.off => 'Nothing is captured, and nothing arrives.',
  ClipboardMode.stage =>
    'A copy here travels to the group. Incoming copies wait for you.',
  ClipboardMode.mirror =>
    'A copy here travels to the group, and incoming copies replace this '
        'clipboard on their own.',
};

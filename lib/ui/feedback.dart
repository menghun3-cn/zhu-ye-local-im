import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';

/// Runs something the app layer is allowed to refuse, and says so where the
/// user is looking.
///
/// Every call that can throw [AppStateException] — dialling a Device with no
/// address, sending with no Session — is a call a user made from a button, so
/// the refusal belongs on screen as a word rather than in an unhandled
/// exception. The messenger and the strings are taken before the await, because
/// the widget that started the call may be gone by the time it answers.
Future<void> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    await action();
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeFailure(error, l10n))),
    );
  }
}

/// A failure as a sentence.
///
/// Two kinds of exception arrive here and they are treated differently, on
/// purpose. The app layer's own refusals are a closed set of things a user
/// asked for and could not have, so they are named rather than worded (see
/// [AppRefusal]) and become a full sentence in the user's language. The core
/// layers' failures carry a `message` that says what the protocol did —
/// "cannot reach 192.168.1.9:47811", a `SocketException`'s own text — and that
/// detail is kept verbatim: it is a fact about the network, not prose this
/// application wrote, and translating it would make it harder to act on rather
/// than easier.
///
/// The one core failure that gets more than its own detail is a dial that never
/// landed. Its cause is almost always outside this application — the other
/// Device is not running, is on another network, or is behind a firewall — so
/// the sentence names what to check instead of leaving the user with the
/// operating system's word for it. That is why [PairingException] carries
/// `unreachable` rather than making this function read tea leaves out of the
/// message.
String describeFailure(Object error, AppLocalizations l10n) => switch (error) {
  AppStateException(:final refusal, :final detail) => describeRefusal(
    refusal,
    detail,
    l10n,
  ),
  HandshakeException(:final message) => l10n.failureUnreachable(message),
  PairingException(:final message, unreachable: true) =>
    l10n.failureCannotReach(message),
  PairingException(:final message) => l10n.failurePairing(message),
  _ => '$error',
};

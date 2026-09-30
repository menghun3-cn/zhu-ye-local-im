import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';

/// Runs something the app layer is allowed to refuse, and says so where the
/// user is looking.
///
/// Every call that can throw [AppStateException] — dialling a Device with no
/// address, sending with no Session — is a call a user made from a button, so
/// the refusal belongs on screen as a word rather than in an unhandled
/// exception. The messenger is taken before the await, because the widget that
/// started the call may be gone by the time it answers.
Future<void> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(describeFailure(error))));
  }
}

/// A failure as a sentence.
///
/// The three exceptions the layers below raise deliberately carry a readable
/// `message` — the field's own doc says it is for the UI — so they are lifted
/// out of their `toString` rather than shown as a type name.
String describeFailure(Object error) => switch (error) {
  AppStateException(:final message) => message,
  HandshakeException(:final message) => 'Could not reach the Device: $message',
  PairingException(:final message) => 'Pairing failed: $message',
  _ => '$error',
};

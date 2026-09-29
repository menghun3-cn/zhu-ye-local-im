/// The parts of the product that do not depend on Flutter.
///
/// Everything under `lib/core` is plain Dart: it is what makes the protocol,
/// the identity model, discovery, transfer and the clipboard policy testable
/// without a widget tree, and what lets the same logic run in a headless
/// acceptance harness as in the app.
library;

export 'clipboard/clipboard_capability.dart';
export 'identity/device_descriptor.dart';
export 'identity/fingerprint.dart';
export 'identity/pairing_secret.dart';
export 'protocol/frame.dart';
export 'protocol/messages.dart';
export 'security/hkdf.dart';
export 'security/secure_link.dart';
export 'transport/byte_transport.dart';
export 'util/crockford_base32.dart';

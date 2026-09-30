/// The parts of the product that do not depend on Flutter.
///
/// Everything under `lib/core` is plain Dart: it is what makes the protocol,
/// the identity model, discovery, transfer and the clipboard policy testable
/// without a widget tree, and what lets the same logic run in a headless
/// acceptance harness as in the app.
library;

export 'clipboard/clipboard_capability.dart';
export 'clipboard/clipboard_channel.dart';
export 'clipboard/clipboard_entry.dart';
export 'clipboard/clipboard_mirror.dart';
export 'clipboard/system_clipboard.dart';
export 'discovery/beacon.dart';
export 'discovery/beacon_transport.dart';
export 'discovery/discovery_service.dart';
export 'discovery/peer_registry.dart';
export 'discovery/udp_beacon_transport.dart';
export 'identity/device_descriptor.dart';
export 'identity/fingerprint.dart';
export 'identity/owner_group.dart';
export 'identity/owner_identity.dart';
export 'identity/pairing_secret.dart';
export 'profile/device_profile.dart';
export 'profile/profile_store.dart';
export 'protocol/frame.dart';
export 'protocol/messages.dart';
export 'security/hkdf.dart';
export 'security/secure_link.dart';
export 'session/session_hub.dart';
export 'transfer/byte_source.dart';
export 'transfer/incoming_transfer.dart';
export 'transfer/outgoing_transfer.dart';
export 'transfer/payload_sink.dart';
export 'transfer/running_digest.dart';
export 'transfer/transfer.dart';
export 'transfer/transfer_channel.dart';
export 'transfer/transfer_engine.dart';
export 'transfer/transfer_limits.dart';
export 'transport/byte_transport.dart';
export 'util/crockford_base32.dart';

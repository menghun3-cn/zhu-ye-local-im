import '../protocol/messages.dart';

/// The slice of an established Session that Clipboard Mirroring needs.
///
/// Clipboard entries are a conversation of their own, separate from Transfers:
/// they are fire-and-forget, they carry no accept/verify round trip, and they
/// are only exchanged inside an Owner Group. Keeping them behind this seam is
/// what lets the mirror be driven without a socket, and what lets a test hand
/// it exactly the entries a hostile Device would have sent.
abstract interface class ClipboardChannel {
  /// Entries pushed by the peer. Single-subscription.
  Stream<ClipboardMessage> get entries;

  /// Pushes an entry to the peer.
  Future<void> send(ClipboardMessage message);
}

import 'dart:async';
import 'dart:convert';

import 'package:local_transfer/core/core.dart';

/// A Device descriptor with a predictable fingerprint, for tests.
DeviceDescriptor testDevice(
  String label, {
  DevicePlatform platform = DevicePlatform.windows,
  String? alias,
  int? listenPort,
}) {
  return DeviceDescriptor(
    fingerprint: Fingerprint.ofPublicKey(utf8.encode(label)),
    alias: alias ?? label,
    platform: platform,
    capability: ClipboardCapability.forPlatform(platform),
    listenPort: listenPort,
  );
}

/// Waits until [condition] holds, or fails the test by throwing.
///
/// Streams in this codebase deliver on the event loop, so assertions about
/// what a peer received have to yield rather than sleep a fixed amount.
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('$description was still false after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Collects every message a link delivers, so a test can assert on the whole
/// sequence rather than racing a single `first`.
final class MessageLog {
  MessageLog(SecureLink link, {bool listenToChunks = false}) {
    link.messages.listen(
      messages.add,
      onError: (Object error) => errors.add(error),
    );
    if (listenToChunks) {
      link.chunks.listen(
        chunks.add,
        onError: (Object error) => errors.add(error),
      );
    }
  }

  /// Messages received so far, in arrival order.
  final List<WireMessage> messages = [];

  /// Chunk frames received so far, in arrival order.
  final List<ChunkFrame> chunks = [];

  /// Errors the link reported, in arrival order.
  final List<Object> errors = [];

  /// The first message of type [T], or null if none has arrived.
  T? firstOf<T extends WireMessage>() {
    for (final message in messages) {
      if (message is T) return message;
    }
    return null;
  }
}

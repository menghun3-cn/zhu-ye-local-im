import 'dart:async';
import 'dart:math';

import 'package:local_transfer/core/core.dart';

/// A [ClipboardChannel] a test drives by hand.
///
/// Stands in for a peer, so a test can push in exactly the entries a broken or
/// hostile Device would have sent and read back everything this side mirrored
/// without a socket in the way.
final class FakeClipboardChannel implements ClipboardChannel {
  final StreamController<ClipboardMessage> _entries =
      StreamController<ClipboardMessage>();

  /// Entries this side has pushed.
  final List<ClipboardMessage> sent = [];

  /// Delivered to the mirror as if the peer had sent it.
  void deliver(ClipboardMessage message) => _entries.add(message);

  /// Closes the peer's side, as a dead Session would.
  Future<void> close() => _entries.close();

  @override
  Stream<ClipboardMessage> get entries => _entries.stream;

  @override
  Future<void> send(ClipboardMessage message) async {
    sent.add(message);
  }
}

/// An entry a peer might have captured, for a test to deliver by hand.
ClipboardEntry testEntry(
  DeviceDescriptor device,
  String text, {
  String? id,
  DateTime? at,
}) => ClipboardEntry(
  entryId: id ?? 'e-${text.hashCode}',
  origin: device.fingerprint,
  text: text,
  capturedAt: at ?? DateTime.utc(2026, 9, 29, 12),
);

/// A mirror plus the two things a test needs to observe it: the clipboard it
/// writes to and the notices it produced.
final class MirrorFixture {
  MirrorFixture({
    required OwnerGroup group,
    ClipboardCapability? capability,
    ClipboardMode mode = ClipboardMode.mirror,
    DateTime Function()? clock,
    Set<Fingerprint> allowedPeers = const {},
    bool allowEveryoneInGroup = false,
  }) : clipboard = MemorySystemClipboard() {
    mirror = ClipboardMirror(
      group: group,
      // The sharing whitelist. A fixture that asks for
      // `allowEveryoneInGroup` is one testing the *other* gates — the Owner
      // Group, the capability, the origin tag — and would otherwise have to
      // restate the same seed in every call. A fixture that names peers
      // explicitly is one testing the whitelist itself.
      allowedPeers: allowEveryoneInGroup ? group.members.toSet() : allowedPeers,
      capability:
          capability ?? ClipboardCapability.forPlatform(DevicePlatform.windows),
      clipboard: clipboard,
      mode: mode,
      clock: clock,
      random: _SeededRandom(),
      onNotice: notices.add,
    );
  }

  final MemorySystemClipboard clipboard;
  late final ClipboardMirror mirror;

  /// Lines the mirror refused or dropped something with.
  final List<String> notices = [];

  /// Attaches [channel] as [device]'s clipboard conversation.
  void attach(DeviceDescriptor device, FakeClipboardChannel channel) =>
      mirror.attachPeer(fingerprint: device.fingerprint, channel: channel);

  Future<void> close() async {
    await mirror.close();
    await clipboard.close();
  }
}

/// Waits long enough for every already-queued stream event to be delivered.
///
/// Used for the assertions that expect *nothing* to happen: there is no event
/// to wait for, so the test has to yield instead. A negative assertion that
/// can be made positive-first should be, and the two places this is used are
/// the ones where it cannot.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 25));

/// A deterministic byte source, so entry ids are stable across a run.
final class _SeededRandom implements Random {
  int _next = 1;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1000) / 1000;

  @override
  int nextInt(int max) {
    _next = (_next * 1103515245 + 12345) & 0x7fffffff;
    return _next % max;
  }
}

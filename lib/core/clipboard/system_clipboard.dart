import 'dart:async';

/// The system clipboard of whatever Device this is running on.
///
/// Nothing above this seam knows whether the clipboard is a Windows message
/// window, an Android `ClipboardManager`, or a map in memory. That is the
/// point: the capture policy, the echo suppression and the Owner gate are all
/// testable without a platform.
///
/// The three members are separate rather than one `watch()` because the
/// platforms disagree about all three. Windows can read, write and listen in
/// the background; Android can write in the background but may only read while
/// its window is focused; and a platform that can do none of them is still
/// expected to honour a [write] so that applying a Mirror degrades to "nothing
/// happened" rather than an exception. What a Device actually promises is
/// declared by `ClipboardCapability`, which travels in its handshake.
abstract interface class SystemClipboard {
  /// The clipboard's current text.
  ///
  /// Null when it holds nothing textual — an image, a file list, nothing at
  /// all — or when this platform cannot read it right now.
  Future<String?> read();

  /// Replaces the clipboard with [text].
  Future<void> write(String text);

  /// Fires on every change to the clipboard, with the new text.
  ///
  /// Single-subscription: one watcher owns the platform notification. A
  /// platform that cannot watch in the background simply never fires.
  Stream<String> get changes;
}

/// A [SystemClipboard] held in memory, for tests and for a headless harness.
///
/// [copy] stands in for a person copying something, and [write] stands in for
/// Mirroring applying an entry — the distinction matters, because the whole
/// echo-suppression problem is telling those two apart.
final class MemorySystemClipboard implements SystemClipboard {
  // Broadcast rather than single-subscription: a real platform watcher drops a
  // change that happens while nobody is listening — there is no clipboard
  // manager holding it. A buffering controller would instead replay every copy
  // made while Mirroring was off the moment it was switched back on, which is
  // a bug this seam must not hide.
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  String? _text;

  /// Every value Mirroring has written, in order.
  ///
  /// Kept separately from [history] so a test can assert on what was applied
  /// without wading through what was merely copied.
  final List<String> applied = [];

  /// Every value that has reached the clipboard, in order.
  final List<String> history = [];

  /// Simulates a person copying [text].
  ///
  /// Unlike [write] this is the event Mirroring is meant to capture, so it
  /// fires [changes] exactly as a platform would.
  void copy(String text) {
    _text = text;
    history.add(text);
    if (!_changes.isClosed) _changes.add(text);
  }

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async {
    _text = text;
    applied.add(text);
    history.add(text);
    // A real platform usually reports its own writes back as a change; the
    // mirror has to survive that, so this seam does not hide it.
    if (!_changes.isClosed) _changes.add(text);
  }

  @override
  Stream<String> get changes => _changes.stream;

  /// Stops the change stream, as shutting the platform layer down would.
  Future<void> close() async {
    if (!_changes.isClosed) await _changes.close();
  }
}

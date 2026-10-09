import 'dart:io';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

/// What the composer can lift out of the system clipboard.
///
/// Flutter's own `Clipboard` reads and writes *text* on every platform and
/// nothing else, so a screenshot or a file copied in Explorer is invisible to
/// it. This is the seam over the plugin that can see them.
///
/// A class rather than two bare calls for the same reason the picker is one: a
/// platform channel cannot answer inside a `testWidgets` body — there is no
/// engine behind it — so a test needs somewhere to put a stand-in. See
/// [PasteResolution].
abstract interface class ClipboardPaste {
  /// The files the clipboard is holding, as paths. Empty when it holds none.
  Future<List<String>> files();

  /// The image the clipboard is holding, as encoded bytes, or null when it is
  /// holding no picture.
  ///
  /// Encoded, not decoded: what the bytes *are* is decided by the bytes, and
  /// that is `imageExtensionOf`'s job, not this one's.
  Future<Uint8List?> image();

  /// Replaces the clipboard with the picture encoded in [bytes], and answers
  /// whether it managed to.
  ///
  /// The same plugin, the other direction — and the direction the platforms
  /// disagree about most. A `bool` rather than a thrown failure because a
  /// clipboard this platform will not let the app write is an ordinary
  /// condition and not an error: Android denies the write while the app is in
  /// the background, and a platform the plugin has no implementation for
  /// answers nothing at all. Both have to reach the user as "it did not
  /// happen" rather than as a stack trace or, worse, as silence.
  Future<bool> writeImage(Uint8List bytes);
}

/// The real clipboard, through the platform plugin.
final class SystemClipboardPaste implements ClipboardPaste {
  /// Reads the desktop clipboard.
  const SystemClipboardPaste();

  @override
  Future<List<String>> files() async {
    // A clipboard that will not answer is the same thing as an empty one here:
    // nothing to send, and the composer falls through to pasting text. Which
    // platform refuses — Android without focus, a desktop that never registered
    // the channel — is not something the user can act on.
    try {
      return await Pasteboard.files();
    } on Object {
      return const [];
    }
  }

  @override
  Future<Uint8List?> image() async {
    try {
      return await Pasteboard.image;
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> writeImage(Uint8List bytes) async {
    // The platforms this app ships to, and no others. On Windows the plugin
    // writes the bytes to a scratch file and lets GDI+ decode it — verified
    // for a name with no extension, which is what it uses — and sets the
    // result as `CF_BITMAP`; on the others the channel call does the same job
    // natively. A platform outside the four falls through the plugin as a
    // silent no-op, and a no-op that reports success would put "copied" on
    // screen for a clipboard nothing happened to.
    final supported =
        Platform.isWindows ||
        Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS;
    if (!supported) return false;
    try {
      await Pasteboard.writeImage(bytes);
      return true;
    } on Object {
      return false;
    }
  }
}

/// Which clipboard reads the composer's paste.
///
/// The substitution point, exactly as [PickerResolution] is for the picker: a
/// test installs a stand-in, drives the real Ctrl+V, and clears it in a
/// `tearDown`. Production never assigns it.
abstract final class PasteResolution {
  /// The reader in force. Set by a test; never by the application.
  static ClipboardPaste paste = const SystemClipboardPaste();

  /// Restores [SystemClipboardPaste]. Called from a `tearDown`.
  static void reset() => paste = const SystemClipboardPaste();
}

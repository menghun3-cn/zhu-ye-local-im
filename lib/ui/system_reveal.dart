import 'dart:io';

import 'android_files.dart';
import 'reveal.dart';

/// The real revealer: the platform's own shell.
///
/// The application ships no launcher plugin — that is a *native* registration
/// bought for one call — so the platform's own shell is asked instead, the
/// same way `external_links.dart` asks it to open a web address. Windows goes
/// to `explorer`; Android goes through the runner's own channel, which asks a
/// file manager through a `content://` URI — the only kind of address another
/// application may be handed. A folder inside the app's private storage is
/// one no file manager can browse, so Android's false is an ordinary answer,
/// not a failure; anywhere else this answers false too, and the caller says
/// so rather than leaving a menu item that does nothing.
///
/// This lives beside `FileOpener` (`open_file.dart`) rather than in
/// `reveal.dart` because the
/// Android half needs the platform channel, and `reveal.dart` has to stay
/// loadable by `dart test` — see the note at the top of that file.
final class SystemRevealer implements Revealer {
  const SystemRevealer();

  @override
  Future<bool> reveal(String path) async {
    final folder = folderOf(path);
    if (folder == null) return false;
    if (Platform.isWindows) {
      try {
        // The shell, not a themed window: this hands over to the same
        // Explorer the user already has open, which is the whole point of
        // showing them where the file went.
        await Process.run('explorer', [explorerArgument(folder)]);
        return true;
      } on Object {
        return false;
      }
    }
    if (Platform.isAndroid) return openAndroidFolder(folder);
    return false;
  }
}

/// Which revealer the surfaces use.
///
/// A single mutable field rather than a parameter threaded through the widget
/// tree, for the same reason the composer's `PickerResolution` is one: the
/// action is offered by more than one surface, and a test-only argument on all
/// of them would put the seam in the application's vocabulary.
abstract final class RevealResolution {
  /// The revealer in force. Set by a test; never by the application.
  static Revealer revealer = const SystemRevealer();

  /// Restores [SystemRevealer]. Called from a `tearDown`.
  static void reset() => revealer = const SystemRevealer();
}

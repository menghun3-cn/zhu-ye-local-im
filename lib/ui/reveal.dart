import 'dart:io';

/// The file manager this Device opens a file's folder with.
///
/// A class rather than a bare function for the same reason the composer's
/// `FilePicker` is one: opening the folder hands over to the operating system's
/// shell, which runs outside Flutter's event loop. A widget test that drove the
/// real thing would launch an Explorer window on the machine running the suite —
/// a side effect with no bearing on what the test asserts. `RevealResolution` is
/// the substitution point: production leaves the field alone and gets
/// [SystemRevealer], and a test sets it, drives the flow through a stand-in, and
/// clears it again in a `tearDown`.
abstract interface class Revealer {
  /// Shows [path] to the user in this machine's file manager, and answers
  /// whether it managed to.
  Future<bool> reveal(String path);
}

/// The real revealer: the platform's own shell.
///
/// The application ships no launcher plugin — that is a *native* registration
/// bought for one call — so the platform's own shell is asked instead, the same
/// way `external_links.dart` asks it to open a web address. Windows only, and
/// for the same reason it is Windows only there: `explorer` is that platform's
/// file manager, and the two platforms this build is aimed at are Windows and an
/// unverified Android. Anywhere else this answers false and the caller says so
/// rather than leaving a menu item that does nothing.
final class SystemRevealer implements Revealer {
  const SystemRevealer();

  @override
  Future<bool> reveal(String path) async {
    if (!Platform.isWindows) return false;
    final folder = folderOf(path);
    if (folder == null) return false;
    try {
      // The shell, not a themed window: this hands over to the same Explorer the
      // user already has open, which is the whole point of showing them where
      // the file went.
      await Process.run('explorer', [explorerArgument(folder)]);
      return true;
    } on Object {
      return false;
    }
  }
}

/// The one argument [folder] becomes on `explorer`'s command line.
///
/// **Explorer reads every `/` in an argument as one of its own switches.**
/// `/e`, `/select` and `/root` are the ones it documents, and it resolves the
/// argument first and the switches after: `C:/Users/me/Downloads` is read as the
/// drive `C:` followed by two switches nobody sent, no path token is left, and
/// Explorer opens its *fallback* folder — the user's Documents — without saying
/// so. Only `/` is affected; `\` is what it expects, and it is also what a path
/// typed into Explorer's own address bar arrives as.
///
/// That rule would not matter if the folder were always spelled with `\`, but it
/// is not: the folder this app fills in by default is built with `/`, because
/// paths in this project are joined the same way on every platform (see
/// `defaultIncomingDirectory`, which has to answer for Android with the same
/// function). So the conversion belongs here, at the one place a path stops
/// being a Dart string and becomes an argument to somebody else's parser — and
/// it covers a folder the user typed with `/` into the accept dialog as well,
/// which no amount of care in the path builders would have.
///
/// Only the argument is converted. The folder itself goes on being the string
/// the rest of the app uses, because `\` is not a fact about the folder, it is a
/// fact about Explorer.
String explorerArgument(String folder) => folder.replaceAll('/', r'\');

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

/// The folder [path] names a file inside, or null when it names no folder.
///
/// **The folder is opened, not the file.** `explorer` can be asked to highlight
/// one file with its `/select,` switch, but that switch carries its argument in
/// the same token — `/select,C:\a b\c.png` — and any launcher that sees a space
/// in an argument quotes the whole of it, which breaks the pairing. A path with
/// a space in it is the ordinary case on Windows, so the reliable half is taken:
/// the folder opens, and the file is in it. "Where is this" is answered either
/// way, and it is answered the same way for every path. What the folder then has
/// to look like before `explorer` will accept it is [explorerArgument]'s
/// business, and it is the other half of the same parser.
///
/// A bare name — `photo.png`, with no directory part at all — resolves to `.`,
/// which is this process's working directory rather than anything the user
/// chose. Opening that would be opening a folder nobody asked about, so it
/// answers null and the caller reports that it could not.
String? folderOf(String path) {
  if (path.isEmpty) return null;
  final parent = File(path).parent.path;
  if (parent.isEmpty || parent == '.' || parent == path) return null;
  return parent;
}

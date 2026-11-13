import 'dart:io';

import 'android_files.dart';
import 'reveal.dart';

/// The application this Device opens a received file with.
///
/// A class rather than a bare function, for the same reason [Revealer] is
/// one: opening a file hands over to the operating system's shell — an
/// Explorer window here, somebody else's activity on Android — which runs
/// outside Flutter's event loop. A widget test that drove the real thing
/// would open a document on the machine running the suite, a side effect
/// with no bearing on what the test asserts. [OpenResolution] is the
/// substitution point: production leaves the field alone and gets
/// [SystemFileOpener], and a test sets it, drives the flow through a
/// stand-in, and clears it again in a `tearDown`.
abstract interface class FileOpener {
  /// Opens [path] with this machine's default handler for its type, and
  /// answers whether it managed to.
  Future<bool> open(String path);
}

/// The real opener: the platform's own "open with".
///
/// Windows goes through `explorer`, the same shell `SystemRevealer` asks —
/// with the same argument conversion, because Explorer reads a `/` in an
/// argument as one of its own switches and a received path is `/`-joined on
/// every platform. Android goes through the runner's own channel, which hands
/// the file to the system as a `content://` URI — a `file://` path is one
/// Android will not let another application open. Anywhere else this answers
/// false and the caller says so rather than leaving a bubble that does
/// nothing.
final class SystemFileOpener implements FileOpener {
  const SystemFileOpener();

  @override
  Future<bool> open(String path) async {
    if (path.isEmpty || !File(path).existsSync()) return false;
    if (Platform.isWindows) {
      try {
        await Process.run('explorer', [explorerArgument(path)]);
        return true;
      } on Object {
        return false;
      }
    }
    if (Platform.isAndroid) return openAndroidFile(path);
    return false;
  }
}

/// Which opener the surfaces use.
///
/// A single mutable field rather than a parameter threaded through the widget
/// tree, for the same reason `RevealResolution` is one: the action is offered
/// by more than one surface, and a test-only argument on all of them would
/// put the seam in the application's vocabulary.
abstract final class OpenResolution {
  /// The opener in force. Set by a test; never by the application.
  static FileOpener opener = const SystemFileOpener();

  /// Restores [SystemFileOpener]. Called from a `tearDown`.
  static void reset() => opener = const SystemFileOpener();
}

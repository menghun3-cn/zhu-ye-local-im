import 'dart:io';

/// Opens a web page in whatever browser the machine has, and says whether it
/// managed to.
///
/// The application ships no launcher plugin — `url_launcher` is a *native*
/// registration bought for one call — so the platform's own shell is asked
/// instead. Windows only: `cmd /c start` is that platform's "open this with its
/// default handler", and the two platforms this build is aimed at are Windows
/// and an unverified Android. Anywhere else this answers false, and the caller
/// leaves the address on screen to be copied by hand.
///
/// [url] is checked before it goes anywhere near a shell, and only https links
/// to github.com pass. The address normally comes out of a GitHub response, but
/// a shell is a shell: the check is what keeps a crafted one from being read as
/// further commands.
Future<bool> openInBrowser(String url) async {
  if (!isOpenableLink(url) || !Platform.isWindows) return false;
  try {
    // The empty argument is the window title `start` expects before whatever it
    // is being asked to open; without it a quoted address would be taken as the
    // title and nothing would open.
    await Process.run('cmd', ['/c', 'start', '', url]);
    return true;
  } on Object {
    return false;
  }
}

/// Whether [url] is an https address on github.com, and so safe to hand to a
/// shell.
bool isOpenableLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host;
  return host == 'github.com' || host.endsWith('.github.com');
}

/// The browser this Device opens a web address with.
///
/// A class rather than a bare function, and for the same reason `Revealer` is
/// one: opening a page hands over to the operating system's shell, which runs
/// outside Flutter's event loop. A widget test that drove the real thing would
/// launch a browser window on the machine running the suite — a side effect
/// with no bearing on what the test asserts, and one that hangs rather than
/// fails, because the shell it starts never returns to the test body.
/// [LinkResolution] is the substitution point: production leaves the field
/// alone and gets [SystemLinkOpener], and a test sets it, drives the press
/// through a stand-in, and clears it again in a `tearDown`.
abstract interface class LinkOpener {
  /// Shows [url] to the user in this machine's browser, and answers whether it
  /// managed to.
  Future<bool> open(String url);
}

/// The real opener: the platform's own shell, by way of [openInBrowser].
final class SystemLinkOpener implements LinkOpener {
  /// Opens through the shell.
  const SystemLinkOpener();

  @override
  Future<bool> open(String url) => openInBrowser(url);
}

/// Which opener the surfaces use.
///
/// A single mutable field rather than a parameter threaded through the widget
/// tree, for the same reason `RevealResolution` is one: a download link is
/// offered by more than one surface — the About card and the rail's update
/// entry — and a test-only argument on both would put the seam in the
/// application's vocabulary.
abstract final class LinkResolution {
  /// The opener in force. Set by a test; never by the application.
  static LinkOpener opener = const SystemLinkOpener();

  /// Restores [SystemLinkOpener]. Called from a `tearDown`.
  static void reset() => opener = const SystemLinkOpener();
}

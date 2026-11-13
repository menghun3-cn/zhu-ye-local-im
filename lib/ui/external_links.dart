import 'dart:io';

import 'android_browser.dart';

/// Opens a web page in whatever browser the machine has, and says whether it
/// managed to.
///
/// The application ships no launcher plugin — `url_launcher` is a *native*
/// registration bought for a call the platform's own shell already answers —
/// so each platform is asked directly instead. Windows hands the address to
/// `rundll32`'s `url.dll,FileProtocolHandler`, which is `start`'s "open this
/// with its default handler" without a command shell in between: an address
/// now comes out of a *message*, and `&` in a query string is not a command
/// separator to hand to `cmd`. Android asks its own runner's channel, which
/// fires an `ACTION_VIEW` intent. Anywhere else this answers false, and the
/// caller leaves the address on screen to be copied by hand.
///
/// [url] is checked before it goes anywhere near a shell or an intent, and
/// only http and https addresses pass. The address normally comes out of a
/// GitHub response or a received message — the second is peer-written text,
/// which is why the check is a scheme whitelist rather than a host one.
Future<bool> openInBrowser(String url) async {
  if (!isOpenableLink(url)) return false;
  if (Platform.isWindows) {
    try {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      return true;
    } on Object {
      return false;
    }
  }
  if (Platform.isAndroid) return openAndroidLink(url);
  return false;
}

/// Whether [url] is an http or https address a browser can be handed.
bool isOpenableLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  // A space or a control character would split the address somewhere between
  // here and the browser; a URI never legitimately carries one.
  return !url.contains(RegExp(r'[\x00-\x20]'));
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
/// offered by more than one surface — the About card, the rail's update
/// entry, and now every URL inside a message — and a test-only argument on
/// all of them would put the seam in the application's vocabulary.
abstract final class LinkResolution {
  /// The opener in force. Set by a test; never by the application.
  static LinkOpener opener = const SystemLinkOpener();

  /// Restores [SystemLinkOpener]. Called from a `tearDown`.
  static void reset() => opener = const SystemLinkOpener();
}

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

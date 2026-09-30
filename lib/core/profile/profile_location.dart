import '../clipboard/clipboard_capability.dart' show DevicePlatform;

/// Where this Device keeps the files it owns, as far as the host will say.
///
/// Paths are joined with `/` on every platform: Dart accepts it on Windows,
/// Android and everywhere else this project runs, and a function that built
/// separators from the *host's* convention could not be asked what an Android
/// path looks like. The rules per platform are facts about the host, so they
/// are inputs here rather than guesses: `environment` is the process
/// environment and `appDataDirectory` is the private directory a platform
/// hands over when it has one.
///
/// Nothing here creates anything. These functions decide a path; the store and
/// the transfer sink are what make it exist.
///
/// A null [profileFilePath] is a real answer, not a failure: a Device with
/// nowhere durable to write runs without persistence, keeps its identity for
/// as long as the app does, and has to be paired again after a restart.
/// Inventing a directory — a relative path, a temporary one — would hide that
/// and lose the group secret on somebody's behalf.
String? profileFilePath({
  required DevicePlatform platform,
  required Map<String, String> environment,
  String? appDataDirectory,
}) {
  final directory = _dataDirectory(
    platform: platform,
    environment: environment,
    appDataDirectory: appDataDirectory,
  );
  return directory == null ? null : '$directory/profile.json';
}

/// Where a Transfer with no destination chosen yet should land, or null when
/// the host has no such place.
///
/// A default rather than a decision: the user picks the directory they mean,
/// and this is what the field starts as. On Android it is the app's own
/// directory, which is always writable and never needs a permission — the
/// price is that it is not the gallery or the Downloads folder, which is
/// recorded as a gap rather than papered over.
String? defaultIncomingDirectory({
  required DevicePlatform platform,
  required Map<String, String> environment,
  String? appDataDirectory,
}) {
  switch (platform) {
    case DevicePlatform.windows:
      final home = environment['USERPROFILE'] ?? environment['HOME'];
      if (home == null || home.isEmpty) return null;
      return '$home/Downloads/LocalTransfer';
    case DevicePlatform.android:
      if (appDataDirectory == null || appDataDirectory.isEmpty) return null;
      return '$appDataDirectory/incoming';
    case DevicePlatform.other:
      return null;
  }
}

/// Where a persisted profile goes, before the filename is appended.
String? _dataDirectory({
  required DevicePlatform platform,
  required Map<String, String> environment,
  String? appDataDirectory,
}) {
  // A platform that told us where its private data lives has answered the
  // question whatever it is running on, so that answer wins.
  if (appDataDirectory != null && appDataDirectory.isNotEmpty) {
    return appDataDirectory;
  }
  if (platform != DevicePlatform.windows) return null;
  // Both are per-user directory roots. A profile is this machine's Device
  // identity, not something to carry to another machine, which is why the
  // per-user ones are the right pair to try.
  for (final key in const ['APPDATA', 'LOCALAPPDATA']) {
    final value = environment[key];
    if (value != null && value.isNotEmpty) return '$value/LocalTransfer';
  }
  final home = environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) return '$home/.local_transfer';
  return null;
}

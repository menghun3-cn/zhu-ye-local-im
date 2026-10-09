/// The version this build carries, and how two of them compare.
///
/// A constant rather than something read off the platform: the number that
/// matters is the one in `pubspec.yaml`, and the plugin that would read it back
/// (`package_info_plus`) is a *native* registration bought for one string.
/// `test/app/app_version_test.dart` reads the pubspec and fails when the two
/// drift, which is the whole of what a build-time read would have bought.
///
/// `lib/app` is plain Dart — see `app.dart`, and the test that keeps Flutter
/// out of it — so nothing here may import Flutter, and nothing needs to.
library;

/// The `version:` of `pubspec.yaml`, without its build number.
///
/// The build number is dropped because it is about how the file was made and
/// not about what the user is running: two builds of the same source are the
/// same version to everybody outside this repository.
const String appVersion = '1.0.0';

/// Whether [candidate] names a version newer than [current].
///
/// Only the numbers are compared, and missing ones read as zero, so `1.2` is
/// newer than `1.1.9` and `1.0.0` is not newer than `1.0`. Everything that is
/// not a number — a leading `v`, a `-rc1` suffix, a `+7` build number — is
/// ignored, because a tag is written with whatever punctuation its author
/// likes and this decision is only ever "is there something newer to fetch".
bool isNewerVersion(String candidate, String current) {
  final left = versionNumbers(candidate);
  final right = versionNumbers(current);
  final width = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < width; index++) {
    final a = index < left.length ? left[index] : 0;
    final b = index < right.length ? right[index] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// The leading run of dotted numbers in [version], in order.
///
/// Empty when there is no number at all, which is what a tag like `nightly`
/// reads as — and an empty list compares as all zeros, so nothing is newer than
/// a version nobody can parse.
List<int> versionNumbers(String version) {
  final start = version.indexOf(RegExp(r'[0-9]'));
  if (start < 0) return const [];
  final run = RegExp(r'^[0-9.]+').firstMatch(version.substring(start));
  if (run == null) return const [];
  return [
    for (final part in run.group(0)!.split('.'))
      if (part.isNotEmpty) int.tryParse(part) ?? 0,
  ];
}

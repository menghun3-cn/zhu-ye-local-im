import 'package:flutter/services.dart';

import 'update_install.dart';

/// The Android runner's channel for handing a checked APK to the system.
const MethodChannel androidUpdateChannel = MethodChannel(
  'cn.hnasct.local_transfer/update',
);

/// The one method that channel implements.
const String installApkMethod = 'installApk';

/// Opens Android's package installer for [path].
///
/// A `permission` answer means the app must first be allowed to install unknown
/// apps; the runner has already opened that Settings page. The next press will
/// find the permission granted and hand the APK over.
Future<AndroidInstallOutcome> installAndroidPackage(String path) async {
  final answer = await androidUpdateChannel.invokeMethod<String>(
    installApkMethod,
    <String, Object?>{'path': path},
  );
  return switch (answer) {
    'permission' => AndroidInstallOutcome.permission,
    'started' => AndroidInstallOutcome.started,
    _ => throw StateError('unexpected Android installer answer: $answer'),
  };
}

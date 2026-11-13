import 'package:flutter/services.dart';

/// The Android runner's channel for handing a file or a folder to the
/// system's own handlers.
///
/// `openFile` answers whether an application claimed the file — an APK goes
/// to the package installer, anything else to whatever its type resolves to.
/// `openFolder` asks a file manager to show the directory; a directory inside
/// the app's private storage is one no file manager can browse, so false is
/// an ordinary answer there rather than a failure.
const MethodChannel androidFilesChannel = MethodChannel(
  'cn.hnasct.local_transfer/files',
);

/// The method [androidFilesChannel] opens a file with.
const String openFileMethod = 'openFile';

/// The method [androidFilesChannel] shows a folder with.
const String openFolderMethod = 'openFolder';

/// Hands [path] to Android's "open with" and answers whether anything took it.
///
/// Every failure — a platform that never registered the channel, a file that
/// is not there, no application for its type — is false, because the caller's
/// answer to all of them is the same sentence.
Future<bool> openAndroidFile(String path) =>
    _askAndroidFiles(openFileMethod, path);

/// Shows [path]'s folder to Android's file managers, answering whether one
/// took it. See [androidFilesChannel] for why false is ordinary.
Future<bool> openAndroidFolder(String path) =>
    _askAndroidFiles(openFolderMethod, path);

Future<bool> _askAndroidFiles(String method, String path) async {
  try {
    final answer = await androidFilesChannel.invokeMethod<bool>(method, {
      'path': path,
    });
    return answer ?? false;
  } on Object {
    return false;
  }
}

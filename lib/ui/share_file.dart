import 'dart:io';

import 'android_files.dart';

/// The share sheet this Device offers a landed file through.
///
/// A class rather than a bare function, for the same reason [FileOpener] is
/// one: sharing hands the file to the operating system's chooser — an
/// activity outside Flutter's event loop — which a widget test that drove the
/// real thing would open on the machine running the suite. [ShareResolution]
/// is the substitution point: production leaves the field alone and gets
/// [SystemFileSharer], and a test sets it, drives the flow through a
/// stand-in, and clears it again in a `tearDown`.
abstract interface class FileSharer {
  /// Whether this Device has a share sheet to offer at all.
  ///
  /// Asked before the menu line is drawn, not after it is tapped: an action
  /// that can only ever answer "nothing here takes this" is a line that
  /// should not be on the menu. The answer is a property of the platform,
  /// which is why it sits on the sharer rather than being re-derived per
  /// call.
  bool get supported;

  /// Hands [paths] — every one an existing file — to the share sheet, and
  /// answers whether anything took them.
  Future<bool> share(List<String> paths);
}

/// The real sharer: Android's `ACTION_SEND` sheet, and nothing anywhere else.
///
/// Android is the one platform this Device can reach a chooser on: the runner
/// hands each path to the system as a `content://` URI and the sheet that
/// opens is where WeChat and every other receiving application live. Windows
/// has no equivalent — its share contract does not cover arbitrary files — so
/// [supported] is false there and the menu never offers the line.
final class SystemFileSharer implements FileSharer {
  const SystemFileSharer();

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<bool> share(List<String> paths) async {
    if (!supported) return false;
    // Only real files are offered: a path that has been moved or deleted
    // since the message landed would reach the chooser as a URI nothing can
    // read, and an all-missing list is a share that cannot happen at all.
    final files = [
      for (final path in paths)
        if (FileSystemEntity.typeSync(path) == FileSystemEntityType.file) path,
    ];
    if (files.isEmpty) return false;
    return shareAndroidFiles(files);
  }
}

/// Which sharer the surfaces use.
///
/// A single mutable field rather than a parameter threaded through the widget
/// tree, for the same reason `OpenResolution` is one: the action is offered
/// by more than one surface, and a test-only argument on all of them would
/// put the seam in the application's vocabulary.
abstract final class ShareResolution {
  /// The sharer in force. Set by a test; never by the application.
  static FileSharer sharer = const SystemFileSharer();

  /// Restores [SystemFileSharer]. Called from a `tearDown`.
  static void reset() => sharer = const SystemFileSharer();
}

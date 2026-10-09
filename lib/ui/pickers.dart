import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// The file extensions the image picker offers, and the set an image must be in
/// to be shown as a picture.
///
/// A whitelist rather than "let the decoder decide": an image message is drawn
/// by reading the file, so a picker that let a user choose a `.txt` would
/// produce a bubble that can only ever show its own name. These are the formats
/// Flutter's decoders handle on every desktop platform.
const List<String> imageExtensions = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
];

/// The picker the composer asks for files and images.
///
/// A class rather than two bare functions because a *native* dialog is the one
/// thing a widget test cannot drive: it opens outside Flutter, blocks on the
/// platform's own event loop, and never returns to a `testWidgets` body. With
/// no way to substitute it, every test that involves choosing a file would have
/// to be deleted — and choosing a file is now most of what the composer does.
///
/// [resolution] is the substitution point. Production leaves [picker] null and
/// gets [SystemPicker]; a test sets it, drives the flow through a stand-in, and
/// clears it again in a `tearDown`.
abstract interface class FilePicker {
  /// Asks for files to send. Empty when the user cancelled.
  Future<List<XFile>> files();

  /// Asks for one image to send. Null when the user cancelled.
  Future<XFile?> image();

  /// Asks for a folder to keep things in. Null when the user cancelled.
  ///
  /// The same seam as the two above, and for the same reason: this is the OS's
  /// own folder chooser, and a dialog that runs outside Flutter never returns
  /// to a `testWidgets` body. A destination a user can only *type* is a
  /// destination most users cannot set at all.
  Future<String?> directory();
}

/// The real picker: the operating system's own dialogs.
final class SystemPicker implements FilePicker {
  const SystemPicker();

  @override
  Future<List<XFile>> files() => openFiles(confirmButtonText: '发送');

  @override
  Future<XFile?> image() => openFile(
    confirmButtonText: '发送',
    acceptedTypeGroups: const [
      XTypeGroup(label: '图片', extensions: imageExtensions),
    ],
  );

  @override
  Future<String?> directory() => getDirectoryPath(confirmButtonText: '选择');
}

/// Which picker the composer uses.
///
/// A single mutable field rather than a parameter threaded through the widget
/// tree: the composer is built by several surfaces (the shell's pane, the
/// pushed page) and threading a test-only argument through all of them would
/// put the seam in the application's vocabulary. This is a seam, and it is
/// named like one.
abstract final class PickerResolution {
  /// The picker in force. Set by a test; never by the application.
  static FilePicker picker = const SystemPicker();

  /// Restores [SystemPicker]. Called from a `tearDown`.
  static void reset() => picker = const SystemPicker();
}

/// Whether [path] names a file this app will draw as an image.
///
/// Used to decide what a *dropped* file means. The picker already filters, but a
/// drop does not: anything on the desktop can land on the window, and treating
/// a dropped `.zip` as an image would be a bubble that cannot render.
bool looksLikeImage(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  final extension = path.substring(dot + 1).toLowerCase();
  return imageExtensions.contains(extension);
}

/// The result of a drop, as the two things a dropped path can mean.
///
/// Returned rather than acted on so that the widget layer keeps the deciding:
/// this file knows what a path *is*, and the conversation knows what to do
/// about it.
({List<File> images, List<File> files}) classifyDrop(List<String> paths) {
  final images = <File>[];
  final files = <File>[];
  for (final path in paths) {
    final file = File(path);
    // A dropped folder has a path but no bytes; sending it would produce an
    // offer whose item is zero bytes long under a name that looks like a file.
    // `File.existsSync` is false for a directory, so one check covers both.
    if (!file.existsSync()) continue;
    (looksLikeImage(path) ? images : files).add(file);
  }
  return (images: images, files: files);
}

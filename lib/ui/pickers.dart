import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// The set a file must be in to be sent — and drawn — as a picture.
///
/// A whitelist rather than "let the decoder decide": an image message is drawn
/// by reading the file, so treating a `.txt` as a picture would produce a
/// bubble that can only ever show its own name. These are the formats Flutter's
/// decoders handle on every desktop platform.
const List<String> imageExtensions = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
];

/// The formats a bubble-skin picture may be — [imageExtensions] minus `gif`.
///
/// A skin is a still background: a GIF would only ever show its first frame,
/// which is a picture the user did not pick, so the format is refused at the
/// dialog rather than silently flattened later.
const List<String> bubbleSkinImageExtensions = [
  'png',
  'jpg',
  'jpeg',
  'webp',
  'bmp',
];

/// The largest picture a bubble skin may be, in bytes.
///
/// A skin is decoded at a capped width anyway, so a bigger file
/// only ever costs disk and load time — the cap is generous enough that no
/// reasonable picture hits it and tight enough that a mistaken multi-hundred
/// megabyte pick fails loudly instead of being copied into app data.
const int bubbleSkinMaxImageBytes = 2 * 1024 * 1024;

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
  ///
  /// One dialog for everything the composer can attach, pictures included: a
  /// picture *is* a file, and which of the two a choice turns out to be is
  /// decided by [looksLikeImage] rather than by which control was pressed. A
  /// second dialog behind a picture-only filter would make the same photograph
  /// two different messages depending on the door it came in through, and would
  /// leave the user to know that "send a file" cannot send a picture — a rule
  /// that was only ever true of a filter.
  Future<List<XFile>> files();

  /// Asks for a folder to keep things in. Null when the user cancelled.
  ///
  /// The same seam as the one above, and for the same reason: this is the OS's
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
  Future<String?> directory() => getDirectoryPath(confirmButtonText: '选择');
}

/// Whether [path] names a file the bubble-skin picker will accept.
///
/// Checked in Dart rather than as a dialog filter for the same reason
/// [looksLikeImage] exists: the picker is one dialog for everything, and
/// what a choice *means* is decided after it — here, "this is a picture a
/// bubble can wear". A GIF is refused even though [imageExtensions] takes
/// it: a skin is a still background, and a GIF would only ever show its
/// first frame.
bool looksLikeBubbleSkinImage(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  final extension = path.substring(dot + 1).toLowerCase();
  return bubbleSkinImageExtensions.contains(extension);
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

/// One path that names a real file, and whether this app draws it as a picture.
typedef ClassifiedPath = ({File file, bool isImage});

/// The paths that name a real file, in the order they were handed in.
///
/// A folder has a path but no bytes; sending one would produce an offer whose
/// item is zero bytes long under a name that looks like a file. `File.existsSync`
/// is false for a directory, so one check covers both. The order is kept
/// because it is the order the user chose, and a message is read in the order
/// it was composed.
List<ClassifiedPath> classifyPaths(List<String> paths) => [
  for (final path in paths)
    if (File(path).existsSync())
      (file: File(path), isImage: looksLikeImage(path)),
];

/// One image in the screenshot history.
///
/// The entry is the *index* record; the pixels live in a PNG file beside it,
/// named by [id]. Keeping the two apart is what lets the history window draw
/// a grid of thumbnails without decoding every file up front, and what lets a
/// pinned image outlive the history entry that produced it — a pin points at
/// its own file, not at a history slot.
final class ScreenshotEntry {
  const ScreenshotEntry({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.width,
    required this.height,
  });

  /// The entry's stable identity, also its file's base name.
  final String id;

  /// The PNG file inside the library directory, e.g. `3f9a…c2.png`.
  final String fileName;

  /// When the capture was taken, in UTC.
  final DateTime createdAt;

  /// The image's pixel size, recorded so a grid can lay out before decode.
  final int width;
  final int height;

  /// The full path [fileName] resolves to inside [directory].
  String pathIn(String directory) => '$directory/$fileName';

  Map<String, Object?> toJson() => {
    'id': id,
    'file': fileName,
    'at': createdAt.toUtc().toIso8601String(),
    'w': width,
    'h': height,
  };

  static ScreenshotEntry fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final file = json['file'];
    final at = json['at'];
    final width = json['w'];
    final height = json['h'];
    if (id is! String ||
        file is! String ||
        at is! String ||
        width is! int ||
        height is! int) {
      throw const FormatException('a screenshot entry is incomplete');
    }
    final created = DateTime.tryParse(at);
    if (created == null) {
      throw FormatException('"at" is not an ISO-8601 timestamp: "$at"');
    }
    return ScreenshotEntry(
      id: id,
      fileName: file,
      createdAt: created,
      width: width,
      height: height,
    );
  }
}

/// One image pinned to the desktop.
///
/// Persisted rather than session-only because a pin is the one screenshot
/// artefact the user deliberately placed on screen: losing it on restart
/// would be the feature forgetting the thing it was asked to remember. The
/// record carries the window's geometry and behaviour flags; the pixels are
/// a PNG file in the same directory, named by [id].
final class PinRecord {
  const PinRecord({
    required this.id,
    required this.fileName,
    required this.createdAt,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.alwaysOnTop = true,
    this.clickThrough = false,
    this.updatedAt,
  });

  /// The pin's stable identity, also its file's base name.
  final String id;

  /// The PNG file inside the pins directory.
  final String fileName;

  /// When the pin was first placed, in UTC.
  final DateTime createdAt;

  /// The window's last known position and size, in the same screen
  /// coordinates `window_manager` reports — whatever unit that is, it is
  /// written back through the same API, so the record round-trips.
  ///
  /// Zero means "wherever it was when first pinned" — the restoring window
  /// picks a cascade offset rather than trusting coordinates that may point
  /// at a monitor that is no longer attached.
  final double x;
  final double y;
  final double width;
  final double height;

  /// Whether the pin stays above other windows.
  final bool alwaysOnTop;

  /// Whether the mouse passes through the pin to the window beneath.
  final bool clickThrough;

  /// When the geometry or flags last changed, in UTC.
  final DateTime? updatedAt;

  /// The full path [fileName] resolves to inside [directory].
  String pathIn(String directory) => '$directory/$fileName';

  /// A copy with the window-state fields replaced.
  PinRecord copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    bool? alwaysOnTop,
    bool? clickThrough,
    DateTime? updatedAt,
  }) => PinRecord(
    id: id,
    fileName: fileName,
    createdAt: createdAt,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
    clickThrough: clickThrough ?? this.clickThrough,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'file': fileName,
    'at': createdAt.toUtc().toIso8601String(),
    'x': x,
    'y': y,
    'w': width,
    'h': height,
    'top': alwaysOnTop,
    'pass': clickThrough,
    if (updatedAt != null) 'upd': updatedAt!.toUtc().toIso8601String(),
  };

  static PinRecord fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final file = json['file'];
    final at = json['at'];
    if (id is! String || file is! String || at is! String) {
      throw const FormatException('a pin record is incomplete');
    }
    final created = DateTime.tryParse(at);
    if (created == null) {
      throw FormatException('"at" is not an ISO-8601 timestamp: "$at"');
    }
    return PinRecord(
      id: id,
      fileName: file,
      createdAt: created,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['w'] as num?)?.toDouble() ?? 0,
      height: (json['h'] as num?)?.toDouble() ?? 0,
      alwaysOnTop: json['top'] is bool ? json['top'] as bool : true,
      clickThrough: json['pass'] is bool ? json['pass'] as bool : false,
      updatedAt: _date(json['upd']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}

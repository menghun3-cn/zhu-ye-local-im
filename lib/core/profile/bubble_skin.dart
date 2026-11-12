/// What a message bubble is painted with, as the user chose it.
///
/// A skin is *user data*, not a palette: it lives in the profile beside the
/// other preferences, and it describes one bubble's fill — a gradient, or an
/// image — plus the ink its text is drawn in. The two sides of a conversation
/// keep separate skins ([DeviceProfile.outgoingBubbleSkin] and
/// [DeviceProfile.incomingBubbleSkin]); null on either means "the theme's own
/// colours", which is what every Device starts with.
///
/// The model is deliberately free of Flutter: colours are stored as ARGB
/// integers and images as an asset name or a file path, so the whole file
/// round-trips through JSON in a plain `dart test` and the widget layer is the
/// only place a [Color] or an [ImageProvider] ever appears.
library;

/// The two inks a bubble's content can be drawn in.
///
/// A binary choice rather than a free colour: the ink has to stay legible on
/// whatever the user picked, and offering a colour wheel for text on top of a
/// colour wheel for the fill is how unreadable combinations get made. Dark
/// resolves to the theme's near-black text colour, light to white — see
/// `bubble_paint.dart`.
enum BubbleSkinInk {
  /// Near-black text, for light fills.
  dark,

  /// White text, for dark fills.
  light;

  /// The value used in persisted state.
  String get wireName => name;

  /// Resolves a wire value, or null when it names nothing this build knows.
  static BubbleSkinInk? fromWireName(String? value) {
    for (final ink in BubbleSkinInk.values) {
      if (ink.wireName == value) return ink;
    }
    return null;
  }
}

/// Which way a [GradientBubbleSkin]'s colours run.
enum BubbleGradientDirection {
  /// Left edge to right edge.
  horizontal,

  /// Top edge to bottom edge.
  vertical,

  /// Top-left to bottom-right.
  diagonal;

  /// The value used in persisted state.
  String get wireName => name;

  /// Resolves a wire value, or null when it names nothing this build knows.
  static BubbleGradientDirection? fromWireName(String? value) {
    for (final direction in BubbleGradientDirection.values) {
      if (direction.wireName == value) return direction;
    }
    return null;
  }
}

/// Where an [ImageBubbleSkin]'s picture comes from.
enum BubbleSkinImageSource {
  /// One of the pictures bundled with the application (`assets/bubble_skins/`).
  asset,

  /// A picture the user picked, copied into the app's own directory at the
  /// time it was chosen — never the path the picker handed back, which on
  /// Android is a `content://` URI or a cache copy that does not survive.
  file;

  /// The value used in persisted state.
  String get wireName => name;

  /// Resolves a wire value, or null when it names nothing this build knows.
  static BubbleSkinImageSource? fromWireName(String? value) {
    for (final source in BubbleSkinImageSource.values) {
      if (source.wireName == value) return source;
    }
    return null;
  }
}

/// A bubble's fill: a gradient or an image, with the ink drawn on top of it.
///
/// Sealed rather than open: the set of fills a bubble can have is exactly
/// these two, and a third would be a design decision, not an extension point.
sealed class BubbleSkin {
  const BubbleSkin({required this.ink});

  /// The ink the bubble's text, icons and progress track are drawn in.
  final BubbleSkinInk ink;

  /// Serialises to the profile's JSON shape. The inverse is [fromJson], which
  /// answers null for anything it cannot fully decode — a skin that fails to
  /// parse is a skin the user never had, not a reason to lose the profile.
  Map<String, Object?> toJson();

  /// The same skin with its ink changed.
  ///
  /// The picker's ink toggle works on whatever is currently chosen — a
  /// preset included — and rebuilding the whole skin to change one field is
  /// exactly what this spares the caller from knowing how.
  BubbleSkin withInk(BubbleSkinInk ink);

  /// Decodes one skin, or null when [json] is not a skin this build knows.
  ///
  /// Null covers every failure the same way: wrong shape, unknown `kind`,
  /// out-of-range numbers. A profile written by a newer build that added a
  /// fill type reads as "no custom skin" here rather than as a parse error —
  /// which is also what downgrading should do.
  static BubbleSkin? fromJson(Object? json) {
    if (json is! Map) return null;
    final ink = BubbleSkinInk.fromWireName(json['ink'] as String?);
    if (ink == null) return null;
    switch (json['kind']) {
      case 'gradient':
        return _gradientFromJson(json, ink);
      case 'image':
        return _imageFromJson(json, ink);
      default:
        return null;
    }
  }

  static GradientBubbleSkin? _gradientFromJson(
    Map<dynamic, dynamic> json,
    BubbleSkinInk ink,
  ) {
    final rawColors = json['colors'];
    final direction = BubbleGradientDirection.fromWireName(
      json['direction'] as String?,
    );
    if (rawColors is! List || rawColors.length < 2 || rawColors.length > 4) {
      return null;
    }
    final colors = <int>[];
    for (final entry in rawColors) {
      final color = _colour(entry);
      if (color == null) return null;
      colors.add(color);
    }
    final stops = _stops(json['stops'], colors.length);
    if (stops == null) return null;
    return GradientBubbleSkin(
      colors: colors,
      stops: stops,
      direction: direction ?? BubbleGradientDirection.horizontal,
      ink: ink,
    );
  }

  static ImageBubbleSkin? _imageFromJson(
    Map<dynamic, dynamic> json,
    BubbleSkinInk ink,
  ) {
    final source = BubbleSkinImageSource.fromWireName(
      json['source'] as String?,
    );
    final name = json['name'];
    if (source == null || name is! String || name.isEmpty) return null;
    final scrim = json['scrim'];
    if (scrim != null && (scrim is! num || scrim < 0 || scrim > maxScrim)) {
      return null;
    }
    return ImageBubbleSkin(
      source: source,
      name: name,
      scrim: (scrim as num?)?.toDouble() ?? defaultScrim,
      ink: ink,
    );
  }

  /// The scrim an image skin carries when the profile does not say.
  static const double defaultScrim = 0.25;

  /// The darkest scrim an image skin may ask for.
  ///
  /// Past this the picture stops being a skin and becomes a tint — which is
  /// what the solid-colour end of the picker is already for, without losing
  /// the image entirely.
  static const double maxScrim = 0.6;

  /// Parses `'#RRGGBB'` (or `'#AARRGGBB'`) into an ARGB int, or null.
  static int? _colour(Object? value) {
    if (value is! String) return null;
    final hex = value.startsWith('#') ? value.substring(1) : value;
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return hex.length == 6 ? 0xFF000000 | parsed : parsed;
  }

  /// Reads `stops`, or answers null when a present-but-broken list would
  /// otherwise reach the paint layer. Absent stops are evenly spaced, which
  /// is what [GradientBubbleSkin.stops] documents as null.
  static List<double>? _stops(Object? raw, int count) {
    if (raw == null) return const [];
    if (raw is! List || raw.length != count) return null;
    final stops = <double>[];
    for (final entry in raw) {
      if (entry is! num || entry < 0 || entry > 1) return null;
      stops.add(entry.toDouble());
    }
    return stops;
  }
}

/// A bubble filled with a linear gradient of two to four colours.
final class GradientBubbleSkin extends BubbleSkin {
  /// A gradient from [colors] in [direction], with text in [ink].
  ///
  /// [stops] is either empty — even spacing, the common case — or exactly
  /// `colors.length` values in 0..1. The constructor enforces both rather than
  /// trusting every caller: a stops list that does not match the colours is
  /// a paint error at best and a crash in `LinearGradient` at worst.
  GradientBubbleSkin({
    required List<int> colors,
    List<double> stops = const [],
    this.direction = BubbleGradientDirection.horizontal,
    required super.ink,
  }) : colors = List.unmodifiable(colors),
       stops = List.unmodifiable(stops) {
    if (this.colors.length < 2 || this.colors.length > 4) {
      throw ArgumentError.value(
        colors,
        'colors',
        'a gradient skin needs two to four colours',
      );
    }
    if (this.stops.isNotEmpty && this.stops.length != this.colors.length) {
      throw ArgumentError.value(
        stops,
        'stops',
        'must be empty or match colors.length',
      );
    }
  }

  /// The gradient's colours as ARGB ints, first to last along [direction].
  final List<int> colors;

  /// Where each colour sits along the gradient, or empty for even spacing.
  final List<double> stops;

  /// Which way the gradient runs.
  final BubbleGradientDirection direction;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'gradient',
    'ink': ink.wireName,
    'direction': direction.wireName,
    'colors': [
      for (final color in colors) '#${color.toRadixString(16).padLeft(8, '0')}',
    ],
    if (stops.isNotEmpty) 'stops': stops,
  };

  @override
  BubbleSkin withInk(BubbleSkinInk ink) => GradientBubbleSkin(
    colors: colors,
    stops: stops,
    direction: direction,
    ink: ink,
  );

  @override
  bool operator ==(Object other) =>
      other is GradientBubbleSkin &&
      other.ink == ink &&
      other.direction == direction &&
      _listEquals(other.colors, colors) &&
      _listEquals(other.stops, stops);

  @override
  int get hashCode => Object.hash(
    ink,
    direction,
    Object.hashAll(colors),
    Object.hashAll(stops),
  );
}

/// A bubble filled with a picture, dimmed by [scrim] so the ink stays legible.
final class ImageBubbleSkin extends BubbleSkin {
  /// An image skin: [name] under [source], inked in [ink], over a scrim of
  /// [scrim] black.
  ImageBubbleSkin({
    required this.source,
    required this.name,
    this.scrim = BubbleSkin.defaultScrim,
    required super.ink,
  }) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (scrim < 0 || scrim > BubbleSkin.maxScrim) {
      throw ArgumentError.value(scrim, 'scrim', 'must be within 0..maxScrim');
    }
  }

  /// Whether [name] is a bundled asset or a copied file on disk.
  final BubbleSkinImageSource source;

  /// The asset's name inside `assets/bubble_skins/`, or the absolute path of
  /// the copied file — what [source] says which.
  final String name;

  /// How much black is laid over the picture, 0 (none) to
  /// [BubbleSkin.maxScrim]. The picture is what the user picked; the scrim is
  /// what keeps the text readable on it.
  final double scrim;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'image',
    'ink': ink.wireName,
    'source': source.wireName,
    'name': name,
    'scrim': scrim,
  };

  @override
  BubbleSkin withInk(BubbleSkinInk ink) =>
      ImageBubbleSkin(source: source, name: name, scrim: scrim, ink: ink);

  @override
  bool operator ==(Object other) =>
      other is ImageBubbleSkin &&
      other.ink == ink &&
      other.source == source &&
      other.name == name &&
      other.scrim == scrim;

  @override
  int get hashCode => Object.hash(ink, source, name, scrim);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

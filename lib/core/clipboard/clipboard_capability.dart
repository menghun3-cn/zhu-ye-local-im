/// The platform a [Device] runs on, as far as clipboard behaviour is concerned.
///
/// Only the two v1 platforms are modelled; anything else is [other] and is
/// treated as the most restrictive case rather than assumed to behave like a
/// supported platform.
enum DevicePlatform {
  windows('windows', 'Windows'),
  android('android', 'Android'),
  other('other', 'Other');

  const DevicePlatform(this.wireName, this.displayName);

  /// The value used on the wire and in persisted state.
  final String wireName;

  /// Human-readable label for the UI.
  final String displayName;

  /// Resolves a wire value, or throws [FormatException] if unknown.
  static DevicePlatform fromWireName(String value) {
    for (final platform in DevicePlatform.values) {
      if (platform.wireName == value) return platform;
    }
    throw FormatException('unknown platform "$value"');
  }
}

/// What a [Device] can actually do with its system clipboard.
///
/// Reading and writing the clipboard are governed by different rules on every
/// platform, so the two abilities are declared separately. The pair travels in
/// every `hello` so no peer can present a Device as capable of something its
/// platform forbids.
///
/// Values are verified in `docs/platform-clipboard-constraints.md`.
final class ClipboardCapability {
  const ClipboardCapability({
    required this.canOriginate,
    required this.canApply,
  });

  /// The capability profile recorded for [platform].
  ///
  /// Windows is the only v1 platform with a prompt-free, fully background
  /// clipboard path in both directions. Android can apply a Mirror in the
  /// background but can only read the clipboard while its window is on screen.
  /// Unlisted platforms are assumed to be able to do neither.
  factory ClipboardCapability.forPlatform(DevicePlatform platform) {
    return switch (platform) {
      DevicePlatform.windows => const ClipboardCapability(
        canOriginate: true,
        canApply: true,
      ),
      DevicePlatform.android => const ClipboardCapability(
        // A foreground service is not enough: the platform requires *window*
        // focus to read, so background monitoring is impossible.
        canOriginate: false,
        canApply: true,
      ),
      DevicePlatform.other => const ClipboardCapability(
        canOriginate: false,
        canApply: false,
      ),
    };
  }

  /// Whether this Device can detect a local copy and send it onward.
  ///
  /// On Android this is true only while the window is focused, which is a
  /// runtime condition the flag cannot express; the flag states the
  /// platform-level limit.
  final bool canOriginate;

  /// Whether this Device can apply an incoming Mirror without user action.
  final bool canApply;

  /// Whether clipboard Mirroring with this Device can work at all.
  bool get canMirrorAtAll => canOriginate || canApply;

  Map<String, Object?> toJson() => {
    'canOriginate': canOriginate,
    'canApply': canApply,
  };

  static ClipboardCapability fromJson(Map<String, Object?> json) {
    return ClipboardCapability(
      canOriginate: _bool(json, 'canOriginate'),
      canApply: _bool(json, 'canApply'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClipboardCapability &&
      other.canOriginate == canOriginate &&
      other.canApply == canApply;

  @override
  int get hashCode => Object.hash(canOriginate, canApply);

  @override
  String toString() =>
      'ClipboardCapability(originate: $canOriginate, apply: $canApply)';

  static bool _bool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException('"$key" must be a bool, got ${value.runtimeType}');
    }
    return value;
  }
}

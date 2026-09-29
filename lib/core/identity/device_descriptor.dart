import '../clipboard/clipboard_capability.dart';
import 'fingerprint.dart';

/// What a Device tells other Devices about itself.
///
/// This is the part of a handshake that is stable for the lifetime of the
/// Device and safe to show in a UI. It travels inside every `hello`, so it is
/// also the part an untrusted peer controls — every field is validated on the
/// way in.
final class DeviceDescriptor {
  DeviceDescriptor({
    required this.fingerprint,
    required String alias,
    required this.platform,
    required this.capability,
    this.listenPort,
  }) : alias = sanitiseAlias(alias) {
    final port = listenPort;
    if (port != null && (port < 1 || port > 65535)) {
      throw RangeError.value(port, 'listenPort', 'must be in 1..65535');
    }
  }

  /// The longest Alias this implementation accepts.
  ///
  /// A peer that sends a longer one is not rejected outright — the value is
  /// truncated — because a hostile name must not be able to make a Device
  /// unusable. Truncation is visible in the UI, so it is self-reporting.
  static const int maxAliasLength = 64;

  /// The alias shown when a Device sends nothing usable.
  static const String fallbackAlias = 'Unnamed device';

  /// The Device's stable identity.
  final Fingerprint fingerprint;

  /// The human-readable name the Device shows to others.
  final String alias;

  /// The platform the Device runs on.
  final DevicePlatform platform;

  /// What the Device can do with its clipboard.
  final ClipboardCapability capability;

  /// The port the Device listens on, if it accepts connections.
  final int? listenPort;

  /// Normalises a peer-supplied or locally chosen Alias.
  ///
  /// Control characters are dropped rather than escaped: a name containing a
  /// terminal escape sequence or a newline exists to mislead whoever reads a
  /// log or a list, and there is no legitimate reason to keep one. Runs of
  /// whitespace collapse so a name cannot be padded to hide its real end.
  static String sanitiseAlias(String raw) {
    final withoutControl = raw.replaceAll(
      RegExp(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]'),
      '',
    );
    final collapsed = withoutControl.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return fallbackAlias;
    if (collapsed.length <= maxAliasLength) return collapsed;
    return collapsed.substring(0, maxAliasLength);
  }

  Map<String, Object?> toJson() => {
    'fp': fingerprint.hex,
    'alias': alias,
    'platform': platform.wireName,
    'clip': capability.toJson(),
    if (listenPort != null) 'port': listenPort,
  };

  static DeviceDescriptor fromJson(Map<String, Object?> json) {
    final rawAlias = json['alias'];
    final rawPlatform = json['platform'];
    final rawClip = json['clip'];
    final rawPort = json['port'];
    if (rawAlias is! String) {
      throw FormatException('"alias" must be a string');
    }
    if (rawPlatform is! String) {
      throw FormatException('"platform" must be a string');
    }
    if (rawClip is! Map) {
      throw FormatException('"clip" must be an object');
    }
    if (rawPort != null && rawPort is! int) {
      throw FormatException('"port" must be an int when present');
    }
    return DeviceDescriptor(
      fingerprint: Fingerprint(_requireString(json, 'fp')),
      alias: rawAlias,
      platform: DevicePlatform.fromWireName(rawPlatform),
      capability: ClipboardCapability.fromJson(rawClip.cast<String, Object?>()),
      listenPort: rawPort as int?,
    );
  }

  @override
  String toString() => 'DeviceDescriptor(${fingerprint.short()}, "$alias")';
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('"$key" must be a string');
  }
  return value;
}

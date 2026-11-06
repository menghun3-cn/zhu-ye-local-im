import 'package:flutter/services.dart';

import '../../core/core.dart';

/// The bridge between the profile's `modifier+key` strings and Flutter's
/// `LogicalKeyboardKey`, shared by the settings page's recorder and the
/// capture overlay's key handling — the two must agree on what `enter` or
/// `pageup` spells, or a binding the page accepts is one the overlay never
/// matches.

/// The named keys [captureKeyNames] defines, as Flutter keys.
const Map<String, LogicalKeyboardKey> _namedKeys = {
  'enter': LogicalKeyboardKey.enter,
  'escape': LogicalKeyboardKey.escape,
  'space': LogicalKeyboardKey.space,
  'tab': LogicalKeyboardKey.tab,
  'backspace': LogicalKeyboardKey.backspace,
  'delete': LogicalKeyboardKey.delete,
  'insert': LogicalKeyboardKey.insert,
  'home': LogicalKeyboardKey.home,
  'end': LogicalKeyboardKey.end,
  'pageup': LogicalKeyboardKey.pageUp,
  'pagedown': LogicalKeyboardKey.pageDown,
  'up': LogicalKeyboardKey.arrowUp,
  'down': LogicalKeyboardKey.arrowDown,
  'left': LogicalKeyboardKey.arrowLeft,
  'right': LogicalKeyboardKey.arrowRight,
};

/// How each named key is written for the user — shorter where the
/// abbreviation is the one everyone uses. Non-const because
/// [LogicalKeyboardKey] is not a legal const map key.
final Map<LogicalKeyboardKey, String> _keyLabels = {
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.insert: 'Insert',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'PgUp',
  LogicalKeyboardKey.pageDown: 'PgDn',
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
};

/// Reads one key name — `q`, `7`, `f5`, `enter` — as a Flutter key, or null
/// when the name is not one the grammar accepts.
LogicalKeyboardKey? captureKeyOf(String name) {
  if (name.length == 1) {
    final code = name.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7a) {
      return LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + code - 0x61);
    }
    if (code >= 0x30 && code <= 0x39) {
      return LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + code - 0x30);
    }
    return null;
  }
  final named = _namedKeys[name];
  if (named != null) return named;
  if (name.startsWith('f')) {
    final n = int.tryParse(name.substring(1));
    if (n != null && n >= 1 && n <= 24) return _functionKey(n);
  }
  return null;
}

/// Writes [key] back as the canonical key name, or null for a key the
/// grammar cannot express — arrows are in, but e.g. `Caps Lock` is not.
String? captureKeyName(LogicalKeyboardKey key) {
  final id = key.keyId;
  final a = LogicalKeyboardKey.keyA.keyId;
  if (id >= a && id <= a + 25) {
    return String.fromCharCode(0x61 + id - a);
  }
  final d = LogicalKeyboardKey.digit0.keyId;
  if (id >= d && id <= d + 9) {
    return String.fromCharCode(0x30 + id - d);
  }
  for (final entry in _namedKeys.entries) {
    if (entry.value.keyId == key.keyId) return entry.key;
  }
  for (var n = 1; n <= 24; n++) {
    if (key == _functionKey(n)) return 'f$n';
  }
  return null;
}

/// A human-readable rendering of an accelerator — `ctrl+enter` reads
/// `Ctrl+Enter`, `q` reads `Q`.
///
/// Used for the settings rows and the overlay's toolbar hints, so both
/// spell a binding the same way the user recorded it.
String captureHotkeyLabel(String accelerator) {
  final parts = accelerator.split('+');
  final labels = <String>[
    for (final part in parts)
      switch (part) {
        'ctrl' => 'Ctrl',
        'shift' => 'Shift',
        'alt' => 'Alt',
        'win' => 'Win',
        _ => _keyLabel(part),
      },
  ];
  return labels.join('+');
}

String _keyLabel(String name) {
  final key = captureKeyOf(name);
  if (key == null) return name;
  final named = _keyLabels[key];
  if (named != null) return named;
  if (name.length == 1) return name.toUpperCase();
  return name;
}

LogicalKeyboardKey _functionKey(int n) => switch (n) {
  1 => LogicalKeyboardKey.f1,
  2 => LogicalKeyboardKey.f2,
  3 => LogicalKeyboardKey.f3,
  4 => LogicalKeyboardKey.f4,
  5 => LogicalKeyboardKey.f5,
  6 => LogicalKeyboardKey.f6,
  7 => LogicalKeyboardKey.f7,
  8 => LogicalKeyboardKey.f8,
  9 => LogicalKeyboardKey.f9,
  10 => LogicalKeyboardKey.f10,
  11 => LogicalKeyboardKey.f11,
  12 => LogicalKeyboardKey.f12,
  13 => LogicalKeyboardKey.f13,
  14 => LogicalKeyboardKey.f14,
  15 => LogicalKeyboardKey.f15,
  16 => LogicalKeyboardKey.f16,
  17 => LogicalKeyboardKey.f17,
  18 => LogicalKeyboardKey.f18,
  19 => LogicalKeyboardKey.f19,
  20 => LogicalKeyboardKey.f20,
  21 => LogicalKeyboardKey.f21,
  22 => LogicalKeyboardKey.f22,
  23 => LogicalKeyboardKey.f23,
  _ => LogicalKeyboardKey.f24,
};

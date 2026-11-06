/// The actions inside the capture overlay that a key press can trigger,
/// and the grammar their bindings are written in.
///
/// Kept in `core` — plain Dart, no Flutter — because the profile stores the
/// bindings, the settings page validates them and the overlay window matches
/// key events against them: three consumers that must agree on one format.
library;

/// What a key inside the capture overlay does.
///
/// The wire names are the profile's JSON keys, so they are stable once
/// shipped: renaming one orphans every saved binding for that action.
enum CaptureAction {
  /// Drag a rectangle.
  region('region'),

  /// Capture the window under the cursor.
  window('window'),

  /// Capture the whole screen.
  full('full'),

  /// Finish and copy to the clipboard.
  copy('copy'),

  /// Finish and pin the result.
  pin('pin'),

  /// Dismiss the overlay.
  cancel('cancel');

  const CaptureAction(this.wireName);

  /// The name this action is stored under in the profile JSON.
  final String wireName;

  /// Reads an action back from its wire name, or null for a name this
  /// build does not know — which is what a profile written by a newer
  /// version looks like, and is not damage.
  static CaptureAction? fromWireName(String name) {
    for (final action in CaptureAction.values) {
      if (action.wireName == name) return action;
    }
    return null;
  }
}

/// The binding a fresh profile starts with for each action.
///
/// Bare letters for the three modes — the overlay owns the keyboard while
/// it is open, so `Q`/`W`/`E` cannot collide with anything the way a
/// global hotkey can. `Enter` finishes, `Ctrl+Enter` pins (the chord keeps
/// the destructive-ish variant off the most-pressed key), `Esc` cancels.
const Map<CaptureAction, String> defaultCaptureKeys = {
  CaptureAction.region: 'q',
  CaptureAction.window: 'w',
  CaptureAction.full: 'e',
  CaptureAction.copy: 'enter',
  CaptureAction.pin: 'ctrl+enter',
  CaptureAction.cancel: 'escape',
};

/// The default binding for [action].
String defaultCaptureKey(CaptureAction action) => defaultCaptureKeys[action]!;

/// The key names [isCaptureHotkey] accepts beyond letters, digits and
/// function keys.
///
/// Canonical spellings only — `escape`, not `esc`; the settings recorder
/// and the overlay's key-event translation both emit this set, so anything
/// else in a hand-edited profile is refused rather than half-supported.
const Set<String> captureKeyNames = {
  'enter',
  'escape',
  'space',
  'tab',
  'backspace',
  'delete',
  'insert',
  'home',
  'end',
  'pageup',
  'pagedown',
  'up',
  'down',
  'left',
  'right',
};

const Set<String> _captureModifiers = {'ctrl', 'shift', 'alt', 'win'};

/// Whether [accelerator] is a binding the capture overlay can match.
///
/// Same `modifier+key` grammar as [isScreenshotHotkey], with two
/// deliberate differences: a bare key is allowed — the overlay has no
/// other app's shortcuts to defer to — and the key may be one of the
/// [captureKeyNames] spellings, because `enter` and `escape` are the two
/// bindings every screenshot tool ships.
bool isCaptureHotkey(String accelerator) {
  final parts = accelerator.split('+');
  if (parts.isEmpty || parts.length > 5) return false;
  if (parts.any((part) => part.isEmpty)) return false;
  var sawKey = false;
  for (final part in parts) {
    if (_captureModifiers.contains(part)) {
      // A modifier after the key (`a+ctrl`) is not a binding.
      if (sawKey) return false;
      continue;
    }
    if (sawKey) return false;
    sawKey = true;
    if (!_isCaptureKey(part)) return false;
  }
  // A modifier with no key (`ctrl+shift`) is not a binding.
  return sawKey;
}

/// Rewrites [accelerator] into the canonical `ctrl+shift+alt+win+key`
/// order, or returns null when [isCaptureHotkey] refuses it.
///
/// The grammar accepts modifiers in any order, but the overlay matches
/// strings, so every stored and every generated binding goes through this
/// once — `shift+ctrl+a` and `ctrl+shift+a` are the same key, and only one
/// of them can be a map key.
String? normalizeCaptureHotkey(String accelerator) {
  if (!isCaptureHotkey(accelerator)) return null;
  final parts = accelerator.split('+');
  final modifiers = <String>[];
  String? key;
  for (final part in parts) {
    if (_captureModifiers.contains(part)) {
      modifiers.add(part);
    } else {
      key = part;
    }
  }
  const order = ['ctrl', 'shift', 'alt', 'win'];
  modifiers.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
  return [...modifiers, ?key].join('+');
}

bool _isCaptureKey(String key) {
  if (_isHotkeyKey(key)) return true;
  return captureKeyNames.contains(key);
}

/// Letters, digits and `f1`–`f24`, shared with [isScreenshotHotkey]'s key
/// half. Duplicated rather than imported because the two grammars are
/// allowed to diverge — this one also takes [captureKeyNames].
bool _isHotkeyKey(String key) {
  if (key.length == 1) {
    final code = key.codeUnitAt(0);
    return (code >= 0x61 && code <= 0x7A) || (code >= 0x30 && code <= 0x39);
  }
  return _isFunctionKey(key);
}

/// `f1`–`f24` — the range [captureKeyOf] can spell back, so a binding
/// outside it could be stored but never matched.
bool _isFunctionKey(String key) {
  if (!key.startsWith('f') || key.length > 3) return false;
  final n = int.tryParse(key.substring(1));
  return n != null && n >= 1 && n <= 24;
}

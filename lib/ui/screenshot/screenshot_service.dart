import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/core.dart';
import 'screenshot_window.dart';
import 'windows/capture_overlay.dart';
import 'windows/editor_window.dart';
import 'windows/history_window.dart';
import 'windows/pin_window.dart';

/// The service the main window is running, for surfaces that need it — the
/// "My" page's screenshot card, the settings sub-page's re-sync.
///
/// A global rather than a constructor argument because the service is created
/// deep inside the app's startup, after the widget tree's seams are already
/// built, and every consumer only ever wants "the one that exists".
ScreenshotService? screenshotService;

/// Everything the screenshot feature does that is not a window: keeping the
/// global hotkey in step with the profile, restoring pins on startup, and
/// opening the right window for the right reason.
///
/// One instance lives in the main window's engine. The other engines never
/// see it — a pin window restoring itself reads the pins file directly, and
/// the hotkey only ever fires in the process that registered it.
final class ScreenshotService {
  ScreenshotService._({required this.libraryPath, required this.pinPath});

  /// Opens the service for this Device, or null when there is nothing to
  /// manage — a non-Windows host, or a test harness with no window.
  static Future<ScreenshotService?> open({
    required String? libraryPath,
    required String? pinPath,
  }) async {
    if (libraryPath == null && pinPath == null) return null;
    return ScreenshotService._(libraryPath: libraryPath, pinPath: pinPath);
  }

  /// Where the history and pins live, as handed over by the platform seams.
  final String? libraryPath;
  final String? pinPath;

  HotKey? _registered;
  bool _restored = false;

  /// Reconciles the global hotkey with what the profile currently says.
  ///
  /// Called at startup and whenever either setting changes: enabled gates
  /// whether anything is registered at all, and the accelerator string is
  /// re-parsed every time so a hotkey edited while the app runs takes effect
  /// without a restart.
  Future<void> syncHotkey({
    required bool enabled,
    required String accelerator,
  }) async {
    final current = _registered;
    if (current != null) {
      await HotKeyManager.instance.unregister(current);
      _registered = null;
    }
    if (!enabled) return;
    final hotKey = _parseAccelerator(accelerator);
    if (hotKey == null) return;
    try {
      await HotKeyManager.instance.register(
        hotKey,
        keyDownHandler: (_) => unawaited(openCapture()),
      );
      _registered = hotKey;
    } on Object {
      // A hotkey another application already owns fails here; the feature
      // stays on and the settings screen can be used to pick another one.
    }
  }

  /// Drops the registration entirely — what disabling the feature or
  /// closing the app both mean.
  Future<void> dispose() async {
    final current = _registered;
    if (current != null) {
      await HotKeyManager.instance.unregister(current);
      _registered = null;
    }
  }

  /// Opens the capture overlay over the whole virtual screen.
  Future<void> openCapture() async {
    await openScreenshotWindow(
      ScreenshotWindowKind.capture,
      libraryPath: libraryPath,
      pinPath: pinPath,
    );
  }

  /// Opens the floating history window.
  Future<void> openHistory() async {
    await openScreenshotWindow(
      ScreenshotWindowKind.history,
      libraryPath: libraryPath,
      pinPath: pinPath,
    );
  }

  /// Re-opens a pin window for every record in the pins store — what startup
  /// does so pins survive a restart, what "restore" does after the user
  /// closed them all.
  Future<void> restorePins() async {
    if (_restored || pinPath == null) return;
    _restored = true;
    final store = PinStore(pinPath!);
    store.reload();
    final pins = await store.pins();
    // Slightly staggered so a dozen pins do not land exactly on top of each
    // other when their saved geometry is all zero.
    for (var i = 0; i < pins.length; i++) {
      await openScreenshotWindow(
        ScreenshotWindowKind.pin,
        libraryPath: libraryPath,
        pinPath: pinPath,
        pinId: pins[i].id,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}

/// Parses `ctrl+shift+a`-style strings into a [HotKey].
///
/// Returns null for anything [isScreenshotHotkey] would refuse, and for
/// keys the plugin cannot express — the settings screen only ever produces
/// the first kind, so a null here means a hand-edited profile.
HotKey? _parseAccelerator(String accelerator) {
  if (!isScreenshotHotkey(accelerator)) return null;
  final parts = accelerator.split('+');
  final modifiers = <HotKeyModifier>[];
  LogicalKeyboardKey? key;
  for (final part in parts) {
    switch (part) {
      case 'ctrl':
        modifiers.add(HotKeyModifier.control);
      case 'shift':
        modifiers.add(HotKeyModifier.shift);
      case 'alt':
        modifiers.add(HotKeyModifier.alt);
      case 'win':
        modifiers.add(HotKeyModifier.meta);
      case _ when part.startsWith('f'):
        final n = int.tryParse(part.substring(1));
        if (n == null || n < 1 || n > 24) return null;
        key = _functionKey(n);
      case _ when part.length == 1:
        final code = part.codeUnitAt(0);
        if (code >= 0x61 && code <= 0x7A) {
          key = LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + code - 0x61);
        } else if (code >= 0x30 && code <= 0x39) {
          key = LogicalKeyboardKey(
            LogicalKeyboardKey.digit0.keyId + code - 0x30,
          );
        }
    }
  }
  if (key == null) return null;
  return HotKey(key: key, modifiers: modifiers);
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

/// Runs the widget a screenshot window's engine was created for.
///
/// Called from `main` *instead of* the ordinary application when
/// [ScreenshotWindowArgs.current] decodes a payload: the extra engines share
/// this `main` because `desktop_multi_window` launches the same executable,
/// and the arguments are the only thing telling them apart.
Widget screenshotWindowRoot(ScreenshotWindowArgs args) => switch (args.kind) {
  ScreenshotWindowKind.capture => CaptureOverlay(args: args),
  ScreenshotWindowKind.history => HistoryWindow(args: args),
  ScreenshotWindowKind.editor => AnnotationEditor(args: args),
  ScreenshotWindowKind.pin => PinWindow(args: args),
};

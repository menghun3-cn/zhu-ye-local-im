import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../app/app_controller.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../screenshot/screenshot_service.dart';

/// The "截图" sub-page under 我的: the feature's on/off switch and the
/// global hotkey that summons the capture overlay.
///
/// The switch is the only gate — pins and history already on disk are the
/// user's pictures and stay either way, and turning the feature back on
/// restores the hotkey without a restart because the app re-syncs the
/// registration on every profile change.
class ScreenshotPage extends StatelessWidget {
  const ScreenshotPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ControllerScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.screenshot_monitor_outlined),
            title: const Text('截图工具'),
            subtitle: const Text('框选、窗口与全屏截图，钉图与标注'),
            value: controller.screenshotEnabled,
            onChanged: controller.setScreenshotEnabled,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '全局快捷键',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  '在任意应用中按下该组合键呼出截图遮罩',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _HotkeyEditor(controller: controller),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('截图历史'),
            subtitle: const Text('打开悬浮历史窗口'),
            onTap: () => screenshotService?.openHistory(),
          ),
        ),
      ],
    );
  }
}

/// The hotkey recorder row: shows the current accelerator and records a new
/// one on the next key press.
///
/// Recording uses hotkey_manager's own recorder, which listens to hardware
/// keys; the result is translated back into the profile's `ctrl+shift+a`
/// string form, which is also what [isScreenshotHotkey] validates.
class _HotkeyEditor extends StatelessWidget {
  const _HotkeyEditor({required this.controller});

  final LocalTransferController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HotKeyRecorder(
            initalHotKey: _toHotKey(controller.screenshotHotkey),
            onHotKeyRecorded: (hotKey) {
              final accelerator = _acceleratorOf(hotKey);
              if (accelerator != null) {
                controller.setScreenshotHotkey(accelerator);
              }
            },
          ),
        ),
        TextButton(
          onPressed: () =>
              controller.setScreenshotHotkey(defaultScreenshotHotkey),
          child: const Text('恢复默认'),
        ),
      ],
    );
  }

  HotKey? _toHotKey(String accelerator) {
    final parts = accelerator.split('+');
    if (parts.length < 2) return null;
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
        default:
          key = _keyOf(part);
      }
    }
    if (key == null) return null;
    return HotKey(key: key, modifiers: modifiers);
  }

  LogicalKeyboardKey? _keyOf(String part) {
    if (part.length == 1) {
      final code = part.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7a) {
        return LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + code - 0x61);
      }
      if (code >= 0x30 && code <= 0x39) {
        return LogicalKeyboardKey(
          LogicalKeyboardKey.digit0.keyId + code - 0x30,
        );
      }
    }
    if (part.startsWith('f')) {
      final n = int.tryParse(part.substring(1));
      if (n != null && n >= 1 && n <= 24) return _functionKey(n);
    }
    return null;
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
    _ => LogicalKeyboardKey.f13,
  };

  /// Translates a recorded [HotKey] back into `modifier+key` form.
  String? _acceleratorOf(HotKey hotKey) {
    final parts = <String>[];
    for (final modifier in hotKey.modifiers ?? const <HotKeyModifier>[]) {
      parts.add(switch (modifier) {
        HotKeyModifier.control => 'ctrl',
        HotKeyModifier.shift => 'shift',
        HotKeyModifier.alt => 'alt',
        HotKeyModifier.meta => 'win',
        _ => '',
      });
    }
    final key = _keyName(hotKey.logicalKey);
    if (key == null) return null;
    parts.add(key);
    final accelerator = parts.where((p) => p.isNotEmpty).join('+');
    return isScreenshotHotkey(accelerator) ? accelerator : null;
  }

  String? _keyName(LogicalKeyboardKey key) {
    final id = key.keyId;
    final a = LogicalKeyboardKey.keyA.keyId;
    if (id >= a && id <= a + 25) {
      return String.fromCharCode(0x61 + id - a);
    }
    final d = LogicalKeyboardKey.digit0.keyId;
    if (id >= d && id <= d + 9) {
      return String.fromCharCode(0x30 + id - d);
    }
    for (var n = 1; n <= 13; n++) {
      if (key == _functionKey(n)) return 'f$n';
    }
    return null;
  }
}

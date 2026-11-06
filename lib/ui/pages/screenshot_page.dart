import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../app/app_controller.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../screenshot/capture_key_names.dart';
import '../screenshot/screenshot_service.dart';

/// The "截图" sub-page under 我的: the feature's on/off switch, the global
/// hotkey that summons the capture overlay, and every key binding that
/// works inside it.
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
                _HotkeyEditor(
                  accelerator: controller.screenshotHotkey,
                  onChanged: controller.setScreenshotHotkey,
                  onReset: () =>
                      controller.setScreenshotHotkey(defaultScreenshotHotkey),
                ),
              ],
            ),
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
                  '截图内快捷键',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  '截图遮罩打开时生效；可以只按一个键，不必带修饰键',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                for (final action in CaptureAction.values)
                  _OverlayKeyRow(action: action, controller: controller),
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

/// One overlay binding: what the action does, the recorder for its key,
/// and a way back to the default.
class _OverlayKeyRow extends StatelessWidget {
  const _OverlayKeyRow({required this.action, required this.controller});

  final CaptureAction action;
  final LocalTransferController controller;

  String get _label => switch (action) {
    CaptureAction.region => '框选区域',
    CaptureAction.window => '窗口截图',
    CaptureAction.full => '全屏截图',
    CaptureAction.copy => '完成（复制）',
    CaptureAction.pin => '钉图',
    CaptureAction.cancel => '取消',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(_label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: _HotkeyEditor(
              accelerator:
                  controller.screenshotCaptureKeys[action] ??
                  defaultCaptureKey(action),
              accepts: isCaptureHotkey,
              onChanged: (accelerator) =>
                  unawaited(_apply(context, accelerator)),
              onReset: () =>
                  unawaited(_apply(context, defaultCaptureKey(action))),
            ),
          ),
        ],
      ),
    );
  }

  /// Applies a recorded binding, telling the user when the profile refuses
  /// it — a collision or the summon chord is only visible as a rejected
  /// future, so it has to be caught here to become a sentence.
  Future<void> _apply(BuildContext context, String accelerator) async {
    try {
      await controller.setScreenshotCaptureKey(action, accelerator);
    } on ArgumentError {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('该快捷键不可用或已被占用')));
      }
    }
  }
}

/// The hotkey recorder row: shows the current accelerator and records a new
/// one on the next key press.
///
/// Recording uses hotkey_manager's own recorder, which listens to hardware
/// keys; the result is translated back into the profile's `ctrl+shift+a`
/// string form, which is also what the validators check.
class _HotkeyEditor extends StatelessWidget {
  const _HotkeyEditor({
    required this.accelerator,
    required this.onChanged,
    this.accepts = isScreenshotHotkey,
    this.onReset,
  });

  /// The binding currently in effect, in `modifier+key` form.
  final String accelerator;

  /// Called with the normalized binding the recorder produced.
  final FutureOr<void> Function(String accelerator) onChanged;

  /// The grammar this row accepts — the global hotkey demands a modifier,
  /// the in-overlay bindings do not.
  final bool Function(String accelerator) accepts;

  /// Returns the binding to its default, when the row offers that.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HotKeyRecorder(
            initalHotKey: _toHotKey(accelerator),
            onHotKeyRecorded: (hotKey) {
              final recorded = _acceleratorOf(hotKey);
              if (recorded != null && accepts(recorded)) {
                onChanged(normalizeCaptureHotkey(recorded)!);
              }
            },
          ),
        ),
        if (onReset != null)
          TextButton(onPressed: onReset, child: const Text('恢复默认')),
      ],
    );
  }

  HotKey? _toHotKey(String accelerator) {
    final modifiers = <HotKeyModifier>[];
    LogicalKeyboardKey? key;
    for (final part in accelerator.split('+')) {
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
          // A second non-modifier part means the string is not a binding
          // this recorder can show; the validators refuse it anyway.
          if (key != null) return null;
          key = captureKeyOf(part);
      }
    }
    if (key == null) return null;
    return HotKey(key: key, modifiers: modifiers);
  }

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
    final key = captureKeyName(hotKey.logicalKey);
    if (key == null) return null;
    parts.add(key);
    return parts.where((p) => p.isNotEmpty).join('+');
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                  '在任意应用中按下该组合键呼出截图遮罩；点击下方按键后按下新组合键即可更改',
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
                  '截图遮罩打开时生效；可以只按一个键，不必带修饰键；点击按键后按下新组合键即可更改',
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

/// The hotkey editor row: shows the current binding and records a new one
/// on tap.
///
/// Recording listens to hardware keys directly rather than going through
/// hotkey_manager's recorder widget: that widget renders its own key caps,
/// and its modifier caps come out as glyphs (`⌃`, `⇧`) that do not say
/// "Ctrl" or "Shift". The row only listens while armed — every row on the
/// page shares the same physical keyboard, so an always-on listener would
/// record every key press into every row at once. The recorded chord is
/// translated into the profile's `ctrl+shift+a` string form — the same
/// form the validators check and [captureHotkeyLabel] renders — so what
/// the row shows is exactly what gets stored.
class _HotkeyEditor extends StatefulWidget {
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

  /// The grammar this row accepts — the global hotkey demands a modifier
  /// (or a bare function key), the in-overlay bindings do not.
  final bool Function(String accelerator) accepts;

  /// Returns the binding to its default, when the row offers that.
  final VoidCallback? onReset;

  @override
  State<_HotkeyEditor> createState() => _HotkeyEditorState();
}

class _HotkeyEditorState extends State<_HotkeyEditor> {
  /// The one row currently listening for a chord. Rows share the physical
  /// keyboard, so arming one must silence the rest — otherwise a single
  /// key press would be recorded into every row on the page.
  static _HotkeyEditorState? _armed;

  bool _recording = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    if (_armed == this) _armed = null;
    super.dispose();
  }

  void _arm() {
    final previous = _armed;
    if (previous != null && previous != this) previous._disarm();
    _armed = this;
    setState(() => _recording = true);
  }

  void _disarm() {
    if (_armed == this) _armed = null;
    if (mounted) setState(() => _recording = false);
  }

  /// Turns a key press into an accelerator candidate while armed.
  ///
  /// Modifier-only presses return false — they are the first half of a
  /// chord, not a binding — and so does any key [captureKeyName] cannot
  /// spell. A bare `escape` disarms instead of recording on rows whose
  /// grammar refuses it, which is the cancel gesture; on rows that accept
  /// `escape` it records like any other key. The candidate is normalized
  /// and then filtered by [widget.accepts]; a refused binding leaves the
  /// display on the effective one rather than showing a promise that was
  /// not kept.
  bool _handleKeyEvent(KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) return false;
    final name = captureKeyName(event.logicalKey);
    if (name == null) return false;
    final keyboard = HardwareKeyboard.instance;
    final recorded = [
      if (keyboard.isControlPressed) 'ctrl',
      if (keyboard.isShiftPressed) 'shift',
      if (keyboard.isAltPressed) 'alt',
      if (keyboard.isMetaPressed) 'win',
      name,
    ].join('+');
    if (recorded == 'escape' && !widget.accepts('escape')) {
      _disarm();
      return true;
    }
    final normalized = normalizeCaptureHotkey(recorded);
    if (normalized != null && widget.accepts(normalized)) {
      _disarm();
      widget.onChanged(normalized);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _recording ? _disarm : _arm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _recording
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).canvasColor,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  _recording
                      ? '按下组合键…'
                      : captureHotkeyLabel(widget.accelerator),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.onReset != null)
          TextButton(onPressed: widget.onReset, child: const Text('恢复默认')),
      ],
    );
  }
}

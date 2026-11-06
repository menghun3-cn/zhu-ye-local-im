import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/core.dart';
import '../native/win_desktop.dart';
import '../screenshot_window.dart';

/// A pinned screenshot: a small always-on-top window floating over other
/// apps, exactly what Snipaste's pin is for.
///
/// The window is frameless and transparent; the image itself is the only
/// visible content, so dragging works anywhere on it. A right-click menu
/// carries copy/save/topmost/click-through/close, and double-click opens the
/// annotation editor on this pin's image.
class PinWindow extends StatefulWidget {
  const PinWindow({super.key, required this.args});

  final ScreenshotWindowArgs args;

  @override
  State<PinWindow> createState() => _PinWindowState();
}

class _PinWindowState extends State<PinWindow> {
  PinStore? _store;
  PinRecord? _record;
  Uint8List? _png;
  bool _clickThrough = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  Future<void> _enter() async {
    await windowManager.ensureInitialized();
    final path = widget.args.pinPath;
    final id = widget.args.pinId;
    if (path == null || id == null) {
      await windowManager.destroy();
      return;
    }
    _store = PinStore(path);
    _store!.reload();
    for (final pin in await _store!.pins()) {
      if (pin.id == id) _record = pin;
    }
    if (_record == null) {
      await windowManager.destroy();
      return;
    }
    final file = File(_record!.pathIn(path));
    if (!await file.exists()) {
      await windowManager.destroy();
      return;
    }
    _png = await file.readAsBytes();
    _clickThrough = _record!.clickThrough;

    final dpr = windowManager.getDevicePixelRatio();
    final width = _record!.width / dpr;
    final height = _record!.height / dpr;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(width, height),
        title: _title,
        alwaysOnTop: _record!.alwaysOnTop,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.setPosition(
          Offset(_record!.x / dpr, _record!.y / dpr),
        );
        await windowManager.setResizable(true);
        await windowManager.setBackgroundColor(Colors.transparent);
        await windowManager.show();
      },
    );
    await windowManager.setAlwaysOnTop(_record!.alwaysOnTop);
    if (_clickThrough) await _applyClickThrough(true);
    if (mounted) setState(() {});
  }

  Future<void> _applyClickThrough(bool enabled) async {
    // Every pin is an engine in the same process, so the HWND cannot come
    // from the process or the plugin's windowId — it comes from the unique
    // title each pin sets on itself.
    final hwnd = hwndForTitle(_title);
    if (hwnd != null) setClickThrough(hwnd, enabled);
  }

  String get _title => '钉图 ${widget.args.pinId}';

  Future<void> _saveState() async {
    final record = _record;
    final store = _store;
    if (record == null || store == null) return;
    await store.update(
      record.copyWith(
        alwaysOnTop: await windowManager.isAlwaysOnTop(),
        clickThrough: _clickThrough,
      ),
    );
  }

  Future<void> _toggleTopmost() async {
    final next = !(await windowManager.isAlwaysOnTop());
    await windowManager.setAlwaysOnTop(next);
    _record = _record?.copyWith(alwaysOnTop: next);
    await _saveState();
    if (mounted) setState(() {});
  }

  Future<void> _toggleClickThrough() async {
    _clickThrough = !_clickThrough;
    await _applyClickThrough(_clickThrough);
    _record = _record?.copyWith(clickThrough: _clickThrough);
    await _saveState();
    if (mounted) setState(() {});
  }

  Future<void> _copy() async {
    final png = _png;
    if (png != null) copyToClipboard(png);
  }

  Future<void> _saveAs() async {
    final png = _png;
    if (png == null) return;
    final location = await getSaveLocation(
      suggestedName: 'pin-${DateTime.now().millisecondsSinceEpoch}.png',
      acceptedTypeGroups: [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    final path = location?.path;
    if (path == null) return;
    await File(path).writeAsBytes(png, flush: true);
  }

  Future<void> _edit() async {
    await openScreenshotWindow(
      ScreenshotWindowKind.editor,
      pinPath: widget.args.pinPath,
      pinId: widget.args.pinId,
    );
  }

  Future<void> _close() async {
    await _saveState();
    await _store?.remove(_record!);
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final png = _png;
    if (png == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return MouseRegion(
      cursor: _clickThrough ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: _edit,
        onSecondaryTapUp: (details) => _menu(details.globalPosition),
        child: Image.memory(png, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }

  void _menu(Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('复制')),
        const PopupMenuItem(value: 'save', child: Text('另存为')),
        const PopupMenuItem(value: 'topmost', child: Text('置顶切换')),
        const PopupMenuItem(value: 'through', child: Text('鼠标穿透')),
        const PopupMenuItem(value: 'edit', child: Text('标注')),
        const PopupMenuItem(value: 'close', child: Text('关闭')),
      ],
    ).then((value) {
      switch (value) {
        case 'copy':
          _copy();
        case 'save':
          _saveAs();
        case 'topmost':
          _toggleTopmost();
        case 'through':
          _toggleClickThrough();
        case 'edit':
          _edit();
        case 'close':
          _close();
      }
    });
  }
}

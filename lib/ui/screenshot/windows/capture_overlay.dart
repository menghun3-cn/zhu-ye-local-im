import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/core.dart';
import '../native/win_desktop.dart';
import '../screenshot_window.dart';

/// What the capture overlay decided to do with a finished screenshot.
enum CaptureOutcome { copied, pinned, cancelled }

/// The pipeline every capture mode shares: hide the overlay, take the
/// pixels, file them, put them on the clipboard, and open whatever the user
/// asked for next.
///
/// Lives here rather than inside the overlay widget because the sequence —
/// hide, capture, show — is the same whether the pixels came from a dragged
/// rect, a window or the whole screen, and because the window must be gone
/// *before* the pixels are read or it would photograph itself.
Future<CaptureOutcome> finishCapture({
  required ScreenshotWindowArgs args,
  required Uint8List? png,
  required int width,
  required int height,
  required bool pin,
}) async {
  if (png == null) return CaptureOutcome.cancelled;

  final libraryPath = args.libraryPath;
  if (libraryPath != null) {
    final library = ScreenshotLibrary(libraryPath);
    await library.add(png: png, width: width, height: height);
  }
  copyToClipboard(png);

  if (pin && args.pinPath != null) {
    final store = PinStore(args.pinPath!);
    final record = await store.add(png: png);
    await openScreenshotWindow(
      ScreenshotWindowKind.pin,
      libraryPath: libraryPath,
      pinPath: args.pinPath,
      pinId: record.id,
    );
  }
  if (args.libraryPath != null) {
    await openScreenshotWindow(
      ScreenshotWindowKind.history,
      libraryPath: args.libraryPath,
      pinPath: args.pinPath,
    );
  }
  return pin ? CaptureOutcome.pinned : CaptureOutcome.copied;
}

/// The fullscreen overlay the hotkey opens: dimmed desktop, drag a region,
/// or switch to window/full modes, then copy — optionally pinning.
///
/// One window covers the whole virtual screen so a selection can cross
/// monitors; it is always-on-top, skip-taskbar, frameless and transparent
/// around the selection. All coordinates inside are physical pixels —
/// converted once from Flutter's logical ones using the window's DPI.
class CaptureOverlay extends StatefulWidget {
  const CaptureOverlay({super.key, required this.args});

  final ScreenshotWindowArgs args;

  @override
  State<CaptureOverlay> createState() => _CaptureOverlayState();
}

enum _Mode { region, window, full }

class _CaptureOverlayState extends State<CaptureOverlay> {
  _Mode _mode = _Mode.region;
  Rect? _selection;
  ForeignWindow? _hoveredWindow;
  bool _dragging = false;
  Offset? _dragStart;
  double _dpr = 1;
  Rect _screen = Rect.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  Future<void> _enter() async {
    await windowManager.ensureInitialized();
    _dpr = windowManager.getDevicePixelRatio();
    _screen = virtualScreen();
    // The window covers the virtual screen exactly: its position and size
    // are the physical rect divided by this window's DPI, because
    // window_manager speaks logical pixels.
    await windowManager.setPosition(
      Offset(_screen.left / _dpr, _screen.top / _dpr),
    );
    await windowManager.setSize(
      Size(_screen.width / _dpr, _screen.height / _dpr),
    );
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.show();
    await windowManager.focus();
    if (mounted) setState(() {});
  }

  /// Flutter-local logical point → physical screen pixel.
  Offset _toPhysical(Offset local) =>
      Offset(_screen.left + local.dx * _dpr, _screen.top + local.dy * _dpr);

  Rect? _toScreenRect(Offset a, Offset b) {
    final pa = _toPhysical(a);
    final pb = _toPhysical(b);
    return Rect.fromPoints(pa, pb);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_mode == _Mode.window) {
      final window = windowAtPoint(_toPhysical(event.localPosition));
      if (window != null) {
        setState(() => _selection = window.bounds);
      }
      return;
    }
    if (_mode == _Mode.full) return;
    _dragging = true;
    _dragStart = event.localPosition;
    setState(() => _selection = null);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_mode == _Mode.window) {
      final window = windowAtPoint(_toPhysical(event.localPosition));
      if (window?.hwnd != _hoveredWindow?.hwnd) {
        setState(() => _hoveredWindow = window);
      }
      return;
    }
    if (!_dragging || _dragStart == null) return;
    setState(
      () => _selection = _toScreenRect(_dragStart!, event.localPosition),
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_mode != _Mode.region) return;
    _dragging = false;
    _dragStart = null;
    final selection = _selection;
    if (selection != null && selection.width < 3 && selection.height < 3) {
      setState(() => _selection = null);
    }
  }

  Rect? get _captureRect {
    if (_mode == _Mode.full) return _screen;
    final selection = _selection;
    if (selection == null) return null;
    return selection.intersect(_screen);
  }

  Future<void> _capture({required bool pin}) async {
    final rect = _captureRect;
    if (rect == null || rect.isEmpty) return;
    await windowManager.hide();
    // The overlay must be *gone*, not merely transparent, before the pixels
    // are read — a hidden window still occupies the screen until the hide
    // has been composited, and one frame is the cheapest reliable wait.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    Uint8List? png;
    var width = 0;
    var height = 0;
    if (_mode == _Mode.window && _hoveredWindow != null && _selection == null) {
      // A window capture uses the window under the cursor even when the
      // selection was never confirmed — PrintWindow reads the window's own
      // pixels, so occlusion is not a problem.
      final hwnd = _hoveredWindow!.hwnd;
      png = captureWindow(hwnd);
      if (png != null) {
        final size = _pngSize(png);
        width = size.width;
        height = size.height;
      }
    } else {
      png = captureRect(rect);
      width = rect.width.round();
      height = rect.height.round();
    }
    await finishCapture(
      args: widget.args,
      png: png,
      width: width,
      height: height,
      pin: pin,
    );
    await windowManager.destroy();
  }

  ({int width, int height}) _pngSize(Uint8List png) {
    // PNG's IHDR is always the first chunk: 8-byte signature, 4-byte length,
    // 'IHDR', then width and height as big-endian uint32.
    if (png.length < 24) return (width: 0, height: 0);
    int be32(int at) =>
        (png[at] << 24) |
        (png[at + 1] << 16) |
        (png[at + 2] << 8) |
        png[at + 3];
    return (width: be32(16), height: be32(20));
  }

  void _cancel() => windowManager.destroy();

  /// Physical screen rect → this window's local logical rect.
  Rect _toLocal(Rect physical) => Rect.fromLTRB(
    (physical.left - _screen.left) / _dpr,
    (physical.top - _screen.top) / _dpr,
    (physical.right - _screen.left) / _dpr,
    (physical.bottom - _screen.top) / _dpr,
  );

  @override
  Widget build(BuildContext context) {
    final localSelection = _selection == null ? null : _toLocal(_selection!);
    final localHover = _mode == _Mode.window && _hoveredWindow != null
        ? _toLocal(_hoveredWindow!.bounds)
        : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        child: CustomPaint(
          painter: _OverlayPainter(
            selection: localSelection,
            hoveredWindow: localHover,
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _Toolbar(
                    mode: _mode,
                    canCapture: _captureRect != null || _mode == _Mode.full,
                    onMode: (mode) => setState(() {
                      _mode = mode;
                      _selection = null;
                      _hoveredWindow = null;
                    }),
                    onCopy: () => _capture(pin: false),
                    onPin: () => _capture(pin: true),
                    onCancel: _cancel,
                  ),
                ),
              ),
              if (_selection != null && _mode == _Mode.region)
                Positioned(
                  left: (_selection!.left - _screen.left) / _dpr + 8,
                  top: (_selection!.top - _screen.top) / _dpr + 8,
                  child: Text(
                    '${_selection!.width.round()} × ${_selection!.height.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      shadows: [Shadow(blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.mode,
    required this.canCapture,
    required this.onMode,
    required this.onCopy,
    required this.onPin,
    required this.onCancel,
  });

  final _Mode mode;
  final bool canCapture;
  final ValueChanged<_Mode> onMode;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    Widget modeButton(_Mode value, String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: () => onMode(value),
        style: TextButton.styleFrom(
          backgroundColor: mode == value
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            modeButton(_Mode.region, '框选'),
            modeButton(_Mode.window, '窗口'),
            modeButton(_Mode.full, '全屏'),
            const SizedBox(width: 8),
            const VerticalDivider(color: Colors.white38, width: 16),
            FilledButton(
              onPressed: canCapture ? onCopy : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('完成', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: canCapture ? onPin : null,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('钉图', style: TextStyle(fontSize: 13)),
            ),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('取消', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dimming layer plus the selection rectangle.
///
/// Everything it draws is already in window-local logical coordinates — the
/// widget converts once, where the DPI is known.
class _OverlayPainter extends CustomPainter {
  const _OverlayPainter({required this.selection, required this.hoveredWindow});

  /// The dragged selection, window-local logical.
  final Rect? selection;

  /// The window under the cursor in window mode, window-local logical.
  final Rect? hoveredWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final highlight = Paint()
      ..color = const Color(0xFF07C160)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rect = selection ?? hoveredWindow;
    if (rect == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    // Four dimmed bands around the selection rather than a clipped overlay:
    // the selection itself stays fully bright, which is the point of the
    // gesture.
    final local = rect;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, local.top.clamp(0, size.height)),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        local.bottom.clamp(0, size.height),
        size.width,
        size.height - local.bottom.clamp(0, size.height),
      ),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        local.top.clamp(0, size.height),
        local.left.clamp(0, size.width),
        local.height,
      ),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        local.right.clamp(0, size.width),
        local.top.clamp(0, size.height),
        size.width - local.right.clamp(0, size.width),
        local.height,
      ),
      dim,
    );
    canvas.drawRect(local, highlight);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.selection != selection || old.hoveredWindow != hoveredWindow;
}

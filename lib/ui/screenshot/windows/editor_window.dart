import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/core.dart';
import '../screenshot_window.dart';

/// One annotation stroke, in image-pixel coordinates.
final class _Element {
  _Element({
    required this.tool,
    required this.color,
    this.points = const [],
    this.text = '',
    this.width = 3,
  });

  /// arrow | rect | brush | text | number
  final String tool;
  final Color color;
  final List<Offset> points;
  final String text;
  final double width;

  _Element copyWith({List<Offset>? points, String? text}) => _Element(
    tool: tool,
    color: color,
    points: points ?? this.points,
    text: text ?? this.text,
    width: width,
  );
}

/// The annotation editor: the screenshot plus Snipaste's markup tools —
/// arrow, rectangle, freehand brush, text and numbered markers.
///
/// Edits a history entry or a pin in place: on 完成 the annotated image is
/// re-encoded over the same file, so history, pins and the clipboard stay
/// consistent without a second copy. The window is sized to the image at a
/// sane scale rather than the raw pixel size, which can be a 4K capture.
class AnnotationEditor extends StatefulWidget {
  const AnnotationEditor({super.key, required this.args});

  final ScreenshotWindowArgs args;

  @override
  State<AnnotationEditor> createState() => _AnnotationEditorState();
}

enum _Tool { select, arrow, rect, brush, text, number }

class _AnnotationEditorState extends State<AnnotationEditor> {
  ui.Image? _image;
  Uint8List? _png;
  String? _targetPath;
  PinStore? _pinStore;
  PinRecord? _pinRecord;
  ScreenshotLibrary? _library;
  ScreenshotEntry? _entry;

  final List<_Element> _elements = [];
  _Tool _tool = _Tool.brush;
  int _number = 1;
  Offset? _draftStart;
  final List<Offset> _draftPoints = [];
  static const _palette = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFFB300),
    Color(0xFF8E24AA),
    Color(0xFFFFFFFF),
  ];
  Color _color = _palette[0];
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  Future<void> _enter() async {
    await windowManager.ensureInitialized();
    final args = widget.args;
    _pinStore = args.pinPath == null ? null : PinStore(args.pinPath!);
    if (_pinStore != null) _pinStore!.reload();
    _library = args.libraryPath == null
        ? null
        : ScreenshotLibrary(args.libraryPath!);

    if (args.pinId != null && _pinStore != null) {
      _pinStore!.reload();
      for (final pin in await _pinStore!.pins()) {
        if (pin.id == args.pinId) _pinRecord = pin;
      }
      if (_pinRecord != null) {
        _targetPath = _pinRecord!.pathIn(_pinStore!.directory);
      }
    } else if (args.entryId != null && _library != null) {
      _library!.reload();
      final entries = await _library!.entries();
      for (final e in entries) {
        if (e.id == args.entryId) _entry = e;
      }
      if (_entry != null) _targetPath = _entry!.pathIn(_library!.directory);
    }
    if (_targetPath == null) {
      await windowManager.destroy();
      return;
    }
    _png = await File(_targetPath!).readAsBytes();
    final codec = await ui.instantiateImageCodec(_png!);
    _image = (await codec.getNextFrame()).image;

    // Fit the image inside ~80% of the primary screen, capped at 1:1.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logical = view.physicalSize / view.devicePixelRatio;
    final maxW = logical.width * 0.8;
    final maxH = logical.height * 0.8;
    final iw = _image!.width.toDouble();
    final ih = _image!.height.toDouble();
    _scale = (iw > maxW || ih > maxH)
        ? (iw / maxW > ih / maxH ? maxW / iw : maxH / ih)
        : 1.0;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(iw * _scale + 16, ih * _scale + 96),
        title: '标注',
        minimumSize: const Size(320, 240),
      ),
      () async {
        await windowManager.center();
        await windowManager.show();
        await windowManager.focus();
      },
    );
    if (mounted) setState(() {});
  }

  Offset _toImage(Offset local) => Offset(local.dx / _scale, local.dy / _scale);

  void _onPointerDown(PointerDownEvent e) {
    final p = _toImage(e.localPosition);
    switch (_tool) {
      case _Tool.brush:
        _draftPoints.add(p);
      case _Tool.arrow || _Tool.rect:
        _draftStart = p;
      case _Tool.number:
        _elements.add(
          _Element(
            tool: 'number',
            color: _color,
            points: [p],
            text: '$_number',
          ),
        );
        _number++;
      case _Tool.text:
        _promptText(p);
      case _Tool.select:
        break;
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_draftPoints.isNotEmpty) _draftPoints.add(_toImage(e.localPosition));
    if (_draftStart != null) {
      _draftPoints
        ..clear()
        ..addAll([_draftStart!, _toImage(e.localPosition)]);
    }
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_draftPoints.isNotEmpty) {
      final points = List<Offset>.of(_draftPoints);
      final tool = switch (_tool) {
        _Tool.arrow => 'arrow',
        _Tool.rect => 'rect',
        _ => 'brush',
      };
      _elements.add(_Element(tool: tool, color: _color, points: points));
      _draftPoints.clear();
      _draftStart = null;
      setState(() {});
    }
  }

  void _promptText(Offset at) {
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文字标注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入文字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((text) {
      if (text == null || text.isEmpty) return;
      setState(() {
        _elements.add(
          _Element(tool: 'text', color: _color, points: [at], text: text),
        );
      });
    });
  }

  void _drawElement(Canvas canvas, _Element e, double scale) {
    final paint = Paint()
      ..color = e.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.width * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (e.tool) {
      case 'brush':
        if (e.points.length > 1) {
          final path = Path()
            ..moveTo(e.points.first.dx * scale, e.points.first.dy * scale);
          for (final p in e.points.skip(1)) {
            path.lineTo(p.dx * scale, p.dy * scale);
          }
          canvas.drawPath(path, paint);
        }
      case 'rect':
        if (e.points.length >= 2) {
          canvas.drawRect(
            Rect.fromPoints(e.points.first * scale, e.points.last * scale),
            paint,
          );
        }
      case 'arrow':
        if (e.points.length >= 2) {
          final a = e.points.first * scale;
          final b = e.points.last * scale;
          canvas.drawLine(a, b, paint);
          final angle = (b - a).direction;
          const head = 12.0;
          canvas.drawLine(
            b,
            b + Offset.fromDirection(angle + 2.6) * head,
            paint,
          );
          canvas.drawLine(
            b,
            b + Offset.fromDirection(angle - 2.6) * head,
            paint,
          );
        }
      case 'number':
        if (e.points.isNotEmpty) {
          final center = e.points.first * scale;
          final r = 11.0 * scale;
          canvas.drawCircle(center, r, Paint()..color = e.color);
          final tp = TextPainter(
            text: TextSpan(
              text: e.text,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
        }
      case 'text':
        if (e.points.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: e.text,
              style: TextStyle(
                color: e.color,
                fontSize: 18 * scale,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          tp.paint(canvas, e.points.first * scale);
        }
    }
  }

  Future<void> _save() async {
    final image = _image;
    final target = _targetPath;
    if (image == null || target == null) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());
    for (final e in _elements) {
      _drawElement(canvas, e, 1.0);
    }
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(image.width, image.height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    picture.dispose();
    if (data == null) return;
    await File(target).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    if (_pinRecord != null && _pinStore != null) {
      await _pinStore!.update(_pinRecord!);
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Column(
        children: [
          _toolbar(),
          Expanded(
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  child: SizedBox(
                    width: image.width * _scale,
                    height: image.height * _scale,
                    child: CustomPaint(
                      painter: _AnnotationPainter(
                        image: image,
                        elements: _elements,
                        draft: _draftPoints,
                        draftTool: switch (_tool) {
                          _Tool.arrow => 'arrow',
                          _Tool.rect => 'rect',
                          _ => 'brush',
                        },
                        color: _color,
                        scale: _scale,
                        drawElement: _drawElement,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    Widget tool(_Tool t, IconData icon, String tip) => IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tip,
      isSelected: _tool == t,
      onPressed: () => setState(() => _tool = t),
      style: IconButton.styleFrom(
        backgroundColor: _tool == t
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
      ),
    );
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            tool(_Tool.brush, Icons.brush, '画笔'),
            tool(_Tool.arrow, Icons.arrow_outward, '箭头'),
            tool(_Tool.rect, Icons.crop_square, '矩形'),
            tool(_Tool.text, Icons.text_fields, '文字'),
            tool(_Tool.number, Icons.pin, '序号'),
            tool(_Tool.select, Icons.near_me, '选择'),
            const SizedBox(width: 12),
            for (final c in _palette)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                      width: _color == c ? 2 : 1,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            if (_elements.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.undo, size: 18),
                tooltip: '撤销',
                onPressed: () => setState(() => _elements.removeLast()),
              ),
            FilledButton(onPressed: _save, child: const Text('完成')),
            TextButton(
              onPressed: () => windowManager.destroy(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({
    required this.image,
    required this.elements,
    required this.draft,
    required this.draftTool,
    required this.color,
    required this.scale,
    required this.drawElement,
  });

  final ui.Image image;
  final List<_Element> elements;
  final List<Offset> draft;
  final String draftTool;
  final Color color;
  final double scale;
  final void Function(Canvas, _Element, double) drawElement;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
    for (final e in elements) {
      drawElement(canvas, e, scale);
    }
    if (draft.isNotEmpty) {
      drawElement(
        canvas,
        _Element(tool: draftTool, color: color, points: draft),
        scale,
      );
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter old) =>
      old.elements != elements ||
      old.draft != draft ||
      old.color != color ||
      old.scale != scale;
}

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/core.dart';
import '../native/win_desktop.dart';
import '../screenshot_window.dart';

/// The screenshot history window: a grid of thumbnails, each with the
/// actions Snipaste puts on a history item — pin, annotate, copy, save,
/// delete.
///
/// Reads the library directory named in its window arguments and reloads it
/// every time the window is shown, because other windows — the overlay, the
/// editor — write to the same directory from their own engines.
class HistoryWindow extends StatefulWidget {
  const HistoryWindow({super.key, required this.args});

  final ScreenshotWindowArgs args;

  @override
  State<HistoryWindow> createState() => _HistoryWindowState();
}

class _HistoryWindowState extends State<HistoryWindow> {
  ScreenshotLibrary? _library;
  List<ScreenshotEntry> _entries = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  Future<void> _enter() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('截图历史');
    final path = widget.args.libraryPath;
    if (path != null) _library = ScreenshotLibrary(path);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: Size(640, 480), center: true),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await _reload();
  }

  Future<void> _reload() async {
    final library = _library;
    if (library == null) {
      setState(() => _loaded = true);
      return;
    }
    library.reload();
    final entries = await library.entries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loaded = true;
      });
    }
  }

  Future<void> _pin(ScreenshotEntry entry) async {
    final library = _library;
    final pinPath = widget.args.pinPath;
    if (library == null || pinPath == null) return;
    final png = await library.readPng(entry);
    if (png == null) return;
    final store = PinStore(pinPath);
    final record = await store.add(png: png);
    await openScreenshotWindow(
      ScreenshotWindowKind.pin,
      libraryPath: widget.args.libraryPath,
      pinPath: pinPath,
      pinId: record.id,
    );
  }

  Future<void> _edit(ScreenshotEntry entry) async {
    await openScreenshotWindow(
      ScreenshotWindowKind.editor,
      libraryPath: widget.args.libraryPath,
      pinPath: widget.args.pinPath,
      entryId: entry.id,
    );
  }

  Future<void> _copy(ScreenshotEntry entry) async {
    final png = await _library?.readPng(entry);
    if (png != null) copyToClipboard(png);
  }

  Future<void> _saveAs(ScreenshotEntry entry) async {
    final png = await _library?.readPng(entry);
    if (png == null) return;
    final name = 'screenshot-${entry.createdAt.millisecondsSinceEpoch}.png';
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    final path = location?.path;
    if (path == null) return;
    await File(path).writeAsBytes(png, flush: true);
  }

  Future<void> _remove(ScreenshotEntry entry) async {
    await _library?.remove(entry);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('截图历史'),
        actions: [
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _entries.isEmpty
                ? null
                : () async {
                    for (final entry in _entries) {
                      await _library?.remove(entry);
                    }
                    await _reload();
                  },
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const Center(child: Text('还没有截图'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return _HistoryTile(
                  entry: entry,
                  library: _library!,
                  onPin: () => _pin(entry),
                  onEdit: () => _edit(entry),
                  onCopy: () => _copy(entry),
                  onSave: () => _saveAs(entry),
                  onDelete: () => _remove(entry),
                );
              },
            ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({
    required this.entry,
    required this.library,
    required this.onPin,
    required this.onEdit,
    required this.onCopy,
    required this.onSave,
    required this.onDelete,
  });

  final ScreenshotEntry entry;
  final ScreenshotLibrary library;
  final VoidCallback onPin;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    widget.library.readPng(widget.entry).then((png) {
      if (mounted && png != null) setState(() => _png = png);
    });
  }

  @override
  Widget build(BuildContext context) {
    final png = _png;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onEdit,
        onSecondaryTapUp: (details) => _menu(details.globalPosition),
        child: Column(
          children: [
            Expanded(
              child: png == null
                  ? const Center(child: CircularProgressIndicator())
                  : Image.memory(png, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _action(Icons.push_pin_outlined, '钉图', widget.onPin),
                  _action(Icons.edit_outlined, '标注', widget.onEdit),
                  _action(Icons.copy_outlined, '复制', widget.onCopy),
                  _action(Icons.save_alt, '保存', widget.onSave),
                  _action(Icons.delete_outline, '删除', widget.onDelete),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String tip, VoidCallback onTap) => IconButton(
    icon: Icon(icon, size: 16),
    tooltip: tip,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    onPressed: onTap,
  );

  void _menu(Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'pin', child: Text('钉图')),
        PopupMenuItem(value: 'edit', child: Text('标注')),
        PopupMenuItem(value: 'copy', child: Text('复制')),
        PopupMenuItem(value: 'save', child: Text('另存为')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ).then((value) {
      switch (value) {
        case 'pin':
          widget.onPin();
        case 'edit':
          widget.onEdit();
        case 'copy':
          widget.onCopy();
        case 'save':
          widget.onSave();
        case 'delete':
          widget.onDelete();
      }
    });
  }
}

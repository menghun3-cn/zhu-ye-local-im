import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'screenshot_entry.dart';

/// Where this Device's screenshot history lives on disk.
///
/// One directory holds `index.json` plus one PNG per entry. The index is the
/// only file rewritten often; images are write-once, so a crash mid-capture
/// can strand a PNG but never corrupts the list — an unreferenced PNG is
/// swept on the next [load], a referenced one that is missing is dropped
/// from the index rather than left as a dead thumbnail.
///
/// Bounded at [maxEntries]: adding past the cap evicts the oldest, which is
/// also what keeps a folder of screenshots from growing without limit on a
/// machine that never cleans it.
final class ScreenshotLibrary {
  /// A library over [directory], created on first write.
  ScreenshotLibrary(this.directory, {this.maxEntries = 20});

  /// The directory `index.json` and the PNGs live in.
  final String directory;

  /// How many entries the history keeps.
  final int maxEntries;

  /// The index file's name inside [directory].
  static const indexFileName = 'index.json';

  /// The pins' file name inside [directory].
  static const pinsFileName = 'pins.json';

  List<ScreenshotEntry>? _entries;

  /// Every entry, newest first.
  ///
  /// Cached per instance, which is per window engine: another window may have
  /// added or removed entries since this one last looked, so a surface that
  /// is about to *show* the list calls [reload] first rather than trusting
  /// what it cached the last time it drew.
  Future<List<ScreenshotEntry>> entries() async {
    final cached = _entries;
    if (cached != null) return List.unmodifiable(cached);
    _entries = await _load();
    return List.unmodifiable(_entries!);
  }

  /// Drops the cache so the next [entries] reads the directory again.
  void reload() => _entries = null;

  /// Records [png] as a new entry and returns it.
  ///
  /// [width] and [height] are the image's pixel size; the caller already
  /// knows them from the capture and pays nothing to say so.
  Future<ScreenshotEntry> add({
    required List<int> png,
    required int width,
    required int height,
    DateTime? at,
    String? id,
  }) async {
    final newId = id ?? _newId();
    final resolved = ScreenshotEntry(
      id: newId,
      fileName: '$newId.png',
      createdAt: (at ?? DateTime.now()).toUtc(),
      width: width,
      height: height,
    );
    await Directory(directory).create(recursive: true);
    await File(resolved.pathIn(directory)).writeAsBytes(png, flush: true);
    final list = await entries();
    _entries = [resolved, ...list];
    if (_entries!.length > maxEntries) {
      _entries = _entries!.sublist(0, maxEntries);
    }
    // Evict before saving: an entry past the cap must lose its file too, or
    // the directory slowly fills with images nothing points at.
    await _evict(list);
    await _save();
    return resolved;
  }

  /// Reads an entry's PNG bytes, or null when the file is gone.
  Future<Uint8List?> readPng(ScreenshotEntry entry) async {
    final file = File(entry.pathIn(directory));
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Removes [entry] and its file.
  Future<void> remove(ScreenshotEntry entry) async {
    final list = await entries();
    _entries = [
      for (final item in list)
        if (item.id != entry.id) item,
    ];
    await _save();
    await _deleteFile(entry.fileName);
  }

  /// Replaces an entry's pixels in place — what the annotation editor does
  /// when the user marks up a history image.
  Future<void> replacePng(ScreenshotEntry entry, List<int> png) async {
    await File(entry.pathIn(directory)).writeAsBytes(png, flush: true);
  }

  Future<List<ScreenshotEntry>> _load() async {
    final file = File('$directory/$indexFileName');
    if (!await file.exists()) {
      await _sweepOrphans(const []);
      return const [];
    }
    List<ScreenshotEntry> decoded;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        throw const FormatException('the index is a JSON array');
      }
      decoded = [
        for (final item in raw)
          if (item is Map)
            ScreenshotEntry.fromJson(item.cast<String, Object?>()),
      ];
    } on Object {
      // A damaged index is not worth a crash: the PNGs are still on disk and
      // a fresh index is cheaper than a startup failure.
      decoded = const [];
    }
    final kept = <ScreenshotEntry>[];
    for (final entry in decoded) {
      if (await File(entry.pathIn(directory)).exists()) kept.add(entry);
    }
    await _sweepOrphans(kept);
    return kept;
  }

  /// Deletes PNGs no entry points at.
  Future<void> _sweepOrphans(List<ScreenshotEntry> kept) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return;
    final live = {for (final entry in kept) entry.fileName};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.png') && !live.contains(name)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // A file another process holds is left for the next sweep.
        }
      }
    }
  }

  /// Drops the files of entries evicted by the cap.
  Future<void> _evict(List<ScreenshotEntry> previous) async {
    final kept = {for (final e in _entries!) e.id};
    for (final entry in previous) {
      if (!kept.contains(entry.id)) await _deleteFile(entry.fileName);
    }
  }

  Future<void> _deleteFile(String fileName) async {
    try {
      await File('$directory/$fileName').delete();
    } on FileSystemException {
      // Already gone is the goal state.
    }
  }

  Future<void> _save() async {
    final file = File('$directory/$indexFileName');
    await Directory(directory).create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert([for (final entry in _entries!) entry.toJson()]),
      flush: true,
    );
  }

  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random.secure().nextInt(0xFFFFFF).toRadixString(36);
    return '$stamp-$random';
  }
}

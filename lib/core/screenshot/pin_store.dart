import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'pin_record.dart';

/// Where this Device's pinned images live on disk.
///
/// Sibling of [ScreenshotLibrary]'s directory: `pins.json` plus one PNG per
/// pin. The store owns both the list and the files, because a pin whose file
/// is gone is a window that can only draw a placeholder — the record and the
/// pixels have to be forgotten together.
final class PinStore {
  /// A store over [directory], created on first write.
  PinStore(this.directory);

  /// The directory `pins.json` and the pin PNGs live in.
  final String directory;

  static const indexFileName = 'pins.json';

  List<PinRecord>? _pins;

  /// Every pin, in placement order.
  Future<List<PinRecord>> pins() async {
    final cached = _pins;
    if (cached != null) return List.unmodifiable(cached);
    _pins = await _load();
    return List.unmodifiable(_pins!);
  }

  /// Drops the cache so the next [pins] reads the directory again.
  void reload() => _pins = null;

  /// Writes [png] as a new pin and returns its record.
  ///
  /// The record starts with no geometry: the pin window decides where it
  /// lands and how large it opens, then writes the real bounds back through
  /// [update]. A screenshot's pixel size is not a window size — at any DPI
  /// other than 96 the two disagree.
  Future<PinRecord> add({
    required List<int> png,
    DateTime? at,
    String? id,
  }) async {
    final newId = id ?? _newId();
    final record = PinRecord(
      id: newId,
      fileName: '$newId.png',
      createdAt: (at ?? DateTime.now()).toUtc(),
    );
    await Directory(directory).create(recursive: true);
    await File(record.pathIn(directory)).writeAsBytes(png, flush: true);
    final list = await pins();
    _pins = [...list, record];
    await _save();
    return record;
  }

  /// Reads a pin's PNG bytes, or null when the file is gone.
  Future<Uint8List?> readPng(PinRecord pin) async {
    final file = File(pin.pathIn(directory));
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Persists a pin's new window state.
  Future<void> update(PinRecord pin) async {
    final list = await pins();
    _pins = [for (final item in list) item.id == pin.id ? pin : item];
    await _save();
  }

  /// Replaces a pin's pixels — what the annotation editor does when a pinned
  /// image is marked up.
  Future<void> replacePng(PinRecord pin, List<int> png) async {
    await File(pin.pathIn(directory)).writeAsBytes(png, flush: true);
  }

  /// Removes [pin] and its file.
  Future<void> remove(PinRecord pin) async {
    final list = await pins();
    _pins = [
      for (final item in list)
        if (item.id != pin.id) item,
    ];
    await _save();
    try {
      await File(pin.pathIn(directory)).delete();
    } on FileSystemException {
      // Already gone is the goal state.
    }
  }

  Future<List<PinRecord>> _load() async {
    final file = File('$directory/$indexFileName');
    if (!await file.exists()) return const [];
    List<PinRecord> decoded;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        throw const FormatException('the pins index is a JSON array');
      }
      decoded = [
        for (final item in raw)
          if (item is Map) PinRecord.fromJson(item.cast<String, Object?>()),
      ];
    } on Object {
      decoded = const [];
    }
    final kept = <PinRecord>[];
    for (final pin in decoded) {
      if (await File(pin.pathIn(directory)).exists()) kept.add(pin);
    }
    // Forget records whose file is gone rather than drawing dead pins.
    if (kept.length != decoded.length) {
      _pins = kept;
      await _save();
    }
    return kept;
  }

  Future<void> _save() async {
    final file = File('$directory/$indexFileName');
    await Directory(directory).create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert([for (final pin in _pins!) pin.toJson()]),
      flush: true,
    );
  }

  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random.secure().nextInt(0xFFFFFF).toRadixString(36);
    return 'pin-$stamp-$random';
  }
}

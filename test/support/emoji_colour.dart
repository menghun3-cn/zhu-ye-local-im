/// Whether the faces the composer offers are drawn in colour.
///
/// The composer offers Unicode code points, and a code point is a fact
/// about Unicode rather than a picture this application ships. Which face
/// draws it is the platform's business — and on Windows that business has a
/// trap in it: two system fonts both claim the emoji code points, and the
/// one that comes first in the fallback chain wins.
///
/// * `Segoe UI Emoji` draws them in colour (it carries COLR colour layers).
/// * `Segoe UI Symbol` draws them as plain outlines, in the text colour.
///
/// Both fonts cover the same code points, so the chain's *order* decides
/// what a face looks like: the symbol font in front means every face is a
/// grey outline, and the emoji font in front means every face is in colour.
///
/// This file answers the question the order cannot: whether a code point
/// has a colour layer at all. A face whose code point no installed colour
/// font covers is drawn as an empty box, and no chain order can fix that —
/// the face has to be replaced with one that exists.
///
/// This lives under `test/` on purpose. It is a way of *asking* a question
/// about the machine's fonts, and nothing in the shipped application asks
/// it: the application does not choose a font per code point, it hands the
/// code point to a chain and the chain decides. Shipping a font parser to
/// answer a question nobody asks would be weight in the package for
/// nothing.
library;

import 'dart:io';
import 'dart:typed_data';

/// A code point, and whether the fonts this application names can draw it
/// in colour.
final class EmojiColour {
  const EmojiColour({required this.codePoint, required this.isColoured});

  /// The Unicode code point of the face.
  final int codePoint;

  /// Whether a colour-capable font covers [codePoint].
  final bool isColoured;

  @override
  String toString() =>
      'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}'
      '${isColoured ? '' : ' (no colour glyph)'}';
}

/// The colour-capable fonts this application asks for, and where they live
/// on a Windows machine.
///
/// The faces are named by the theme's fallback chain, and this is where a
/// chain entry is turned into a file to read. A face the machine does not
/// have is skipped rather than failed on: the answer to "is this face
/// coloured" is only meaningful on a machine that has the face, and a
/// machine without it has bigger problems.
const Map<String, String> colourFontPaths = {
  'Segoe UI Emoji': r'C:\Windows\Fonts\seguiemj.ttf',
};

/// Whether [codePoint] is drawn in colour by the fonts this application
/// names.
///
/// Returns true when the question cannot be answered — no colour font is
/// installed, or the file cannot be read — because a missing answer is not
/// evidence of a missing colour. The [EmojiColour] result says what was
/// found; a caller that needs certainty checks the fonts themselves.
EmojiColour emojiColour(int codePoint, {Map<String, String>? fonts}) {
  final sources = fonts ?? colourFontPaths;
  var sawFont = false;
  for (final path in sources.values) {
    final font = _FontFile.read(File(path));
    if (font == null) continue;
    sawFont = true;
    if (font.hasColourGlyph(codePoint)) {
      return EmojiColour(codePoint: codePoint, isColoured: true);
    }
  }
  return EmojiColour(codePoint: codePoint, isColoured: !sawFont);
}

/// Just enough of a TrueType font to answer "does this font draw this code
/// point in colour".
///
/// Two tables are read: `cmap`, which maps code points to glyph ids, and
/// `COLR`, which lists the glyph ids that carry colour layers. A code point
/// is drawn in colour when its glyph id is in the `COLR` list. Both are
/// read as ids rather than as names, because ids are what the tables
/// actually store and a font's names are optional.
///
/// This is not a font library. It is the smallest thing that answers the
/// question, and it answers it by reading the same bytes the renderer does.
final class _FontFile {
  _FontFile(this._data, this._tables);

  /// The bytes of the whole font file.
  final Uint8List _data;

  /// Where each table starts and how long it is.
  final Map<String, _TableRange> _tables;

  /// The code points the font maps, and to which glyph id.
  late final Map<int, int> _cmap = _readCmap();

  /// The glyph ids that carry colour layers.
  late final Set<int> _colourGlyphs = _readColourGlyphs();

  /// Reads the font at [path], or answers null when it cannot be read.
  static _FontFile? read(File file) {
    try {
      if (!file.existsSync()) return null;
      final data = Uint8List.fromList(file.readAsBytesSync());
      final tables = _readTableDirectory(data);
      if (tables == null) return null;
      return _FontFile(data, tables);
    } on FileSystemException {
      return null;
    }
  }

  /// Whether the font draws [codePoint] in colour.
  bool hasColourGlyph(int codePoint) {
    final glyph = _cmap[codePoint];
    if (glyph == null) return false;
    return _colourGlyphs.contains(glyph);
  }

  /// Reads the table directory: for each table, where it starts and how long.
  static Map<String, _TableRange>? _readTableDirectory(Uint8List data) {
    if (data.length < 12) return null;
    final numTables = _readU16(data, 4);
    final tables = <String, _TableRange>{};
    for (var i = 0; i < numTables; i++) {
      final record = 12 + i * 16;
      if (record + 16 > data.length) return null;
      final tag = String.fromCharCodes(data.sublist(record, record + 4));
      tables[tag] = _TableRange(
        offset: _readU32(data, record + 8),
        length: _readU32(data, record + 12),
      );
    }
    return tables;
  }

  /// Reads the `cmap` table into a code-point-to-glyph-id map.
  ///
  /// The table holds several subtables and a font may pick any of them, so
  /// every readable subtable is merged and the first mapping of a code point
  /// wins — which is the order the font's own preference list gives.
  Map<int, int> _readCmap() {
    final table = _tables['cmap'];
    if (table == null) return const {};
    final base = table.offset;
    if (base + 4 > _data.length) return const {};
    final numTables = _readU16(_data, base + 2);
    final result = <int, int>{};
    for (var i = 0; i < numTables; i++) {
      final record = base + 4 + i * 8;
      if (record + 8 > _data.length) continue;
      final subtable = base + _readU32(_data, record + 4);
      _readCmapSubtable(subtable, result);
    }
    return result;
  }

  /// Reads one `cmap` subtable into [into].
  void _readCmapSubtable(int base, Map<int, int> into) {
    if (base + 4 > _data.length) return;
    final format = _readU16(_data, base);
    switch (format) {
      case 0:
        _readCmapFormat0(base, into);
      case 4:
        _readCmapFormat4(base, into);
      case 6:
        _readCmapFormat6(base, into);
      case 12:
        _readCmapFormat12(base, into);
    }
  }

  /// The byte-segment mapping (format 4), the one almost every font has.
  void _readCmapFormat4(int base, Map<int, int> into) {
    if (base + 14 > _data.length) return;
    final segCount = _readU16(_data, base + 6) ~/ 2;
    final endCodes = base + 14;
    final startCodes = endCodes + segCount * 2 + 2;
    final idDeltas = startCodes + segCount * 2;
    final idRangeOffsets = idDeltas + segCount * 2;
    if (idRangeOffsets + segCount * 2 > _data.length) return;
    for (var segment = 0; segment < segCount; segment++) {
      final end = _readU16(_data, endCodes + segment * 2);
      final start = _readU16(_data, startCodes + segment * 2);
      if (start > end) continue;
      if (start == 0xFFFF) continue;
      final delta = _readU16(_data, idDeltas + segment * 2);
      final rangeOffset = _readU16(_data, idRangeOffsets + segment * 2);
      for (var code = start; code <= end; code++) {
        int glyph;
        if (rangeOffset == 0) {
          glyph = (code + delta) & 0xFFFF;
        } else {
          // A range offset points at a word holding the glyph id for this
          // code, relative to the word's own place in the array.
          final word =
              idRangeOffsets + segment * 2 + rangeOffset + (code - start) * 2;
          if (word + 2 > _data.length) continue;
          glyph = _readU16(_data, word);
          if (glyph == 0) continue;
          glyph = (glyph + delta) & 0xFFFF;
        }
        into.putIfAbsent(code, () => glyph);
      }
    }
  }

  /// The segmented coverage mapping (format 12), which carries the planes
  /// that format 4 cannot express.
  void _readCmapFormat12(int base, Map<int, int> into) {
    if (base + 16 > _data.length) return;
    final groups = _readU32(_data, base + 12);
    for (var i = 0; i < groups; i++) {
      final record = base + 16 + i * 12;
      if (record + 12 > _data.length) return;
      final start = _readU32(_data, record);
      final end = _readU32(_data, record + 4);
      final startGlyph = _readU32(_data, record + 8);
      for (var code = start; code <= end; code++) {
        into.putIfAbsent(code, () => startGlyph + (code - start));
      }
    }
  }

  /// The trimmed table mapping (format 6).
  void _readCmapFormat6(int base, Map<int, int> into) {
    if (base + 10 > _data.length) return;
    final first = _readU16(_data, base + 6);
    final count = _readU16(_data, base + 8);
    for (var i = 0; i < count; i++) {
      final word = base + 10 + i * 2;
      if (word + 2 > _data.length) return;
      into.putIfAbsent(first + i, () => _readU16(_data, word));
    }
  }

  /// The byte mapping (format 0).
  void _readCmapFormat0(int base, Map<int, int> into) {
    if (base + 6 > _data.length) return;
    for (var code = 0; code < 256; code++) {
      final word = base + 6 + code;
      if (word + 1 > _data.length) return;
      final glyph = _data[word];
      if (glyph == 0) continue;
      into.putIfAbsent(code, () => glyph);
    }
  }

  /// Reads the `COLR` table's list of colour-capable glyph ids.
  ///
  /// Version 0 lists them as a plain array of glyph ids; version 1 replaces
  /// that array with a base-glyph list plus layer records. Both are read,
  /// because a colour font that answers only for version 1 would otherwise
  /// report every one of its faces as uncoloured.
  Set<int> _readColourGlyphs() {
    final table = _tables['COLR'];
    if (table == null) return const {};
    final base = table.offset;
    if (base + 14 > _data.length) return const {};
    final glyphs = <int>{};
    final version = _readU16(_data, base);
    if (version == 0) {
      final count = _readU16(_data, base + 12);
      for (var i = 0; i < count; i++) {
        final word = base + 14 + i * 2;
        if (word + 2 > _data.length) return glyphs;
        glyphs.add(_readU16(_data, word));
      }
      return glyphs;
    }
    // Version 1: the base-glyph list holds the colour-carrying glyphs.
    final baseListOffset = _readU32(_data, base + 8);
    if (baseListOffset == 0) return glyphs;
    final listBase = base + baseListOffset;
    if (listBase + 6 > _data.length) return glyphs;
    final count = _readU32(_data, listBase + 4);
    for (var i = 0; i < count; i++) {
      final word = listBase + 6 + i * 2;
      if (word + 2 > _data.length) return glyphs;
      glyphs.add(_readU16(_data, word));
    }
    return glyphs;
  }

  /// Reads a big-endian unsigned 16-bit value.
  static int _readU16(Uint8List data, int offset) =>
      (data[offset] << 8) | data[offset + 1];

  /// Reads a big-endian unsigned 32-bit value.
  static int _readU32(Uint8List data, int offset) =>
      (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

/// Where one table sits in a font file.
final class _TableRange {
  const _TableRange({required this.offset, required this.length});

  /// Where the table starts.
  final int offset;

  /// How long the table is.
  final int length;
}

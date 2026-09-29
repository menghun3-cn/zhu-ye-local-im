/// Crockford's Base32: an alphabet chosen so a human typing a code cannot be
/// defeated by characters that look alike.
///
/// The alphabet is `0-9` plus the letters `A-Z` minus `I`, `L`, `O` and `U`.
/// Decoding additionally accepts lowercase and folds the confusable characters
/// `O` to `0` and `I`/`L` to `1`, which is what makes the encoding forgiving
/// enough for a code read off one screen and typed into another.
///
/// See <https://www.crockford.com/base32.html>.
class CrockfordBase32 {
  const CrockfordBase32._();

  /// The 32 encoding symbols, in value order.
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Encodes [bytes] without padding.
  static String encode(List<int> bytes) {
    final buffer = StringBuffer();
    var accumulator = 0;
    var bits = 0;
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        throw RangeError.value(byte, 'byte', 'must be in 0..255');
      }
      accumulator = (accumulator << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        buffer.write(alphabet[(accumulator >> bits) & 0x1f]);
      }
    }
    if (bits > 0) {
      buffer.write(alphabet[(accumulator << (5 - bits)) & 0x1f]);
    }
    return buffer.toString();
  }

  /// Decodes [code], or throws [FormatException] if it contains a symbol that
  /// is not in the alphabet even after folding.
  ///
  /// Trailing bits that do not form a whole byte are discarded, so
  /// `decode(encode(x)) == x` for every input.
  static List<int> decode(String code) {
    final out = <int>[];
    var accumulator = 0;
    var bits = 0;
    for (var i = 0; i < code.length; i++) {
      final symbol = code[i];
      if (symbol == '-') continue; // display separator, not a value
      final value = _valueOf(symbol, i);
      accumulator = (accumulator << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((accumulator >> bits) & 0xff);
      }
    }
    return out;
  }

  static int _valueOf(String symbol, int index) {
    final upper = symbol.toUpperCase();
    final folded = switch (upper) {
      'O' => '0',
      'I' || 'L' => '1',
      _ => upper,
    };
    final value = alphabet.indexOf(folded);
    if (value < 0) {
      throw FormatException('invalid base32 symbol "$symbol" at index $index');
    }
    return value;
  }
}

/// Splits [code] into groups of [size] joined by `-`, for display.
String groupCode(String code, {int size = 5}) {
  final buffer = StringBuffer();
  for (var i = 0; i < code.length; i++) {
    if (i > 0 && i % size == 0) buffer.write('-');
    buffer.write(code[i]);
  }
  return buffer.toString();
}

/// Removes the display separators and case from a user-typed code.
String normaliseCode(String code) =>
    code.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toUpperCase();

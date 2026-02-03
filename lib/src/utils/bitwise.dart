/// Extension on [num] to simplify bitwise operations for byte extraction
extension BitwiseByteExtension on num {
  /// Extracts the byte at the specified position (0-indexed from right)
  /// Example: 0x12345678.byteAt(0) returns 0x78
  /// Works regardless of the actual integer size
  int byteAt(int position) {
    return (toInt() >> (position * 8)) & 0xFF;
  }

  /// Extracts all bytes as a list (from low to high byte)
  /// Automatically determines the number of bytes needed
  List<int> get bytes {
    final value = toInt();
    if (value == 0) return [0];

    final bytes = <int>[];
    var temp = value.abs();
    while (temp > 0) {
      bytes.add(temp & 0xFF);
      temp >>= 8;
    }
    return bytes;
  }

  /// Extracts the low byte (bits 0-7)
  int get lowByte => byteAt(0);

  /// Extracts the low byte (bits 0-7)
  int get byte0 => byteAt(0);

  /// Extracts the second byte (bits 8-15)
  int get byte1 => byteAt(1);

  /// Extracts the third byte (bits 16-23)
  int get byte2 => byteAt(2);

  /// Extracts the fourth byte (bits 24-31)
  int get byte3 => byteAt(3);

  /// Extracts byte 4 (bits 32-39) - useful for 64-bit values
  int get byte4 => byteAt(4);

  /// Extracts byte 5 (bits 40-47)
  int get byte5 => byteAt(5);

  /// Extracts byte 6 (bits 48-55)
  int get byte6 => byteAt(6);

  /// Extracts byte 7 (bits 56-63)
  int get byte7 => byteAt(7);

  /// Extracts a specific bit at the given position
  bool bitAt(int position) {
    return ((toInt() >> position) & 1) == 1;
  }

  /// Extracts a range of bits as a mask
  /// [start] is the starting bit position (inclusive)
  /// [length] is the number of bits to extract
  int bits(int start, int length) {
    final mask = (1 << length) - 1;
    return (toInt() >> start) & mask;
  }
}

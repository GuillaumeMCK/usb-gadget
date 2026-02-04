import 'dart:typed_data';

/// Extension on [int] to provide bitwise operations for extracting bytes and
/// bits.
extension IntOps on int {
  /// Extracts or sets a specific byte at the given position.
  /// [position] is the byte position (0 = least significant byte).
  /// If [value] is provided, sets the byte to that value (0-255
  /// inclusive) and returns the modified integer. If [value] is null,
  /// returns the extracted byte value.
  int byte(int position, [int? value]) {
    assert(position >= 0, 'Byte position must be non-negative');
    assert(
      position < 8,
      'Byte position $position exceeds 64-bit integer range',
    );
    assert(
      value == null || (value >= 0 && value <= 255),
      'Byte value must be between 0 and 255',
    );
    final shift = position * 8;
    return switch (value) {
      null => (this >> shift) & 0xFF,
      _ => (this & ~(0xFF << shift)) | ((value & 0xFF) << shift),
    };
  }

  /// Extracts all bytes as a list (from low to high byte).
  Uint8List get bytes {
    // Safety: bitLength for 0 is 0; ensure we produce at least 1 byte if needed,
    // or handle the 0 case gracefully.
    final byteCount = bitLength == 0 ? 1 : (bitLength + 7) ~/ 8;
    final byteList = Uint8List(byteCount);
    for (var i = 0; i < byteCount; i++) {
      byteList[i] = byte(i);
    }
    return byteList;
  }

  /// Extracts a specific bit at the given position.
  bool bitFlag(int position) {
    assert(position >= 0, 'Bit position must be non-negative');
    assert(position < 64, 'Bit position $position exceeds 64-bit range');
    return ((this >> position) & 1) == 1;
  }

  /// Sets or clears a specific bit at the given position.
  /// [position] is the bit position to modify.
  /// If [bit] is 1, the bit is set; if 0, the bit is cleared; if null, no
  /// change. Then returns the modified / original integer.
  int bit(int position, [int? bit]) {
    assert(position >= 0, 'Bit position must be non-negative');
    assert(position < 64, 'Bit position $position exceeds 64-bit range');
    return switch (bit) {
      0 => this & ~(1 << position),
      1 => this | (1 << position),
      _ => this,
    };
  }

  /// Extracts a range of bits as a mask.
  int bitMask(int start, int length) {
    assert(start >= 0, 'Start position must be non-negative');
    assert(length > 0, 'Length must be greater than 0');
    assert(start + length <= 64, 'Bit range exceeds 64-bit capacity');

    // Safety: Prevent overflow when creating the mask.
    // (1 << 64) would result in 0 or an error depending on the platform.
    final mask = length == 64 ? -1 : (1 << length) - 1;
    return (this >> start) & mask;
  }
}

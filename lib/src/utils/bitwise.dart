import 'dart:typed_data';

/// Extension providing bit-level operations on integers.
///
/// These utilities treat the integer as a 64-bit two’s-complement value
/// and operate within that range.
extension IntBitOps on int {
  /// Returns `true` if the bit at [position] is set (1), otherwise `false`.
  ///
  /// [position] must be in the range 0–63.
  bool bitFlag(int position) {
    assert(position >= 0, 'Bit position must be non-negative');
    assert(position < 64, 'Bit position $position exceeds 64-bit range');

    return ((this >> position) & 1) == 1;
  }

  /// Sets or clears a specific bit at the given [position].
  ///
  /// If [bit] is:
  ///  * `1` – the bit is set
  ///  * `0` – the bit is cleared
  ///  * `null` – the original integer is returned unchanged
  ///
  /// Returns the modified integer.
  int bit(int position, [int? bit]) {
    assert(position >= 0, 'Bit position must be non-negative');
    assert(position < 64, 'Bit position $position exceeds 64-bit range');
    assert(
    bit == null || bit == 0 || bit == 1,
    'Bit value must be 0, 1, or null',
    );

    return switch (bit) {
      0 => this & ~(1 << position),
      1 => this | (1 << position),
      _ => this,
    };
  }

  /// Extracts a range of bits as an integer mask.
  ///
  /// Bits are taken starting from [start] and spanning [length] bits.
  ///
  /// Example:
  /// ```dart
  /// 0b110101.bitMask(1, 3) == 0b010
  /// ```
  int bitMask(int start, int length) {
    assert(start >= 0, 'Start position must be non-negative');
    assert(start < 64, 'Start position must be less than 64');
    assert(length > 0, 'Length must be greater than 0');
    assert(length <= 64, 'Length cannot exceed 64 bits');
    assert(start + length <= 64, 'Bit range exceeds 64-bit capacity');

    // Special case: shifting by 64 would overflow, so use -1 (all bits set)
    final mask = length == 64 ? -1 : (1 << length) - 1;

    return (this >> start) & mask;
  }
}

/// Extension providing byte-level operations on integers.
///
/// Bytes are indexed from least significant (position 0)
/// to most significant (position 7).
extension IntByteOps on int {
  /// Gets or sets a specific byte within the integer.
  ///
  /// If [value] is `null`, returns the byte at [position].
  ///
  /// If [value] is provided (0–255), the byte at [position] is replaced
  /// with that value and the modified integer is returned.
  int byte(int position, [int? value]) {
    assert(position >= 0, 'Byte position must be non-negative');
    assert(
    position < 8,
    'Byte position must be between 0 and 7 inclusive',
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

  /// Returns all significant bytes of this integer as a [Uint8List].
  ///
  /// The bytes are returned in little-endian order (least significant
  /// byte first). At least one byte is returned, even for the value `0`.
  Uint8List get bytes {
    final byteCount = bitLength == 0 ? 1 : (bitLength + 7) ~/ 8;

    final byteList = Uint8List(byteCount);
    for (var i = 0; i < byteCount; i++) {
      byteList[i] = byte(i);
    }

    return byteList;
  }

  /// Converts this integer to a byte array of fixed [length] and [endian] order.
  ///
  /// [length] must be between 1 and 8 (inclusive), as a Dart [int] is treated
  /// here as a 64-bit value.
  ///
  /// If [length] is smaller than the number of significant bytes, the value
  /// will be truncated.
  Uint8List toBytes(int length, [Endian endian = Endian.big]) {
    assert(length > 0, 'Length must be greater than 0');
    assert(length <=
        8, 'Cannot convert more than 8 bytes from a 64-bit integer');

    final byteList = Uint8List(length);

    for (var i = 0; i < length; i++) {
      final index = endian == Endian.big ? length - 1 - i : i;
      byteList[index] = byte(i);
    }

    return byteList;
  }
}

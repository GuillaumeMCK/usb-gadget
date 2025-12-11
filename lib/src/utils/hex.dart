extension HexStringExt on int {
  /// Convert an integer to a hexadecimal string with optional padding.
  String toHex({int padding = 0, bool prefix = true}) {
    final hex = toRadixString(16).toUpperCase().padLeft(padding, '0');
    return prefix ? '0x$hex' : hex;
  }
}
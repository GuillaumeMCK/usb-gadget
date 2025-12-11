import 'dart:io';
import 'dart:typed_data';
import 'hex.dart';

extension XXDExt on Uint8List {
  void xxd() {
    final hexDump = StringBuffer();
    for (var i = 0; i < length; i += 16) {
      hexDump.write('${i.toHex(padding: 4)}:  ');

      final lineBytes = sublist(i, (i + 16).clamp(0, length));
      for (var j = 0; j < 16; j++) {
        if (j < lineBytes.length) {
          hexDump.write('${lineBytes[j].toHex(prefix: false, padding: 2)} ');
        } else {
          hexDump.write('   ');
        }
        if (j == 7) hexDump.write(' ');
      }

      hexDump.write(' |');
      for (final byte in lineBytes) {
        hexDump.write(
          (byte >= 32 && byte < 127) ? String.fromCharCode(byte) : '.',
        );
      }
      hexDump.write('|\n');
    }
    stdout.write(hexDump.toString());
  }
}

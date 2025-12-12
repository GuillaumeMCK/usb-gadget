import 'dart:io';

import '/src/usb/hid/types.dart';
import 'base.dart';

/// HID function (keyboard, mouse, gamepad, etc.).
class HIDFunction extends KernelFunction {
  HIDFunction({
    required super.name,
    required this.descriptor,
    this.protocol = HIDProtocol.none,
    this.subclass = HIDSubclass.none,
    this.reportLength = 64,
  }) : super(kernelType: .hid);

  /// HID report descriptor (defines device type and data format)
  final List<int> descriptor;

  /// HID protocol (0=none, 1=keyboard, 2=mouse)
  final HIDProtocol protocol;

  /// HID subclass (0=none, 1=boot)
  final HIDSubclass subclass;

  /// Maximum report length in bytes
  final int reportLength;

  /// HID device file handle (use RandomAccessFile for synchronous writes)
  RandomAccessFile? _file;

  /// Gets the HID device file handle for writing reports.
  /// Lazily opens the file on first access.
  RandomAccessFile get file {
    final currentFile = _file;
    if (currentFile != null) {
      return currentFile;
    }
    return _file ??= File(_getHIDDevice()).openSync(mode: .writeOnlyAppend);
  }

  @override
  bool validate() {
    if (descriptor.isEmpty) {
      return false;
    }
    if (reportLength <= 0 || reportLength > 1024) {
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'protocol': protocol.value.toString(),
    'subclass': subclass.value.toString(),
    'report_length': reportLength.toString(),
  };

  @override
  Future<void> prepare(String path) async {
    log?.info('Writing HID report descriptor (${descriptor.length} bytes)');
    File(
      '$path/report_desc',
    ).writeAsBytesSync(descriptor, mode: .writeOnlyAppend);
    await super.prepare(path);
  }

  @override
  Future<void> dispose() async {
    log?.info('Closing HID device');
    await _file?.close();
    _file = null;
    await super.dispose();
  }

  /// Gets the HID device path (e.g., /dev/hidg0).
  String _getHIDDevice() {
    if (!prepared) {
      throw StateError('HID function not prepared');
    }
    final devAttr = readAttribute('dev');
    if (devAttr != null) {
      final parts = devAttr.split(':');
      final devNum = int.tryParse(parts.isEmpty ? devAttr : parts.last);
      if (devNum != null) {
        return '/dev/hidg$devNum';
      }
    }
    if (File('/dev/hidg0').existsSync()) {
      return '/dev/hidg0';
    }
    throw StateError('No HID device found');
  }
}

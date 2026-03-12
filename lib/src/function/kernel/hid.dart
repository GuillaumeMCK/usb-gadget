import 'dart:io';

import '/src/usb/hid/types.dart';
import 'base.dart';

/// HID function (keyboard, mouse, gamepad, etc.).
class HIDFunction extends KernelFunction {
  HIDFunction({
    required super.name,
    required this.descriptor,
    this.protocol = 0x00,
    this.subClass = 0x00,
    this.reportLength = 64,
    this.noOutEndpoint = false,
  }) : super(kernelType: .hid);

  /// HID report descriptor (defines device type and data format)
  final List<int> descriptor;

  /// HID protocol (0=none, 1=keyboard, 2=mouse)
  final int protocol;

  /// HID subclass (0=none, 1=boot)
  final int subClass;

  /// Maximum report length in bytes
  final int reportLength;

  /// Whether to disable the OUT endpoint.
  ///
  /// Some HID devices don't need an OUT endpoint (e.g., simple mice or keyboards
  /// that only send data to the host). Setting this to true disables the OUT
  /// endpoint creation.
  final bool noOutEndpoint;

  /// HID device file handle (use RandomAccessFile for synchronous writes)
  RandomAccessFile? _file;

  /// Gets the HID device file handle for writing reports.
  /// Lazily opens the file on first access.
  RandomAccessFile get file {
    if (_file != null) {
      return _file!;
    }
    final (major, minor) = device();
    final path = '/dev/hidg$minor';
    return _file ??= File(path).openSync(mode: .writeOnlyAppend);
  }

  /// Device major and minor numbers.
  ///
  /// Parses the 'dev' attribute which contains the device numbers in
  /// "major:minor" format (e.g., "240:0").
  ///
  /// Returns a tuple of (major, minor) device numbers.
  /// Throws if the function is not prepared or the format is invalid.
  (int, int) device() {
    if (!prepared) {
      throw StateError('Function not prepared - bind gadget first');
    }

    final dev = readAttribute('dev');
    if (dev == null) {
      throw StateError('dev attribute not found');
    }

    final parts = dev.trim().split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid device number format: $dev');
    }

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);

    if (major == null || minor == null) {
      throw FormatException('Invalid device number format: $dev');
    }

    return (major, minor);
  }

  /// Device path in `/dev` (e.g. `/dev/hidg0`).
  ///
  /// Derives the path from the minor device number read from the `dev`
  /// attribute. This is the file you open to send HID reports.
  ///
  /// Throws [StateError] if the function has not been prepared.
  String devicePath() {
    final (_, minor) = device();
    return '/dev/hidg$minor';
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
    'protocol': protocol.toString(),
    'subclass': subClass.toString(),
    'report_length': reportLength.toString(),
    'no_out_endpoint': noOutEndpoint ? '1' : '0',
  };

  @override
  Future<void> prepare(String path) async {
    log?.info('Writing HID report descriptor (${descriptor.length} bytes)');
    File(
      '$path/report_desc',
    ).writeAsBytesSync(descriptor, mode: FileMode.writeOnlyAppend);
    await super.prepare(path);
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    log?.info('Closing HID device');
    try {
      _file?.closeSync();
    } catch (err, st) {
      log?.warn('Failed to close HID device file:', err, st);
    }
    _file = null;
    await super.release();
  }
}

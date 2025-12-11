import 'dart:io';

import '/src/usb/hid/types.dart';
import 'base.dart';

/// HID function (keyboard, mouse, gamepad, etc.).
class HIDFunction extends KernelFunction {
  HIDFunction({
    required super.name,
    required this.reportDescriptor,
    this.protocol = HIDProtocol.none,
    this.subclass = HIDSubclass.none,
    this.reportLength = 64,
  }) : super(kernelType: .hid);

  /// HID report descriptor (defines device type and data format)
  final List<int> reportDescriptor;

  /// HID protocol (0=none, 1=keyboard, 2=mouse)
  final HIDProtocol protocol;

  /// HID subclass (0=none, 1=boot)
  final HIDSubclass subclass;

  /// Maximum report length in bytes
  final int reportLength;

  @override
  bool validate() {
    if (reportDescriptor.isEmpty) {
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
  void onPrepare() {
    final reportDescPath = '$functionPath/report_desc';
    log?.info(
      'Writing HID report descriptor (${reportDescriptor.length} bytes)',
    );
    File(reportDescPath).writeAsBytesSync(reportDescriptor);
  }

  /// Gets the HID device path (e.g., /dev/hidg0).
  String? getHIDDevice() {
    if (!isPrepared) return null;
    try {
      final devAttr = tryReadAttribute('dev');
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
      return null;
    } catch (_) {
      return null;
    }
  }
}

import 'base.dart';

/// Serial (CDC ACM) function (virtual serial port).
class AcmFunction extends KernelFunction {
  AcmFunction({required super.name}) : super(kernelType: .acm);

  @override
  Map<String, String> getConfigAttributes() => {};

  /// Gets the TTY device path on the device side (e.g., /dev/ttyGS0).
  String? getTtyDevice() {
    if (!isPrepared) return null;
    try {
      final portNum = readAttribute('port_num');
      return '/dev/ttyGS$portNum';
    } catch (_) {
      return null;
    }
  }
}

/// Generic serial function (non-CDC).
class GenericSerialFunction extends KernelFunction {
  GenericSerialFunction({required super.name}) : super(kernelType: .serial);

  @override
  Map<String, String> getConfigAttributes() => {};

  /// Gets the TTY device path on the device side.
  String? getTtyDevice() {
    if (!isPrepared) return null;
    try {
      final portNum = readAttribute('port_num');
      return '/dev/ttyGS$portNum';
    } catch (_) {
      return null;
    }
  }
}

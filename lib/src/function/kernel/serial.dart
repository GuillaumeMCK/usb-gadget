import 'base.dart';

/// Serial (CDC ACM) function (virtual serial port).
class AcmFunction extends KernelFunction {
  AcmFunction({required super.name, this.console}) : super(kernelType: .acm);

  /// Whether to enable console mode.
  ///
  /// When enabled, this allows the serial port to be used as a console device.
  /// Note: Console support is optional and may not be available on all kernels.
  final bool? console;

  @override
  Map<String, String> getConfigAttributes() => {
    if (console != null) 'console': console! ? '1' : '0',
  };

  /// Gets the TTY device path on the device side (e.g., /dev/ttyGS0).
  String? getTtyDevice() {
    if (!prepared) return null;
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
  GenericSerialFunction({required super.name, this.console})
    : super(kernelType: .serial);

  /// Whether to enable console mode.
  ///
  /// When enabled, this allows the serial port to be used as a console device.
  /// Note: Console support is optional and may not be available on all kernels.
  final bool? console;

  @override
  Map<String, String> getConfigAttributes() => {
    if (console != null) 'console': console! ? '1' : '0',
  };

  /// Gets the TTY device path on the device side.
  String? getTtyDevice() {
    if (!prepared) return null;
    try {
      final portNum = readAttribute('port_num');
      return '/dev/ttyGS$portNum';
    } catch (_) {
      return null;
    }
  }
}

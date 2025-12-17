import 'base.dart';

/// Printer function (USB printer class).
class PrinterFunction extends KernelFunction {
  PrinterFunction({required super.name, this.pnpString, this.queueLength})
    : super(kernelType: .printer);

  /// Get printer status ioctl ID.
  ///
  /// Use with ioctl() calls to get current printer status flags.
  static const int ioctlGetPrinterStatus = 0x21;

  /// Set printer status ioctl ID.
  ///
  /// Use with ioctl() calls to set printer status flags.
  static const int ioctlSetPrinterStatus = 0x22;

  // Printer status flags (based on USB printer class spec)

  /// Printer not in error state.
  static const int statusNotError = 1 << 3;

  /// Printer selected.
  static const int statusSelected = 1 << 4;

  /// Printer out of paper.
  static const int statusPaperEmpty = 1 << 5;

  /// PNP ID string used for this printer.
  final String? pnpString;

  /// Number of 8k buffers to use per endpoint (default: 10).
  final int? queueLength;

  @override
  Map<String, String> getConfigAttributes() => {
    if (pnpString != null) 'pnp_string': pnpString!,
    if (queueLength != null) 'q_len': queueLength.toString(),
  };

  /// Gets the printer device path (e.g., /dev/g_printer0).
  ///
  /// Parses the 'dev' attribute to get the minor number and constructs
  /// the device path. Returns null if not available.
  String? getPrinterDevice() {
    if (!prepared) return null;

    try {
      final dev = readAttribute('dev');
      if (dev != null) {
        final parts = dev.trim().split(':');
        if (parts.length == 2) {
          final minor = int.tryParse(parts[1]);
          if (minor != null) {
            return '/dev/g_printer$minor';
          }
        }
      }
    } catch (_) {
      // Ignore errors
    }

    return null;
  }
}

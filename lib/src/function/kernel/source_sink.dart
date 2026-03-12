import 'base.dart';

/// Source/Sink function (for USB testing).
///
/// Generates patterns on IN endpoint and validates patterns on OUT endpoint.
class SourceSinkFunction extends KernelFunction {
  SourceSinkFunction({
    required super.name,
    this.pattern = 0,
    this.isocInterval = 4,
    this.isocMaxpacket = 1024,
    this.isocMult = 0,
    this.isocMaxburst = 0,
    this.bulkBuflen = 4096,
    this.bulkQlen = 32,
    this.isoQlen = 16,
  }) : super(kernelType: .sourceSink);

  /// Pattern type (0=all zeros, 1=mod63, 2=none)
  final int pattern;

  /// Isochronous endpoint interval
  final int isocInterval;

  /// Isochronous maximum packet size
  final int isocMaxpacket;

  /// Isochronous transactions per microframe (high-speed/super-speed)
  final int isocMult;

  /// Isochronous max burst (super-speed only)
  final int isocMaxburst;

  /// Bulk buffer length
  final int bulkBuflen;

  /// Bulk queue length
  final int bulkQlen;

  /// Isochronous request queue length
  final int isoQlen;

  @override
  bool validate() {
    if (pattern < 0 || pattern > 2) {
      log?.error('Invalid pattern: $pattern (must be 0-2)');
      return false;
    }
    if (isocInterval < 1 || isocInterval > 16) {
      log?.error('Invalid isoc_interval: $isocInterval');
      return false;
    }
    if (bulkQlen <= 0 || bulkQlen > 1000) {
      log?.error('Invalid bulk_qlen: $bulkQlen');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'pattern': pattern.toString(),
    'isoc_interval': isocInterval.toString(),
    'isoc_maxpacket': isocMaxpacket.toString(),
    'isoc_mult': isocMult.toString(),
    'isoc_maxburst': isocMaxburst.toString(),
    'bulk_buflen': bulkBuflen.toString(),
    'bulk_qlen': bulkQlen.toString(),
    'iso_qlen': isoQlen.toString(),
  };
}

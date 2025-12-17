import 'base.dart';

/// Loopback function (for USB testing).
///
/// Data written to the OUT endpoint is looped back to the IN endpoint.
class LoopbackFunction extends KernelFunction {
  LoopbackFunction({required super.name, this.qlen = 32, this.buflen = 4096})
    : super(kernelType: .loopback);

  /// Request queue length
  final int qlen;

  /// Buffer size in bytes
  final int buflen;

  @override
  bool validate() {
    if (qlen <= 0 || qlen > 1000) {
      log?.error('Invalid queue length: $qlen');
      return false;
    }
    if (buflen <= 0 || buflen > 65536) {
      log?.error('Invalid buffer length: $buflen');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'qlen': qlen.toString(),
    'buflen': buflen.toString(),
  };
}

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
  };
}

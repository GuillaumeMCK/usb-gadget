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
    'bulk_buflen': buflen.toString(),
  };
}

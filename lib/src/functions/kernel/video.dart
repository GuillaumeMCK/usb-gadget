import 'base.dart';

/// UVC (USB Video Class) function for webcam emulation.
class UvcFunction extends KernelFunction {
  UvcFunction({
    required super.name,
    this.streamingMaxpacket = 3072,
    this.streamingMaxburst = 0,
    this.streamingInterval = 1,
  }) : super(kernelType: .uvc);

  /// Maximum packet size for streaming endpoint
  final int streamingMaxpacket;

  /// Maximum burst size (USB 3.0 only)
  final int streamingMaxburst;

  /// Streaming interval (1-16, frame rate related)
  final int streamingInterval;

  @override
  bool validate() {
    if (streamingMaxpacket <= 0 || streamingMaxpacket > 3072) {
      log?.error('Invalid streaming_maxpacket: $streamingMaxpacket');
      return false;
    }
    if (streamingInterval < 1 || streamingInterval > 16) {
      log?.error('Invalid streaming_interval: $streamingInterval');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'streaming_maxpacket': streamingMaxpacket.toString(),
    'streaming_maxburst': streamingMaxburst.toString(),
    'streaming_interval': streamingInterval.toString(),
  };

  /// Gets the V4L2 video device path (e.g., /dev/video0).
  ///
  /// Parses the 'dev' attribute to get the minor number and constructs
  /// the device path. Returns null if not available.
  String? getVideoDevice() {
    if (!prepared) return null;

    try {
      final dev = readAttribute('dev');
      if (dev != null) {
        final parts = dev.trim().split(':');
        if (parts.length == 2) {
          final minor = int.tryParse(parts[1]);
          if (minor != null) {
            return '/dev/video$minor';
          }
        }
      }
    } catch (_) {
      // Ignore errors
    }

    return null;
  }
}

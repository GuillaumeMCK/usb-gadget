import 'base.dart';

/// MIDI function (Musical Instrument Digital Interface).
class MidiFunction extends KernelFunction with DevicePathResolver {
  MidiFunction({
    required super.name,
    this.id = 'usb-midi',
    this.inPorts = 1,
    this.outPorts = 1,
    this.buflen = 512,
    this.qlen = 32,
  }) : super(kernelType: .midi);

  /// MIDI device identifier string
  final String id;

  /// Number of MIDI input ports (device to host)
  final int inPorts;

  /// Number of MIDI output ports (host to device)
  final int outPorts;

  /// Buffer length for each port
  final int buflen;

  /// Request queue length
  final int qlen;

  @override
  bool validate() {
    if (inPorts < 0 || inPorts > 16) {
      log?.error('Invalid input ports: $inPorts (must be 0-16)');
      return false;
    }
    if (outPorts < 0 || outPorts > 16) {
      log?.error('Invalid output ports: $outPorts (must be 0-16)');
      return false;
    }
    if (buflen <= 0 || buflen > 4096) {
      log?.error('Invalid buffer length: $buflen');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'id': id,
    'in_ports': inPorts.toString(),
    'out_ports': outPorts.toString(),
    'buflen': buflen.toString(),
    'qlen': qlen.toString(),
  };

  /// Gets the ALSA sequencer device path.
  ///
  /// Note: MIDI devices use ALSA sequencer (/dev/snd/seq) rather than
  /// direct device files. The card number can be read from 'alsa_card' attribute.
  String? getMidiCardNumber() {
    if (!prepared) return null;
    return readAttribute('alsa_card');
  }
}

/// UVC (USB Video Class) function for webcam emulation.
class UvcFunction extends KernelFunction with DevicePathResolver {
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

  /// Gets the V4L2 video device path (e.g., /dev/video0)
  String? getVideoDevice() => getDevicePath('video');
}

/// Printer function (USB printer class).
class PrinterFunction extends KernelFunction with DevicePathResolver {
  PrinterFunction({
    required super.name,
    this.pnpString = 'MFG:Generic;MDL:USB Printer;',
    this.qLen = 10,
  }) : super(kernelType: .printer);

  /// IEEE 1284 Plug and Play string
  final String pnpString;

  /// Request queue length
  final int qLen;

  @override
  bool validate() {
    if (qLen <= 0 || qLen > 100) {
      log?.error('Invalid queue length: $qLen');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'pnp_string': pnpString,
    'q_len': qLen.toString(),
  };

  /// Gets the printer device path (e.g., /dev/g_printer0)
  String? getPrinterDevice() => getDevicePath('g_printer');
}

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

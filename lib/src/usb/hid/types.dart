import '../descriptors.dart';
import '../types.dart';

/// HID class-specific request codes (bRequest).
///
/// These request codes are used in control transfers to configure and
/// control HID devices. They extend the standard USB requests with
/// HID-specific operations.
enum HIDRequest {
  /// GET_REPORT (0x01).
  ///
  /// Retrieves a report from the device. Used to read the current state
  /// of input reports, get feature reports, or read output reports.
  ///
  /// Direction: Device-to-Host
  /// wValue: Report Type (high byte) and Report ID (low byte)
  /// wIndex: Interface number
  /// wLength: Report length
  getReport(0x01),

  /// GET_IDLE (0x02).
  ///
  /// Retrieves the current idle rate for an input report. The idle rate
  /// determines how often the device sends reports when data hasn't changed.
  ///
  /// Direction: Device-to-Host
  /// wValue: Report ID (low byte), 0 (high byte)
  /// wIndex: Interface number
  /// wLength: 1
  getIdle(0x02),

  /// GET_PROTOCOL (0x03).
  ///
  /// Retrieves the current protocol (boot or report). Only used by boot
  /// interface devices.
  ///
  /// Direction: Device-to-Host
  /// wValue: 0
  /// wIndex: Interface number
  /// wLength: 1
  /// Returns: 0 = boot protocol, 1 = report protocol
  getProtocol(0x03),

  /// SET_REPORT (0x09).
  ///
  /// Sends a report to the device. Used to send output reports (like LED
  /// states for keyboards) or configure feature reports.
  ///
  /// Direction: Host-to-Device
  /// wValue: Report Type (high byte) and Report ID (low byte)
  /// wIndex: Interface number
  /// wLength: Report length
  setReport(0x09),

  /// SET_IDLE (0x0A).
  ///
  /// Sets the idle rate for an input report. Value is in 4ms units,
  /// where 0 means infinite (only report on change).
  ///
  /// Direction: Host-to-Device
  /// wValue: Duration (high byte), Report ID (low byte)
  /// wIndex: Interface number
  /// wLength: 0
  setIdle(0x0A),

  /// SET_PROTOCOL (0x0B).
  ///
  /// Switches between boot and report protocol. Only used by boot
  /// interface devices.
  ///
  /// Direction: Host-to-Device
  /// wValue: 0 = boot protocol, 1 = report protocol
  /// wIndex: Interface number
  /// wLength: 0
  setProtocol(0x0B);

  const HIDRequest(this.value);

  /// Creates a request from its raw value.
  factory HIDRequest.fromByte(int byte) => switch (byte) {
    0x01 => .getReport,
    0x02 => .getIdle,
    0x03 => .getProtocol,
    0x09 => .setReport,
    0x0A => .setIdle,
    0x0B => .setProtocol,
    _ => throw Exception('Unknown HIDRequest'),
  };

  /// Raw request code value.
  final int value;
}

/// HID descriptor type codes (bDescriptorType).
///
/// These type codes identify different kinds of HID-specific descriptors.
/// They are used in addition to the standard USB descriptor types.
enum HIDDescriptorType {
  /// HID descriptor (0x21).
  ///
  /// The main HID descriptor that follows the interface descriptor.
  /// Contains HID version, country code, and references to other
  /// HID descriptors (report, physical).
  hid(0x21),

  /// Report descriptor (0x22).
  ///
  /// Defines the format and meaning of data exchanged with the device.
  /// This is the most important HID descriptor as it describes all
  /// inputs, outputs, and features of the device.
  report(0x22),

  /// Physical descriptor (0x23).
  ///
  /// Optional descriptor that describes the physical characteristics
  /// of the device (like button locations). Rarely used in practice.
  physical(0x23);

  /// Creates a HID descriptor type.
  const HIDDescriptorType(this.value);

  /// Creates a descriptor type from its raw value.
  factory HIDDescriptorType.fromByte(int byte) => switch (byte) {
    0x21 => .hid,
    0x22 => .report,
    0x23 => .physical,
    _ => throw Exception('Unknown HIDDescriptorType'),
  };

  /// Raw descriptor type value.
  final int value;
}

/// HID report types.
enum HIDReportType {
  /// Input report (1).
  input(1),

  /// Output report (2).
  output(2),

  /// Feature report (3).
  feature(3);

  /// Creates a HID report type.
  const HIDReportType(this.value);

  /// Creates a report type from its raw value.
  factory HIDReportType.fromByte(int byte) => switch (byte) {
    1 => .input,
    2 => .output,
    3 => .feature,
    _ => throw Exception('Unknown HIDReportType $byte'),
  };

  final int value;
}

/// Configuration for HID endpoint topology and parameters.
///
/// This is a sealed class — only the built-in factory constructors may be used:
/// - [HIDEndpointConfig.inputOnly] (keyboard, mouse)
/// - [HIDEndpointConfig.bidirectional] (game controllers, custom devices)
/// - [HIDEndpointConfig.outputOnly] (LED controllers, rare)
sealed class HIDEndpointConfig {
  const HIDEndpointConfig({
    required this.maxPacketSize,
    this.pollInterval = const Duration(milliseconds: 10),
    this.reportInterval = const Duration(milliseconds: 10),
  });

  /// Creates an output-only HID configuration (single OUT endpoint).
  const factory HIDEndpointConfig.outputOnly({
    Duration pollInterval,
    int maxPacketSize,
    EndpointNumber endpointNumber,
  }) = _OutputOnlyEndpointConfig;

  /// Creates an input-only HID configuration (single IN endpoint).
  const factory HIDEndpointConfig.inputOnly({
    Duration reportInterval,
    int maxPacketSize,
    EndpointNumber endpointNumber,
  }) = _InputOnlyEndpointConfig;

  /// Creates a bidirectional HID configuration (IN + OUT endpoints).
  const factory HIDEndpointConfig.bidirectional({
    Duration pollInterval,
    Duration reportInterval,
    int maxPacketSize,
    EndpointNumber inEndpointNumber,
    EndpointNumber outEndpointNumber,
  }) = _BidirectionalEndpointConfig;

  /// Polling interval in milliseconds (for OUT endpoint, if applicable).
  final Duration pollInterval;

  /// Report interval in milliseconds (for IN endpoint, if applicable).
  final Duration reportInterval;

  /// Maximum packet size for interrupt config.
  final int maxPacketSize;

  /// Number of endpoints this configuration uses (excluding EP0).
  int get numEndpoints;

  /// Generates the descriptor list for this endpoint configuration.
  List<USBDescriptor> get descriptors;

  /// Whether this config has an IN endpoint.
  bool get hasInputEndpoint;

  /// Whether this config has an OUT endpoint.
  bool get hasOutputEndpoint;

  /// Endpoint number for IN transfers (null if not applicable).
  EndpointNumber? get inEndpointNumber => null;

  /// Endpoint number for OUT transfers (null if not applicable).
  EndpointNumber? get outEndpointNumber => null;
}

/// Input-only HID configuration (IN endpoint only).
final class _InputOnlyEndpointConfig extends HIDEndpointConfig {
  const _InputOnlyEndpointConfig({
    super.reportInterval = const Duration(milliseconds: 10),
    super.maxPacketSize = 64,
    this.endpointNumber = EndpointNumber.ep1,
  });

  final EndpointNumber endpointNumber;

  @override
  int get numEndpoints => 1;

  @override
  bool get hasInputEndpoint => true;

  @override
  bool get hasOutputEndpoint => false;

  @override
  EndpointNumber get inEndpointNumber => endpointNumber;

  @override
  List<USBDescriptor> get descriptors => [
    EndpointDescriptor(
      address: .in_(endpointNumber),
      config: .interrupt(
        interval: reportInterval,
        maxPacketSize: maxPacketSize,
      ),
    ),
  ];
}

/// Bidirectional HID configuration (IN + OUT endpoints).
final class _BidirectionalEndpointConfig extends HIDEndpointConfig {
  const _BidirectionalEndpointConfig({
    super.pollInterval = const Duration(milliseconds: 10),
    super.reportInterval = const Duration(milliseconds: 10),
    super.maxPacketSize = 64,
    this.inEndpointNumber = EndpointNumber.ep1,
    this.outEndpointNumber = EndpointNumber.ep2,
  });

  @override
  final EndpointNumber inEndpointNumber;

  @override
  final EndpointNumber outEndpointNumber;

  @override
  int get numEndpoints => 2;

  @override
  bool get hasInputEndpoint => true;

  @override
  bool get hasOutputEndpoint => true;

  @override
  List<USBDescriptor> get descriptors => [
    EndpointDescriptor(
      address: .in_(inEndpointNumber),
      config: .interrupt(
        interval: reportInterval,
        maxPacketSize: maxPacketSize,
      ),
    ),
    EndpointDescriptor(
      address: .out(outEndpointNumber),
      config: .interrupt(interval: pollInterval, maxPacketSize: maxPacketSize),
    ),
  ];
}

/// Output-only HID configuration (OUT endpoint only).
final class _OutputOnlyEndpointConfig extends HIDEndpointConfig {
  const _OutputOnlyEndpointConfig({
    super.pollInterval = const Duration(milliseconds: 10),
    super.maxPacketSize = 64,
    this.endpointNumber = EndpointNumber.ep1,
  });

  final EndpointNumber endpointNumber;

  @override
  int get numEndpoints => 1;

  @override
  bool get hasInputEndpoint => false;

  @override
  bool get hasOutputEndpoint => true;

  @override
  EndpointNumber get outEndpointNumber => endpointNumber;

  @override
  List<USBDescriptor> get descriptors => [
    EndpointDescriptor(
      address: .out(endpointNumber),
      config: .interrupt(interval: pollInterval, maxPacketSize: maxPacketSize),
    ),
  ];
}

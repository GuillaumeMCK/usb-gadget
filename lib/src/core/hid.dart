/// USB HID (Human Interface Device) support.
///
/// Provides types and descriptors for implementing HID devices like keyboards,
/// mice, game controllers, and custom HID devices. This library follows the
/// USB HID 1.11 specification.
///
/// HID devices communicate through:
/// - HID descriptors: Describe the device capabilities
/// - Report descriptors: Define the format of data exchanged
/// - HID class requests: Control transfers for configuration
/// - Interrupt transfers: For sending/receiving reports
library;

import 'dart:typed_data';


import '/usb_gadget.dart';

/// HID subclass codes (bInterfaceSubClass).
///
/// Subclass codes identify specific types of HID devices. Most HID devices
/// use the "no subclass" value and rely on the report descriptor to define
/// their functionality. The boot interface subclass is used for BIOS-level
/// support before the full HID driver loads.
///
/// Example:
/// ```dart
/// final subclass = HIDSubclass.boot;
/// print(subclass.value); // 0x01
/// ```
enum HIDSubclass {
  /// No subclass (0x00).
  ///
  /// Most HID devices use this. The report descriptor fully defines the device.
  none(0x00),

  /// Boot interface subclass (0x01).
  ///
  /// Indicates a device that implements a simplified "boot protocol" for
  /// BIOS compatibility. Used by keyboards and mice to function before the
  /// OS HID driver loads. Boot devices can also support a full report protocol.
  boot(0x01);

  const HIDSubclass(this.value);

  /// Raw subclass code value.
  final int value;

  /// Creates a subclass from its raw value.
  static HIDSubclass fromValue(int value) {
    return HIDSubclass.values.firstWhere(
      (s) => s.value == value,
      orElse: () => none,
    );
  }
}

/// HID protocol codes (bInterfaceProtocol).
///
/// Protocol codes identify specific device types within the boot interface
/// subclass. These are only meaningful when using HIDSubclass.boot.
///
/// Example:
/// ```dart
/// // Boot keyboard
/// final protocol = HIDProtocol.keyboard;
/// print(protocol.value); // 0x01
/// ```
enum HIDProtocol {
  /// No protocol or non-boot device (0x00).
  ///
  /// Used by all non-boot HID devices and as the default.
  none(0x00),

  /// Keyboard protocol (0x01).
  ///
  /// Boot interface keyboard. Sends 8-byte reports with modifier keys
  /// and up to 6 simultaneous key presses.
  keyboard(0x01),

  /// Mouse protocol (0x02).
  ///
  /// Boot interface mouse. Sends reports with button states and
  /// relative X/Y movement.
  mouse(0x02);

  const HIDProtocol(this.value);

  /// Raw protocol code value.
  final int value;

  /// Creates a protocol from its raw value.
  static HIDProtocol fromValue(int value) {
    return HIDProtocol.values.firstWhere(
      (p) => p.value == value,
      orElse: () => none,
    );
  }
}

/// HID class-specific request codes (bRequest).
///
/// These request codes are used in control transfers to configure and
/// control HID devices. They extend the standard USB requests with
/// HID-specific operations.
///
/// Example:
/// ```dart
/// // GET_REPORT request
/// final request = HIDRequest.getReport;
/// print(request.value); // 0x01
/// ```
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

  /// Raw request code value.
  final int value;

  /// Creates a request from its raw value.
  static HIDRequest? fromValue(int value) {
    try {
      return HIDRequest.values.firstWhere((r) => r.value == value);
    } catch (_) {
      return null;
    }
  }
}

/// HID descriptor type codes (bDescriptorType).
///
/// These type codes identify different kinds of HID-specific descriptors.
/// They are used in addition to the standard USB descriptor types.
///
/// Example:
/// ```dart
/// final type = HIDDescriptorType.hid;
/// print(type.value); // 0x21
/// ```
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

  const HIDDescriptorType(this.value);

  /// Raw descriptor type value.
  final int value;

  /// Creates a descriptor type from its raw value.
  static HIDDescriptorType fromValue(
    int value, {
    HIDDescriptorType orElse = .hid,
  }) {
    try {
      return HIDDescriptorType.values.firstWhere((t) => t.value == value);
    } catch (_) {
      return orElse;
    }
  }
}

/// USB HID Descriptor.
///
/// The HID descriptor provides information about the HID device and references
/// to additional HID-specific descriptors (report descriptor, physical descriptor).
/// It immediately follows the interface descriptor in the configuration.
///
/// The HID descriptor includes:
/// - HID specification version
/// - Country code (for localization)
/// - Number and types of subordinate descriptors
/// - Lengths of subordinate descriptors
///
/// Example:
/// ```dart
/// final hidDesc = USBHIDDescriptor(
///   hidVersion: 0x0111, // HID 1.11
///   countryCode: 0x00,   // Not localized
///   reportDescriptorLength: 63,
/// );
/// ```
class USBHIDDescriptor implements USBDescriptor {
  /// Creates a HID descriptor.
  ///
  /// Parameters:
  /// - [hidVersion]: HID specification version in BCD (default: 0x0111 for HID 1.11)
  /// - [countryCode]: Hardware target country code (default: 0, not localized)
  /// - [reportDescriptorLength]: Length of report descriptor in bytes (required)
  /// - [physicalDescriptorLength]: Length of physical descriptor (default: 0, not used)
  const USBHIDDescriptor({
    this.hidVersion = 0x0111,
    this.countryCode = 0x00,
    required this.reportDescriptorLength,
    this.physicalDescriptorLength = 0,
  }) : assert(
         reportDescriptorLength > 0,
         'Report descriptor length must be greater than 0',
       );

  @override
  int get bLength => physicalDescriptorLength > 0 ? 12 : 9;

  @override
  int get bDescriptorType => HIDDescriptorType.hid.value;

  /// HID specification release number in BCD.
  ///
  /// Common values:
  /// - 0x0100: HID 1.0
  /// - 0x0110: HID 1.1
  /// - 0x0111: HID 1.11 (most common)
  ///
  /// Format: 0xJJMN where JJ = major version, M = minor, N = sub-minor
  final int hidVersion;

  /// Country code for hardware localization.
  ///
  /// Values:
  /// - 0x00: Not supported (most common)
  /// - 0x01-0x23: Various country codes (rarely used)
  ///
  /// Most devices use 0 as keyboard layouts are handled by the OS.
  final int countryCode;

  /// Length of the report descriptor in bytes.
  ///
  /// The report descriptor defines all inputs, outputs, and features
  /// of the HID device. This field tells the host how many bytes to
  /// request when fetching the report descriptor.
  final int reportDescriptorLength;

  /// Length of the physical descriptor in bytes.
  ///
  /// Optional descriptor describing physical characteristics. Most devices
  /// set this to 0 (no physical descriptor).
  final int physicalDescriptorLength;

  /// Number of subordinate descriptors.
  ///
  /// Always at least 1 (for the report descriptor). Incremented if a
  /// physical descriptor is present.
  int get numDescriptors => physicalDescriptorLength > 0 ? 2 : 1;

  /// BCD version major number.
  int get majorVersion => (hidVersion >> 8) & 0xFF;

  /// BCD version minor number.
  int get minorVersion => hidVersion & 0xFF;

  @override
  Uint8List toBytes() {
    final bytes = ByteData(bLength)
      ..setUint8(0, bLength)
      ..setUint8(1, bDescriptorType)
      ..setUint16(2, hidVersion, Endian.little)
      ..setUint8(4, countryCode)
      ..setUint8(5, numDescriptors)
      // First subordinate descriptor (report descriptor)
      ..setUint8(6, HIDDescriptorType.report.value)
      ..setUint16(7, reportDescriptorLength, Endian.little);

    if (physicalDescriptorLength > 0) {
      // Second subordinate descriptor (physical descriptor)
      bytes
        ..setUint8(9, HIDDescriptorType.physical.value)
        ..setUint16(10, physicalDescriptorLength, Endian.little);
    }

    return bytes.buffer.asUint8List();
  }

  @override
  String toString() =>
      'USBHIDDescriptor(HID $majorVersion.$minorVersion, '
      'reportLen=$reportDescriptorLength)';
}

/// HID report types.
enum HIDReportType {
  /// Input report (1).
  input(1),

  /// Output report (2).
  output(2),

  /// Feature report (3).
  feature(3);

  const HIDReportType(this.value);

  final int value;

  static HIDReportType? fromValue(int value) {
    try {
      return HIDReportType.values.firstWhere((t) => t.value == value);
    } catch (_) {
      return null;
    }
  }
}

// /// Configuration for HID endpoint topology and parameters.
// ///
// /// Provides convenient presets for common HID configurations:
// /// - Input-only (keyboard, mouse)
// /// - Bidirectional (game controllers, custom devices)
// /// - Output-only (LED controllers, rare)
// ///
// /// Example:
// /// ```dart
// /// // Simple input-only device
// /// final config = HIDEndpointConfig.inputOnly(pollingIntervalMs: 10);
// ///
// /// // Bidirectional game controller
// /// final config = HIDEndpointConfig.bidirectional(
// ///   pollingIntervalMs: 4,
// ///   maxPacketSize: 64,
// /// );
// /// ```
// sealed class HIDEndpointConfig {
//   const HIDEndpointConfig({
//     required this.pollingIntervalMs,
//     required this.maxPacketSize,
//   });
//
//   /// Creates an output-only HID configuration (single OUT endpoint).
//   ///
//   /// Rare configuration for devices that only receive data from the host.
//   /// Most devices use bidirectional or input-only.
//   ///
//   /// Example:
//   /// ```dart
//   /// HIDEndpointConfig.outputOnly(
//   ///   pollingIntervalMs: 10,
//   ///   maxPacketSize: 64,
//   /// )
//   /// ```
//   const factory HIDEndpointConfig.outputOnly({
//     int pollingIntervalMs,
//     int maxPacketSize,
//   }) = _OutputOnlyConfig;
//
//   /// Creates an input-only HID configuration (single IN endpoint).
//   ///
//   /// Common for keyboards, mice, and sensors. The device can send
//   /// reports to the host but cannot receive data via interrupt endpoint.
//   ///
//   /// Example:
//   /// ```dart
//   /// HIDEndpointConfig.inputOnly(
//   ///   pollingIntervalMs: 10,  // 100Hz
//   ///   maxPacketSize: 8,       // Standard keyboard size
//   /// )
//   /// ```
//   const factory HIDEndpointConfig.inputOnly({
//     int pollingIntervalMs,
//     int maxPacketSize,
//   }) = _InputOnlyConfig;
//
//   /// Creates a bidirectional HID configuration (IN + OUT endpoints).
//   ///
//   /// Common for game controllers, custom devices, and devices that
//   /// need to receive commands (LEDs, rumble, etc.) via interrupt endpoint.
//   ///
//   /// Example:
//   /// ```dart
//   /// HIDEndpointConfig.bidirectional(
//   ///   pollingIntervalMs: 4,   // 250Hz
//   ///   maxPacketSize: 64,      // Standard controller size
//   /// )
//   /// ```
//   const factory HIDEndpointConfig.bidirectional({
//     int pollingIntervalMs,
//     int maxPacketSize,
//   }) = _BidirectionalConfig;
//
//   /// Polling interval in milliseconds (1-255 for Full-Speed).
//   final int pollingIntervalMs;
//
//   /// Maximum packet size for interrupt endpoints.
//   final int maxPacketSize;
//
//   /// Number of endpoints this configuration uses (excluding EP0).
//   int get numEndpoints;
//
//   /// Generates the descriptor list for this endpoint configuration.
//   List<USBDescriptor> generateDescriptors();
//
//   /// Whether this config has an IN endpoint.
//   bool get hasInputEndpoint;
//
//   /// Whether this config has an OUT endpoint.
//   bool get hasOutputEndpoint;
// }
//
// /// Input-only HID configuration (IN endpoint only).
// final class _InputOnlyConfig extends HIDEndpointConfig {
//   const _InputOnlyConfig({
//     super.pollingIntervalMs = 10,
//     super.maxPacketSize = 64,
//   });
//
//   @override
//   int get numEndpoints => 1;
//
//   @override
//   bool get hasInputEndpoint => true;
//
//   @override
//   bool get hasOutputEndpoint => false;
//
//   @override
//   List<USBDescriptor> generateDescriptors() {
//     return [
//       EndpointTemplate(
//         address: const EndpointAddress.in_(EndpointNumber.ep1),
//         config: EndpointConfig.interrupt(
//           pollingMs: pollingIntervalMs,
//           maxPacketSize: maxPacketSize,
//         ),
//       ),
//     ];
//   }
// }
//
// /// Bidirectional HID configuration (IN + OUT endpoints).
// final class _BidirectionalConfig extends HIDEndpointConfig {
//   const _BidirectionalConfig({
//     super.pollingIntervalMs = 10,
//     super.maxPacketSize = 64,
//   });
//
//   @override
//   int get numEndpoints => 2;
//
//   @override
//   bool get hasInputEndpoint => true;
//
//   @override
//   bool get hasOutputEndpoint => true;
//
//   @override
//   List<USBDescriptor> generateDescriptors() {
//     return [
//       EndpointTemplate(
//         address: const EndpointAddress.in_(EndpointNumber.ep1),
//         config: EndpointConfig.interrupt(
//           pollingMs: pollingIntervalMs,
//           maxPacketSize: maxPacketSize,
//         ),
//       ),
//       EndpointTemplate(
//         address: const EndpointAddress.out(EndpointNumber.ep2),
//         config: EndpointConfig.interrupt(
//           pollingMs: pollingIntervalMs,
//           maxPacketSize: maxPacketSize,
//         ),
//       ),
//     ];
//   }
// }
//
// /// Output-only HID configuration (OUT endpoint only).
// final class _OutputOnlyConfig extends HIDEndpointConfig {
//   const _OutputOnlyConfig({
//     super.pollingIntervalMs = 10,
//     super.maxPacketSize = 64,
//   });
//
//   @override
//   int get numEndpoints => 1;
//
//   @override
//   bool get hasInputEndpoint => false;
//
//   @override
//   bool get hasOutputEndpoint => true;
//
//   @override
//   List<USBDescriptor> generateDescriptors() {
//     return [
//       EndpointTemplate(
//         address: const EndpointAddress.out(EndpointNumber.ep1),
//         config: EndpointConfig.interrupt(
//           pollingMs: pollingIntervalMs,
//           maxPacketSize: maxPacketSize,
//         ),
//       ),
//     ];
//   }
// }

/// Enhanced HIDFunctionFs with simplified endpoint configuration.
///
/// This version uses the new HIDEndpointConfig abstraction to make
/// endpoint setup more intuitive and reduce boilerplate.
///
/// Example:
/// ```dart
/// final gamepad = HIDFunctionFs(
///   name: 'gamepad',
///   reportDescriptor: gamepadReportDescriptor,
///   subclass: HIDSubclass.none,
///   protocol: HIDProtocol.none,
///   endpointConfig: HIDEndpointConfig.bidirectional(
///     pollingIntervalMs: 10,
///     maxPacketSize: 64,
///   ),
/// );
/// ```
// class HIDFunctionFs extends FunctionFs {
//   HIDFunctionFs({
//     required super.name,
//     required this.reportDescriptor,
//     required this.subclass,
//     required this.protocol,
//     required this.endpointConfig,
//     super.speeds,
//     super.strings,
//     super.flags,
//     super.debug,
//   }) : super(
//          descriptors: [
//            USBInterfaceDescriptor(
//              interfaceNumber: InterfaceNumber.interface0,
//              numEndpoints: EndpointCount(endpointConfig.numEndpoints),
//              interfaceClass: USBClass.hid,
//              interfaceSubClass: subclass.value,
//              interfaceProtocol: protocol.value,
//            ),
//            USBHIDDescriptor(reportDescriptorLength: reportDescriptor.length),
//            ...endpointConfig.generateDescriptors(),
//          ],
//        );
//
//   /// HID Report Descriptor defining the device's data format.
//   final Uint8List reportDescriptor;
//
//   /// HID device subclass (boot device or none).
//   final HIDSubclass subclass;
//
//   /// HID protocol (keyboard, mouse, or none).
//   final HIDProtocol protocol;
//
//   /// Endpoint configuration (input-only, bidirectional, output-only).
//   final HIDEndpointConfig endpointConfig;
//
//   /// Current idle rate for input reports (in 4ms units).
//   /// 0 means infinite (only report on change).
//   int _idleRate = 0;
//
//   /// Current HID protocol mode (boot or report).
//   HIDProtocol _currentProtocol = .none;
//
//   /// Getter for current protocol
//   HIDProtocol get currentProtocol => _currentProtocol;
//
//   /// Storage for cached report data by report type and ID.
//   final Map<(HIDReportType, int), Uint8List> _reports = {};
//
//   /// Interrupt IN endpoint for sending reports to the host.
//   EndpointInFile? _interruptIn;
//
//   /// Interrupt OUT endpoint for receiving reports from the host.
//   EndpointOutFile? _interruptOut;
//
//   @override
//   @mustCallSuper
//   void onEnable() {
//     super.onEnable();
//
//     // Get IN endpoint if present (always EP1 for input-only or bidirectional)
//     if (endpointConfig.hasInputEndpoint) {
//       try {
//         _interruptIn = getEndpoint<EndpointInFile>(1);
//         if (debug) log('IN endpoint ready: EP1');
//       } catch (e) {
//         log('Warning: Failed to get IN endpoint: $e');
//       }
//     }
//
//     // Get OUT endpoint:
//     // - EP2 for bidirectional (EP1 is IN)
//     // - EP1 for output-only (no IN endpoint)
//     if (endpointConfig.hasOutputEndpoint) {
//       final epNumber = endpointConfig.hasInputEndpoint ? 2 : 1;
//       try {
//         _interruptOut = getEndpoint<EndpointOutFile>(epNumber);
//         if (debug) log('OUT endpoint ready: EP$epNumber');
//       } catch (e) {
//         log('Warning: Failed to get OUT endpoint: $e');
//       }
//     }
//   }
//
//   @override
//   @mustCallSuper
//   void onSetup(int requestType, int request, int value, int index, int length) {
//     final type = USBRequestType.fromByte(requestType);
//     final recipient = USBRecipient.fromByte(requestType);
//     final direction = USBDirection.fromByte(requestType);
//
//     // Handle standard interface descriptor requests
//     if (type == .standard &&
//         recipient == .interface &&
//         direction.isIn &&
//         request == USBRequest.getDescriptor.value) {
//       final descriptorType = HIDDescriptorType.fromValue((value >> 8) & 0xFF);
//
//       if (descriptorType == .hid) {
//         if (debug) log('Providing HID descriptor');
//         final hidDesc = USBHIDDescriptor(
//           reportDescriptorLength: reportDescriptor.length,
//         );
//         final bytes = hidDesc.toBytes();
//         if (debug) bytes.xxd();
//
//         final sendLength = length < bytes.length ? length : bytes.length;
//         // IN transfer: write data, kernel handles status phase
//         ep0.write(bytes.sublist(0, sendLength));
//         return;
//       }
//
//       if (descriptorType == .report) {
//         if (debug) log('Providing HID report descriptor');
//         if (debug) reportDescriptor.xxd();
//
//         final sendLength = length < reportDescriptor.length
//             ? length
//             : reportDescriptor.length;
//         // IN transfer: write data, kernel handles status phase
//         ep0.write(reportDescriptor.sublist(0, sendLength));
//         return;
//       }
//     }
//
//     // Handle HID class-specific interface requests
//     if (type == .class_ && recipient == .interface) {
//       final hidRequest = HIDRequest.fromValue(request);
//
//       if (hidRequest == null) {
//         if (debug) log('Unknown HID request: ${request.toHex()}');
//         return ep0.halt();
//       }
//
//       return switch (hidRequest) {
//         .getReport => _handleGetReport(value, length, direction),
//         .setReport => _handleSetReport(value, length, direction),
//         .getIdle => _handleGetIdle(value, length, direction),
//         .setIdle => _handleSetIdle(value, direction),
//         .getProtocol => _handleGetProtocol(value, length, direction),
//         .setProtocol => _handleSetProtocol(value, direction),
//       };
//     }
//
//     // Fall back to standard USB request handling
//     super.onSetup(requestType, request, value, index, length);
//   }
//
//   /// Handles GET_REPORT request (IN transfer).
//   ///
//   /// Protocol: Device writes report data, kernel handles status phase.
//   void _handleGetReport(int value, int length, USBDirection direction) {
//     if (!direction.isIn || length == 0) {
//       if (debug) log('GET_REPORT: Invalid direction or length');
//       return ep0.halt();
//     }
//
//     final reportType = HIDReportType.fromValue((value >> 8) & 0xFF);
//     final reportId = value & 0xFF;
//
//     if (reportType == null) {
//       if (debug) log('GET_REPORT: Invalid report type: ${(value >> 8) & 0xFF}');
//       return ep0.halt();
//     }
//
//     if (debug) {
//       log('GET_REPORT: type=${reportType.name}, id=$reportId, len=$length');
//     }
//
//     // Try cached report first
//     var reportData = _reports[(reportType, reportId)];
//
//     // If not cached, call hook
//     if (reportData == null) {
//       reportData = onGetReport(reportType, reportId);
//       if (reportData == null) {
//         if (debug) log('GET_REPORT: No data available');
//         return ep0.halt();
//       }
//     }
//
//     // Prepare response matching requested length
//     final response = _prepareReportData(reportData, length);
//
//     // IN transfer - write data, kernel handles status
//     ep0.write(response);
//   }
//
//   /// Handles SET_REPORT request (OUT transfer).
//   ///
//   /// Protocol: Device reads data, then sends ACK with ep0.read(0).
//   void _handleSetReport(int value, int length, USBDirection direction) {
//     if (!direction.isOut) {
//       if (debug) log('SET_REPORT: Invalid direction');
//       return ep0.halt();
//     }
//
//     final reportType = HIDReportType.fromValue((value >> 8) & 0xFF);
//     final reportId = value & 0xFF;
//
//     if (reportType == null) {
//       if (debug) log('SET_REPORT: Invalid report type');
//       return ep0.halt();
//     }
//
//     if (debug) {
//       log('SET_REPORT: type=${reportType.name}, id=$reportId, len=$length');
//     }
//
//     // Read report data from EP0
//     final data = length > 0
//         ? Uint8List.fromList(ep0.read(length))
//         : Uint8List(0);
//
//     // Cache the report
//     _reports[(reportType, reportId)] = data;
//
//     // Notify subclass
//     onSetReport(reportType, reportId, data);
//
//     // OUT transfer - send ACK
//     ep0.read(0);
//   }
//
//   /// Handles GET_IDLE request (IN transfer).
//   ///
//   /// Protocol: Device writes idle rate, kernel handles status phase.
//   void _handleGetIdle(int value, int length, USBDirection direction) {
//     if (!direction.isIn || length != 1) {
//       if (debug) log('GET_IDLE: Invalid parameters');
//       return ep0.halt();
//     }
//
//     final reportId = value & 0xFF;
//
//     if (debug) {
//       log('GET_IDLE: reportId=$reportId, rate=$_idleRate');
//     }
//
//     // IN transfer - write response, kernel handles status
//     ep0.write(Uint8List(1)..[0] = _idleRate);
//   }
//
//   /// Handles SET_IDLE request (OUT transfer, no data phase).
//   ///
//   /// Protocol: Device processes request, then sends ACK with ep0.read(0).
//   void _handleSetIdle(int value, USBDirection direction) {
//     if (direction.isIn) {
//       if (debug) log('SET_IDLE: Invalid direction');
//       return ep0.halt();
//     }
//
//     final duration = (value >> 8) & 0xFF;
//     final reportId = value & 0xFF;
//
//     _idleRate = duration;
//
//     if (debug) {
//       log(
//         'SET_IDLE: reportId=$reportId, duration=$duration (${duration * 4}ms)',
//       );
//     }
//
//     onSetIdle(reportId, duration);
//
//     // OUT transfer - send ACK
//     ep0.read(0);
//   }
//
//   /// Handles GET_PROTOCOL request (IN transfer).
//   ///
//   /// Protocol: Device writes protocol, kernel handles status phase.
//   void _handleGetProtocol(int value, int length, USBDirection direction) {
//     if (!direction.isIn || length != 1 || value != 0) {
//       if (debug) log('GET_PROTOCOL: Invalid parameters');
//       return ep0.halt();
//     }
//
//     if (debug) {
//       log('GET_PROTOCOL: returning ${_currentProtocol.name}');
//     }
//
//     // IN transfer - write response, kernel handles status
//     ep0.write(Uint8List(1)..[0] = _currentProtocol.value);
//   }
//
//   /// Handles SET_PROTOCOL request (OUT transfer, no data phase).
//   ///
//   /// Protocol: Device processes request, then sends ACK with ep0.read(0).
//   void _handleSetProtocol(int value, USBDirection direction) {
//     if (!direction.isOut) {
//       if (debug) log('SET_PROTOCOL: Invalid direction');
//       return ep0.halt();
//     }
//
//     _currentProtocol = HIDProtocol.fromValue(value);
//
//     if (debug) {
//       log('SET_PROTOCOL: set to ${_currentProtocol.name}');
//     }
//
//     onSetProtocol(_currentProtocol);
//
//     // OUT transfer - send ACK
//     ep0.read(0);
//   }
//
//   /// Prepares report data to match the requested length.
//   Uint8List _prepareReportData(Uint8List data, int requestedLength) {
//     if (data.length == requestedLength) {
//       return data;
//     } else if (data.length > requestedLength) {
//       return Uint8List.fromList(data.sublist(0, requestedLength));
//     } else {
//       return Uint8List(requestedLength)..setRange(0, data.length, data);
//     }
//   }
//
//   // Public API for subclasses
//   /// Sends a HID input report to the host via the interrupt IN endpoint.
//   ///
//   /// The device must have an IN endpoint configured and be enabled by the host.
//   /// Throws [StateError] if the device doesn't have an IN endpoint or isn't enabled.
//   void sendReport(Uint8List report) {
//     if (_interruptIn == null) {
//       throw StateError(
//         'Device has no input endpoint. '
//         'Ensure endpointConfig.hasInputEndpoint is true and device is enabled.',
//       );
//     }
//     _interruptIn!.write(report);
//   }
//
//   /// Streams reports from the interrupt OUT endpoint.
//   ///
//   /// Throws [StateError] if the device doesn't have an OUT endpoint or isn't enabled.
//   Stream<Uint8List> streamReports() {
//     if (_interruptOut == null) {
//       throw StateError(
//         'Device has no output endpoint. '
//         'Ensure endpointConfig.hasOutputEndpoint is true and device is enabled.',
//       );
//     }
//     return _interruptOut!.stream();
//   }
//
//   /// Gets a cached report by type and ID.
//   Uint8List? getCachedReport(HIDReportType type, int reportId) {
//     return _reports[(type, reportId)];
//   }
//
//   /// Caches a report by type and ID.
//   void setCachedReport(HIDReportType type, int reportId, Uint8List data) {
//     _reports[(type, reportId)] = data;
//   }
//
//   // Override hooks for subclasses
//   /// Called when the host requests a report via GET_REPORT.
//   ///
//   /// Return the report data, or null to halt the request.
//   /// If not overridden and no cached report exists, the request is halted.
//   Uint8List? onGetReport(HIDReportType type, int reportId) {
//     return null;
//   }
//
//   /// Called when the host sends a report via SET_REPORT.
//   ///
//   /// The report has been cached and can be retrieved via [getCachedReport].
//   void onSetReport(HIDReportType type, int reportId, Uint8List data) {}
//
//   /// Called when the host changes the idle rate via SET_IDLE.
//   ///
//   /// Duration is in 4ms units. 0 means infinite (only report on change).
//   void onSetIdle(int reportId, int duration) {}
//
//   /// Called when the host changes the protocol via SET_PROTOCOL.
//   void onSetProtocol(HIDProtocol protocol) {}
// }

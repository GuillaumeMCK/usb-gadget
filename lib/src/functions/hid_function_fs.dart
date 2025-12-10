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

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '/src/core/utils.dart';
import '/usb_gadget.dart';

/// Configuration for HID endpoint topology and parameters.
///
/// Provides convenient presets for common HID configurations:
/// - Input-only (keyboard, mouse)
/// - Bidirectional (game controllers, custom devices)
/// - Output-only (LED controllers, rare)
///
/// Example:
/// ```dart
/// // Simple input-only device
/// final config = HIDFunctionFsConfig.inputOnly(pollingIntervalMs: 10);
///
/// // Bidirectional game controller
/// final config = HIDFunctionFsConfig.bidirectional(
///   pollingIntervalMs: 4,
///   maxPacketSize: 64,
/// );
/// ```
sealed class HIDFunctionFsConfig {
  const HIDFunctionFsConfig({
    required this.pollingIntervalMs,
    required this.maxPacketSize,
  });

  /// Creates an output-only HID configuration (single OUT endpoint).
  ///
  /// Rare configuration for devices that only receive data from the host.
  /// Most devices use bidirectional or input-only.
  ///
  /// Example:
  /// ```dart
  /// HIDFunctionFsConfig.outputOnly(
  ///   pollingIntervalMs: 10,
  ///   maxPacketSize: 64,
  /// )
  /// ```
  const factory HIDFunctionFsConfig.outputOnly({
    int pollingIntervalMs,
    int maxPacketSize,
  }) = _OutputOnlyConfig;

  /// Creates an input-only HID configuration (single IN endpoint).
  ///
  /// Common for keyboards, mice, and sensors. The device can send
  /// reports to the host but cannot receive data via interrupt endpoint.
  ///
  /// Example:
  /// ```dart
  /// HIDFunctionFsConfig.inputOnly(
  ///   pollingIntervalMs: 10,  // 100Hz
  ///   maxPacketSize: 8,       // Standard keyboard size
  /// )
  /// ```
  const factory HIDFunctionFsConfig.inputOnly({
    int pollingIntervalMs,
    int maxPacketSize,
  }) = _InputOnlyConfig;

  /// Creates a bidirectional HID configuration (IN + OUT endpoints).
  ///
  /// Common for game controllers, custom devices, and devices that
  /// need to receive commands (LEDs, rumble, etc.) via interrupt endpoint.
  ///
  /// Example:
  /// ```dart
  /// HIDFunctionFsConfig.bidirectional(
  ///   pollingIntervalMs: 4,   // 250Hz
  ///   maxPacketSize: 64,      // Standard controller size
  /// )
  /// ```
  const factory HIDFunctionFsConfig.bidirectional({
    int pollingIntervalMs,
    int maxPacketSize,
  }) = _BidirectionalConfig;

  /// Polling interval in milliseconds (1-255 for Full-Speed).
  final int pollingIntervalMs;

  /// Maximum packet size for interrupt endpoints.
  final int maxPacketSize;

  /// Number of endpoints this configuration uses (excluding EP0).
  int get numEndpoints;

  /// Generates the descriptor list for this endpoint configuration.
  List<USBDescriptor> get descriptors;

  /// Whether this config has an IN endpoint.
  bool get hasInputEndpoint;

  /// Whether this config has an OUT endpoint.
  bool get hasOutputEndpoint;
}

/// Input-only HID configuration (IN endpoint only).
final class _InputOnlyConfig extends HIDFunctionFsConfig {
  const _InputOnlyConfig({
    super.pollingIntervalMs = 10,
    super.maxPacketSize = 64,
  });

  @override
  int get numEndpoints => 1;

  @override
  bool get hasInputEndpoint => true;

  @override
  bool get hasOutputEndpoint => false;

  @override
  List<USBDescriptor> get descriptors => [
    EndpointTemplate(
      address: const EndpointAddress.in_(EndpointNumber.ep1),
      config: EndpointConfig.interrupt(
        pollingMs: pollingIntervalMs,
        maxPacketSize: maxPacketSize,
      ),
    ),
  ];
}

/// Bidirectional HID configuration (IN + OUT endpoints).
final class _BidirectionalConfig extends HIDFunctionFsConfig {
  const _BidirectionalConfig({
    super.pollingIntervalMs = 10,
    super.maxPacketSize = 64,
  });

  @override
  int get numEndpoints => 2;

  @override
  bool get hasInputEndpoint => true;

  @override
  bool get hasOutputEndpoint => true;

  @override
  List<USBDescriptor> get descriptors => [
    EndpointTemplate(
      address: const EndpointAddress.in_(EndpointNumber.ep1),
      config: EndpointConfig.interrupt(
        pollingMs: pollingIntervalMs,
        maxPacketSize: maxPacketSize,
      ),
    ),
    EndpointTemplate(
      address: const EndpointAddress.out(EndpointNumber.ep2),
      config: EndpointConfig.interrupt(
        pollingMs: pollingIntervalMs,
        maxPacketSize: maxPacketSize,
      ),
    ),
  ];
}

/// Output-only HID configuration (OUT endpoint only).
final class _OutputOnlyConfig extends HIDFunctionFsConfig {
  const _OutputOnlyConfig({
    super.pollingIntervalMs = 10,
    super.maxPacketSize = 64,
  });

  @override
  int get numEndpoints => 1;

  @override
  bool get hasInputEndpoint => false;

  @override
  bool get hasOutputEndpoint => true;

  @override
  List<USBDescriptor> get descriptors => [
    EndpointTemplate(
      address: const EndpointAddress.out(EndpointNumber.ep1),
      config: EndpointConfig.interrupt(
        pollingMs: pollingIntervalMs,
        maxPacketSize: maxPacketSize,
      ),
    ),
  ];
}

/// Enhanced HIDFunctionFs with simplified endpoint configuration.
///
/// This version uses the new HIDFunctionFsConfig abstraction to make
/// endpoint setup more intuitive and reduce boilerplate.
///
/// Example:
/// ```dart
/// final gamepad = HIDFunctionFs(
///   name: 'gamepad',
///   reportDescriptor: gamepadReportDescriptor,
///   subclass: HIDSubclass.none,
///   protocol: HIDProtocol.none,
///   endpointConfig: HIDFunctionFsConfig.bidirectional(
///     pollingIntervalMs: 10,
///     maxPacketSize: 64,
///   ),
/// );
/// ```
class HIDFunctionFs extends FunctionFs {
  HIDFunctionFs({
    required super.name,
    required this.reportDescriptor,
    required this.subclass,
    required this.protocol,
    required this.endpointConfig,
    super.speeds,
    super.strings,
    super.flags,
    super.debug,
  }) : super(
         descriptors: [
           USBInterfaceDescriptor(
             interfaceNumber: InterfaceNumber.interface0,
             numEndpoints: EndpointCount(endpointConfig.numEndpoints),
             interfaceClass: USBClass.hid,
             interfaceSubClass: subclass.value,
             interfaceProtocol: protocol.value,
           ),
           USBHIDDescriptor(reportDescriptorLength: reportDescriptor.length),
           ...endpointConfig.descriptors,
         ],
       );

  /// HID Report Descriptor defining the device's data format.
  final Uint8List reportDescriptor;

  /// HID device subclass (boot device or none).
  final HIDSubclass subclass;

  /// HID protocol (keyboard, mouse, or none).
  final HIDProtocol protocol;

  /// Endpoint configuration (input-only, bidirectional, output-only).
  final HIDFunctionFsConfig endpointConfig;

  /// Current idle rate for input reports (in 4ms units).
  /// 0 means infinite (only report on change).
  int _idleRate = 0;

  /// Current HID protocol mode (boot or report).
  HIDProtocol _currentProtocol = .none;

  /// Getter for current protocol
  HIDProtocol get currentProtocol => _currentProtocol;

  /// Storage for cached report data by report type and ID.
  final Map<(HIDReportType, int), Uint8List> _reports = {};

  /// Interrupt IN endpoint for sending reports to the host.
  EndpointInFile? _interruptIn;

  /// Interrupt OUT endpoint for receiving reports from the host.
  EndpointOutFile? _interruptOut;

  @override
  @protected
  void onEnable() {
    // Get IN endpoint if present (always EP1 for input-only or bidirectional)
    if (endpointConfig.hasInputEndpoint) {
      try {
        _interruptIn = getEndpoint<EndpointInFile>(1);
        if (debug) log('IN endpoint ready: EP1');
      } catch (e) {
        log('Warning: Failed to get IN endpoint: $e');
      }
    }

    // Get OUT endpoint:
    // - EP2 for bidirectional (EP1 is IN)
    // - EP1 for output-only (no IN endpoint)
    if (endpointConfig.hasOutputEndpoint) {
      final epNumber = endpointConfig.hasInputEndpoint ? 2 : 1;
      try {
        _interruptOut = getEndpoint<EndpointOutFile>(epNumber);
        if (debug) log('OUT endpoint ready: EP$epNumber');
      } catch (e) {
        log('Warning: Failed to get OUT endpoint: $e');
      }
    }
    super.onEnable();
  }

  @override
  @protected
  void onSetup(int requestType, int request, int value, int index, int length) {
    final type = USBRequestType.fromByte(requestType);
    final recipient = USBRecipient.fromByte(requestType);
    final direction = USBDirection.fromByte(requestType);

    // Handle standard interface descriptor requests
    if (type == .standard &&
        recipient == .interface &&
        direction.isIn &&
        request == USBRequest.getDescriptor.value) {
      final descriptorType = HIDDescriptorType.fromValue((value >> 8) & 0xFF);

      if (descriptorType == .hid) {
        if (debug) log('Providing HID descriptor');
        final hidDesc = USBHIDDescriptor(
          reportDescriptorLength: reportDescriptor.length,
        );
        final bytes = hidDesc.toBytes();
        if (debug) bytes.xxd();

        final sendLength = length < bytes.length ? length : bytes.length;
        ep0.write(bytes.sublist(0, sendLength));
        return;
      }

      if (descriptorType == .report) {
        if (debug) log('Providing HID report descriptor');
        if (debug) reportDescriptor.xxd();

        final sendLength = length < reportDescriptor.length
            ? length
            : reportDescriptor.length;
        // IN transfer: write data, kernel handles status phase
        ep0.write(reportDescriptor.sublist(0, sendLength));
        return;
      }
    }

    // Handle HID class-specific interface requests
    if (type == .class_ && recipient == .interface) {
      final hidRequest = HIDRequest.fromValue(request);

      if (hidRequest == null) {
        if (debug) log('Unknown HID request: ${request.toHex()}');
        return ep0.halt();
      }

      return switch (hidRequest) {
        .getReport => _handleGetReport(value, length, direction),
        .setReport => _handleSetReport(value, length, direction),
        .getIdle => _handleGetIdle(value, length, direction),
        .setIdle => _handleSetIdle(value, direction),
        .getProtocol => _handleGetProtocol(value, length, direction),
        .setProtocol => _handleSetProtocol(value, direction),
      };
    }

    // Fall back to standard USB request handling
    super.onSetup(requestType, request, value, index, length);
  }

  /// Handles GET_REPORT request (IN transfer).
  ///
  /// Protocol: Device writes report data, kernel handles status phase.
  void _handleGetReport(int value, int length, USBDirection direction) {
    if (!direction.isIn || length == 0) {
      if (debug) log('GET_REPORT: Invalid direction or length');
      return ep0.halt();
    }

    final reportType = HIDReportType.fromValue((value >> 8) & 0xFF);
    final reportId = value & 0xFF;

    if (reportType == null) {
      if (debug) log('GET_REPORT: Invalid report type: ${(value >> 8) & 0xFF}');
      return ep0.halt();
    }

    if (debug) {
      log('GET_REPORT: type=${reportType.name}, id=$reportId, len=$length');
    }

    // Try cached report first
    var reportData = _reports[(reportType, reportId)];

    // If not cached, call hook
    if (reportData == null) {
      reportData = onGetReport(reportType, reportId);
      if (reportData == null) {
        if (debug) log('GET_REPORT: No data available');
        return ep0.halt();
      }
    }

    // Prepare response matching requested length
    final response = _prepareReportData(reportData, length);

    // IN transfer - write data, kernel handles status
    ep0.write(response);
  }

  /// Handles SET_REPORT request (OUT transfer).
  ///
  /// Protocol: Device reads data, then sends ACK with ep0.read(0).
  void _handleSetReport(int value, int length, USBDirection direction) {
    if (!direction.isOut) {
      if (debug) log('SET_REPORT: Invalid direction');
      return ep0.halt();
    }

    final reportType = HIDReportType.fromValue((value >> 8) & 0xFF);
    final reportId = value & 0xFF;

    if (reportType == null) {
      if (debug) log('SET_REPORT: Invalid report type');
      return ep0.halt();
    }

    if (debug) {
      log('SET_REPORT: type=${reportType.name}, id=$reportId, len=$length');
    }

    // Read report data from EP0
    final data = length > 0
        ? Uint8List.fromList(ep0.read(length))
        : Uint8List(0);

    // Cache the report
    _reports[(reportType, reportId)] = data;

    // Notify subclass
    onSetReport(reportType, reportId, data);

    // OUT transfer - send ACK
    ep0.read(0);
  }

  /// Handles GET_IDLE request (IN transfer).
  ///
  /// Protocol: Device writes idle rate, kernel handles status phase.
  void _handleGetIdle(int value, int length, USBDirection direction) {
    if (!direction.isIn || length != 1) {
      if (debug) log('GET_IDLE: Invalid parameters');
      return ep0.halt();
    }

    final reportId = value & 0xFF;

    if (debug) {
      log('GET_IDLE: reportId=$reportId, rate=$_idleRate');
    }

    // IN transfer - write response, kernel handles status
    ep0.write(Uint8List(1)..[0] = _idleRate);
  }

  /// Handles SET_IDLE request (OUT transfer, no data phase).
  ///
  /// Protocol: Device processes request, then sends ACK with ep0.read(0).
  void _handleSetIdle(int value, USBDirection direction) {
    if (direction.isIn) {
      if (debug) log('SET_IDLE: Invalid direction');
      return ep0.halt();
    }

    final duration = (value >> 8) & 0xFF;
    final reportId = value & 0xFF;

    _idleRate = duration;

    if (debug) {
      log(
        'SET_IDLE: reportId=$reportId, duration=$duration (${duration * 4}ms)',
      );
    }

    onSetIdle(reportId, duration);

    // OUT transfer - send ACK
    ep0.read(0);
  }

  /// Handles GET_PROTOCOL request (IN transfer).
  ///
  /// Protocol: Device writes protocol, kernel handles status phase.
  void _handleGetProtocol(int value, int length, USBDirection direction) {
    if (!direction.isIn || length != 1 || value != 0) {
      if (debug) log('GET_PROTOCOL: Invalid parameters');
      return ep0.halt();
    }

    if (debug) {
      log('GET_PROTOCOL: returning ${_currentProtocol.name}');
    }

    // IN transfer - write response, kernel handles status
    ep0.write(Uint8List(1)..[0] = _currentProtocol.value);
  }

  /// Handles SET_PROTOCOL request (OUT transfer, no data phase).
  ///
  /// Protocol: Device processes request, then sends ACK with ep0.read(0).
  void _handleSetProtocol(int value, USBDirection direction) {
    if (!direction.isOut) {
      if (debug) log('SET_PROTOCOL: Invalid direction');
      return ep0.halt();
    }

    _currentProtocol = HIDProtocol.fromValue(value);

    if (debug) {
      log('SET_PROTOCOL: set to ${_currentProtocol.name}');
    }

    onSetProtocol(_currentProtocol);

    // OUT transfer - send ACK
    ep0.read(0);
  }

  /// Prepares report data to match the requested length.
  Uint8List _prepareReportData(Uint8List data, int requestedLength) {
    if (data.length == requestedLength) {
      return data;
    } else if (data.length > requestedLength) {
      return Uint8List.fromList(data.sublist(0, requestedLength));
    } else {
      return Uint8List(requestedLength)..setRange(0, data.length, data);
    }
  }

  // Public API for subclasses
  /// Sends a HID input report to the host via the interrupt IN endpoint.
  /// The device must have an IN endpoint configured and be enabled by the host.
  void sendReport(Uint8List report) {
    assert(
      _interruptIn != null,
      'Device has no input endpoint. '
      'Ensure endpointConfig.hasInputEndpoint is true and device is enabled.',
    );
    _interruptIn!.write(report);
  }

  /// Streams reports from the interrupt OUT endpoint.
  Stream<Uint8List> streamReports() {
    assert(
      _interruptOut != null,
      'Device has no output endpoint. '
      'Ensure endpointConfig.hasOutputEndpoint is true and device is enabled.',
    );
    return _interruptOut!.stream();
  }

  /// Gets a cached report by type and ID.
  Uint8List? getCachedReport(HIDReportType type, int reportId) {
    return _reports[(type, reportId)];
  }

  /// Caches a report by type and ID.
  void setCachedReport(HIDReportType type, int reportId, Uint8List data) {
    _reports[(type, reportId)] = data;
  }

  // Override hooks for subclasses
  /// Called when the host requests a report via GET_REPORT.
  ///
  /// Return the report data, or null to halt the request.
  /// If not overridden and no cached report exists, the request is halted.
  Uint8List? onGetReport(HIDReportType type, int reportId) {
    return null;
  }

  /// Called when the host sends a report via SET_REPORT.
  ///
  /// The report has been cached and can be retrieved via [getCachedReport].
  void onSetReport(HIDReportType type, int reportId, Uint8List data) {}

  /// Called when the host changes the idle rate via SET_IDLE.
  ///
  /// Duration is in 4ms units. 0 means infinite (only report on change).
  void onSetIdle(int reportId, int duration) {}

  /// Called when the host changes the protocol via SET_PROTOCOL.
  void onSetProtocol(HIDProtocol protocol) {}
}

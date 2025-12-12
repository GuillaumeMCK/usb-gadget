import 'dart:typed_data';

import 'package:meta/meta.dart';

import '/usb_gadget.dart';

/// Configuration for HID endpoint topology and parameters.
///
/// Provides convenient presets for common HID configurations:
/// - Input-only (keyboard, mouse)
/// - Bidirectional (game controllers, custom devices)
/// - Output-only (LED controllers, rare)
sealed class HIDFunctionFsConfig {
  const HIDFunctionFsConfig({
    required this.pollingIntervalMs,
    required this.maxPacketSize,
  });

  /// Creates an output-only HID configuration (single OUT endpoint).
  const factory HIDFunctionFsConfig.outputOnly({
    int pollingIntervalMs,
    int maxPacketSize,
  }) = _OutputOnlyConfig;

  /// Creates an input-only HID configuration (single IN endpoint).
  const factory HIDFunctionFsConfig.inputOnly({
    int pollingIntervalMs,
    int maxPacketSize,
  }) = _InputOnlyConfig;

  /// Creates a bidirectional HID configuration (IN + OUT endpoints).
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
class HIDFunctionFs extends FunctionFs with USBGadgetLogger {
  HIDFunctionFs({
    required super.name,
    required this.reportDescriptor,
    required this.subclass,
    required this.protocol,
    required this.endpointConfig,
    super.speeds,
    super.strings,
    super.flags,
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
  HIDProtocol _currentProtocol = HIDProtocol.none;

  /// Getter for current protocol.
  HIDProtocol get currentProtocol => _currentProtocol;

  /// Interrupt IN endpoint for sending reports to the host.
  EndpointInFile? _interruptIn;

  /// Interrupt OUT endpoint for receiving reports from the host.
  EndpointOutFile? _interruptOut;

  @override
  @mustCallSuper
  void onEnable() {
    // Get IN endpoint if present (always EP1 for input-only or bidirectional)
    if (endpointConfig.hasInputEndpoint) {
      try {
        _interruptIn = getEndpoint<EndpointInFile>(1);
        log?.info('IN endpoint ready: EP1');
      } catch (err) {
        log?.error('Failed to get IN endpoint: $err');
      }
    }

    // Get OUT endpoint:
    // - EP2 for bidirectional (EP1 is IN)
    // - EP1 for output-only (no IN endpoint)
    if (endpointConfig.hasOutputEndpoint) {
      final epNumber = endpointConfig.hasInputEndpoint ? 2 : 1;
      try {
        _interruptOut = getEndpoint<EndpointOutFile>(epNumber);
        log?.info('OUT endpoint ready: EP$epNumber');
      } catch (err) {
        log?.error('Failed to get OUT endpoint: $err');
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
    if (type == USBRequestType.standard &&
        recipient == USBRecipient.interface &&
        direction.isIn &&
        request == USBRequest.getDescriptor.value) {
      final descriptorType = HIDDescriptorType.fromValue((value >> 8) & 0xFF);
      if (descriptorType == HIDDescriptorType.hid) {
        log?.info('Providing HID descriptor');
        final hidDesc = USBHIDDescriptor(
          reportDescriptorLength: reportDescriptor.length,
        );
        final bytes = hidDesc.toBytes();
        if (log?.level == .debug) bytes.xxd();
        final sendLength = length < bytes.length ? length : bytes.length;
        ep0.write(bytes.sublist(0, sendLength));
        return;
      }
      if (descriptorType == HIDDescriptorType.report) {
        log?.info('Providing HID report descriptor');
        if (log?.level == .debug) reportDescriptor.xxd();
        final sendLength = length < reportDescriptor.length
            ? length
            : reportDescriptor.length;
        ep0.write(reportDescriptor.sublist(0, sendLength));
        return;
      }
    }

    // Handle HID class-specific interface requests
    if (type == USBRequestType.class_ && recipient == USBRecipient.interface) {
      final hidRequest = HIDRequest.fromValue(request);
      if (hidRequest == null) {
        log?.warn('Unknown HID request: ${request.toHex()}');
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
  void _handleGetReport(int value, int length, USBDirection direction) {
    if (!direction.isIn || length == 0) {
      log?.error('GET_REPORT: Invalid direction or length');
      return ep0.halt();
    }
    final reportType = HIDReportType.fromValue((value >> 8) & 0xFF);
    final reportId = value & 0xFF;
    if (reportType == null) {
      log?.error('GET_REPORT: Invalid report type: ${(value >> 8) & 0xFF}');
      return ep0.halt();
    }
    log?.info('GET_REPORT: type=${reportType.name}, id=$reportId, len=$length');

    final reportData = onGetReport(reportType, reportId);
    if (reportData == null) {
      log?.error('GET_REPORT: No data available');
      return ep0.halt();
    }
    // Prepare response matching requested length
    final response = _prepareReportData(reportData, length);
    // IN transfer - write data, kernel handles status
    ep0.write(response);
  }

  /// Handles SET_REPORT request (OUT transfer).
  void _handleSetReport(int value, int length, USBDirection direction) {
    if (!direction.isOut) {
      log?.error('SET_REPORT: Invalid direction');
      return ep0.halt();
    }
    final reportType = HIDReportType.fromValue((value >> 8) & 0xFF);
    final reportId = value & 0xFF;
    if (reportType == null) {
      log?.error('SET_REPORT: Invalid report type');
      return ep0.halt();
    }
    log?.info('SET_REPORT: type=${reportType.name}, id=$reportId, len=$length');

    // Read report data from EP0
    final data = length > 0
        ? Uint8List.fromList(ep0.read(length))
        : Uint8List(0);
    // Notify subclass
    onSetReport(reportType, reportId, data);
    // OUT transfer - send ACK
    ep0.read(0);
  }

  /// Handles GET_IDLE request (IN transfer).
  void _handleGetIdle(int value, int length, USBDirection direction) {
    if (!direction.isIn || length != 1) {
      log?.error('GET_IDLE: Invalid parameters');
      return ep0.halt();
    }
    final reportId = value & 0xFF;
    log?.info('GET_IDLE: reportId=$reportId, rate=$_idleRate');
    // IN transfer - write response, kernel handles status
    ep0.write(Uint8List(1)..[0] = _idleRate);
  }

  /// Handles SET_IDLE request (OUT transfer, no data phase).
  void _handleSetIdle(int value, USBDirection direction) {
    if (direction.isIn) {
      log?.error('SET_IDLE: Invalid direction');
      return ep0.halt();
    }
    final duration = (value >> 8) & 0xFF;
    final reportId = value & 0xFF;
    _idleRate = duration;
    log?.info(
      'SET_IDLE: reportId=$reportId, duration=$duration (${duration * 4}ms)',
    );
    onSetIdle(reportId, duration);
    // OUT transfer - send ACK
    ep0.read(0);
  }

  /// Handles GET_PROTOCOL request (IN transfer).
  void _handleGetProtocol(int value, int length, USBDirection direction) {
    if (!direction.isIn || length != 1 || value != 0) {
      log?.error('GET_PROTOCOL: Invalid parameters');
      return ep0.halt();
    }
    log?.info('GET_PROTOCOL: returning ${_currentProtocol.name}');
    // IN transfer - write response, kernel handles status
    ep0.write(Uint8List(1)..[0] = _currentProtocol.value);
  }

  /// Handles SET_PROTOCOL request (OUT transfer, no data phase).
  void _handleSetProtocol(int value, USBDirection direction) {
    if (!direction.isOut) {
      log?.error('SET_PROTOCOL: Invalid direction');
      return ep0.halt();
    }
    _currentProtocol = HIDProtocol.fromValue(value);
    log?.info('SET_PROTOCOL: set to ${_currentProtocol.name}');
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
  void sendReport(Uint8List report) {
    assert(
      _interruptIn != null,
      'Device has no input endpoint. Ensure endpointConfig.hasInputEndpoint '
      'is true and device is enabled.',
    );
    _interruptIn!.write(report);
  }

  /// Streams reports from the interrupt OUT endpoint.
  Stream<Uint8List> streamReports() {
    assert(
      _interruptOut != null,
      'Device has no output endpoint. Ensure endpointConfig.hasOutputEndpoint '
      'is true and device is enabled.',
    );
    return _interruptOut!.stream();
  }

  // Override hooks for subclasses

  /// Called when the host requests a report via GET_REPORT.
  Uint8List? onGetReport(HIDReportType type, int reportId) {
    return null;
  }

  /// Called when the host sends a report via SET_REPORT.
  void onSetReport(HIDReportType type, int reportId, Uint8List data) {}

  /// Called when the host changes the idle rate via SET_IDLE.
  void onSetIdle(int reportId, int duration) {}

  /// Called when the host changes the protocol via SET_PROTOCOL.
  void onSetProtocol(HIDProtocol protocol) {}
}

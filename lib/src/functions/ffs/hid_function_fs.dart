import 'dart:math' as math;
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
    required this.maxPacketSize,
    this.pollingIntervalMs = 10,
    this.reportIntervalMs = 10,
  });

  /// Creates an output-only HID configuration (single OUT endpoint).
  const factory HIDFunctionFsConfig.outputOnly({
    int pollingIntervalMs,
    int maxPacketSize,
    EndpointNumber endpointNumber,
  }) = _OutputOnlyConfig;

  /// Creates an input-only HID configuration (single IN endpoint).
  const factory HIDFunctionFsConfig.inputOnly({
    int reportIntervalMs,
    int maxPacketSize,
    EndpointNumber endpointNumber,
  }) = _InputOnlyConfig;

  /// Creates a bidirectional HID configuration (IN + OUT endpoints).
  const factory HIDFunctionFsConfig.bidirectional({
    int pollingIntervalMs,
    int reportIntervalMs,
    int maxPacketSize,
    EndpointNumber inEndpointNumber,
    EndpointNumber outEndpointNumber,
  }) = _BidirectionalConfig;

  /// Polling interval in milliseconds (for OUT endpoint, if applicable).
  final int pollingIntervalMs;

  /// Report interval in milliseconds (for IN endpoint, if applicable).
  final int reportIntervalMs;

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

  /// Endpoint number for IN transfers (null if not applicable).
  EndpointNumber? get inEndpointNumber => null;

  /// Endpoint number for OUT transfers (null if not applicable).
  EndpointNumber? get outEndpointNumber => null;
}

/// Input-only HID configuration (IN endpoint only).
final class _InputOnlyConfig extends HIDFunctionFsConfig {
  const _InputOnlyConfig({
    super.reportIntervalMs,
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
    EndpointTemplate(
      address: EndpointAddress.in_(endpointNumber),
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
    super.pollingIntervalMs,
    super.reportIntervalMs,
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
    EndpointTemplate(
      address: EndpointAddress.in_(inEndpointNumber),
      config: EndpointConfig.interrupt(
        pollingMs: reportIntervalMs,
        maxPacketSize: maxPacketSize,
      ),
    ),
    EndpointTemplate(
      address: EndpointAddress.out(outEndpointNumber),
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
    EndpointTemplate(
      address: EndpointAddress.out(endpointNumber),
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
    required this.config,
    super.speeds,
    super.strings,
    super.flags,
  }) : super(
         descriptors: [
           USBInterfaceDescriptor(
             interfaceNumber: .interface0,
             numEndpoints: EndpointCount(config.numEndpoints),
             interfaceClass: .hid,
             interfaceSubClass: subclass.value,
             interfaceProtocol: protocol.value,
           ),
           USBHIDDescriptor(reportLenght: reportDescriptor.length),
           ...config.descriptors,
         ],
       );

  /// HID Report Descriptor defining the device's data format.
  final Uint8List reportDescriptor;

  /// HID device subclass (boot device or none).
  final HIDSubclass subclass;

  /// HID protocol (keyboard, mouse, or none).
  final HIDProtocol protocol;

  /// Endpoint configuration (input-only, bidirectional, output-only).
  final HIDFunctionFsConfig config;

  /// Idle rates per report ID (in 4ms units).
  /// Key: Report ID (0 = all reports)
  /// Value: Idle rate (0 = infinite, only report on change)
  final Map<int, int> _idleRates = {};

  /// Current HID protocol mode (boot or report).
  late HIDProtocol _currentProtocol;

  /// Getter for current protocol.
  HIDProtocol get currentProtocol => _currentProtocol;

  /// Interrupt IN endpoint for sending reports to the host.
  EndpointInFile? _interruptIn;

  /// Interrupt OUT endpoint for receiving reports from the host.
  EndpointOutFile? _interruptOut;

  /// Interrupt IN endpoint for sending reports to the host.
  EndpointInFile get epIn {
    if (_interruptIn == null) {
      throw StateError(
        'Device has no input endpoint. Ensure config.hasInputEndpoint '
        'is true and device is enabled.',
      );
    }
    return _interruptIn!;
  }

  /// Interrupt OUT endpoint for receiving reports from the host.
  EndpointOutFile get epOut {
    if (_interruptOut == null) {
      throw StateError(
        'Device has no output endpoint. Ensure config.hasOutputEndpoint '
        'is true and device is enabled.',
      );
    }
    return _interruptOut!;
  }

  @override
  @mustCallSuper
  void onEnable() {
    _currentProtocol = protocol;
    if (config.hasInputEndpoint) {
      _interruptIn ??= getEndpoint<EndpointInFile>(config.inEndpointNumber!);
    }

    if (config.hasOutputEndpoint) {
      _interruptOut ??= getEndpoint<EndpointOutFile>(config.outEndpointNumber!);
    }

    super.onEnable();
  }

  @override
  void onDisable() {
    // Null out endpoint references to help GC
    _interruptIn = null;
    _interruptOut = null;
    super.onDisable();
  }

  @override
  @mustCallSuper
  void onSetup(
    int bmRequestType,
    int bRequest,
    int wValue,
    int wIndex,
    int wLength,
  ) {
    log?.debug(
      'HID Setup: '
      'bmRequestType=${bmRequestType.toHex()} '
      'bRequest=${bRequest.toHex()} '
      'wValue=${wValue.toHex()} '
      'wIndex=${wIndex.toHex()} '
      'wLength=${wLength.toHex()}',
    );

    final type = USBRequestType.fromByte(bmRequestType);
    final direction = USBDirection.fromByte(bmRequestType);
    final recipient = USBRecipient.fromByte(bmRequestType);

    // Standard requests for HID interface
    if (type == .standard) {
      final stdRequest = USBRequest.fromByte(bRequest);

      switch ((stdRequest, direction)) {
        case (.getDescriptor, .in_):
          switch (HIDDescriptorType.fromByte(wValue.byte(1))) {
            case .hid:
              log?.debug('Providing HID descriptor');
              final hidDesc = USBHIDDescriptor(
                reportLenght: reportDescriptor.length,
              );
              final bytes = hidDesc.toBytes();
              return ep0.write(bytes);

            case .report:
              log?.debug('Providing HID report descriptor');
              return ep0.write(reportDescriptor);
            default:
          }
        default:
      }

      return super.onSetup(bmRequestType, bRequest, wValue, wIndex, wLength);
    }

    if (type == .class_ && recipient == .interface) {
      final hidRequest = HIDRequest.fromByte(bRequest);

      switch ((hidRequest, direction)) {
        case (.getReport, .in_):
          final reportId = wValue.byte(0);
          final reportType = HIDReportType.fromByte(wValue.byte(1));
          final data = onGetReport(reportType, reportId);

          if (data == null) {
            log?.error('GET_REPORT: No data available – stalling');
            return ep0.halt();
          }
          return ep0.write(data.sublist(0, wLength));

        case (.setReport, .out):
          final reportId = wValue.byte(0);
          final reportType = HIDReportType.fromByte(wValue.byte(1));

          final data = ep0.read(wLength);
          onSetReport(reportType, reportId, data);
          return ep0.ack();

        case (.getIdle, .in_):
          if (wLength != 1) {
            return ep0.halt();
          }

          final reportId = wValue.byte(0);
          final idleRate = _idleRates[reportId] ?? _idleRates[0] ?? 0;

          return ep0.write(Uint8List(1)..[0] = idleRate);

        case (.setIdle, .out):
          final reportId = wValue.byte(0);
          final duration = wValue.byte(1);

          if (reportId == 0) {
            _idleRates[0] = duration;
          } else {
            _idleRates[reportId] = duration;
          }
          onSetIdle(reportId, duration);
          return ep0.ack();

        case (.getProtocol, .in_):
          if (wLength != 1) {
            return ep0.halt();
          }
          return ep0.write(Uint8List(1)..[0] = _currentProtocol.value);

        case (.setProtocol, .out):
          _currentProtocol = HIDProtocol.fromByte(wValue.byte(0));
          onSetProtocol(_currentProtocol);
          return ep0.ack();

        default:
          return ep0.halt();
      }
    }

    // fall back to base class for anything else
    return super.onSetup(bmRequestType, bRequest, wValue, wIndex, wLength);
  }

  /// Called when the host requests a report via GET_REPORT.
  ///
  /// Subclasses MUST override this method to provide report data.
  /// Return null to STALL the request.
  ///
  /// The returned data should NOT include the Report ID byte - it will be
  /// prepended automatically if reportId != 0.
  @protected
  Uint8List? onGetReport(HIDReportType type, int reportId) {
    log?.warn('onGetReport not overridden - returning null (will STALL)');
    return null;
  }

  /// Called when the host sends a report via SET_REPORT.
  @protected
  void onSetReport(HIDReportType type, int reportId, Uint8List data) {}

  /// Called when the host changes the idle rate via SET_IDLE.
  @protected
  void onSetIdle(int reportId, int duration) {}

  /// Called when the host changes the protocol via SET_PROTOCOL.
  @protected
  void onSetProtocol(HIDProtocol protocol) {
    _currentProtocol = protocol;
  }

  @override
  @mustCallSuper
  void release() {
    _idleRates.clear();
    _interruptIn = null;
    _interruptOut = null;
    super.release();
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '/src/logger/logger.dart';
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
           USBHIDDescriptor(reportDescriptorLength: reportDescriptor.length),
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
    // Initialize protocol from constructor parameter
    _currentProtocol = protocol;

    // Get IN endpoint if present
    if (config.hasInputEndpoint) {
      final epNum = config.inEndpointNumber!;
      try {
        _interruptIn = getEndpoint<EndpointInFile>(epNum);
        log?.info('IN endpoint ready: $epNum');
      } catch (err) {
        log?.error('Failed to get IN endpoint: $err');
      }
    }

    // Get OUT endpoint if present
    if (config.hasOutputEndpoint) {
      final epNum = config.outEndpointNumber!;
      try {
        _interruptOut = getEndpoint<EndpointOutFile>(epNum);
        log?.info('OUT endpoint ready: $epNum');
      } catch (err) {
        log?.error('Failed to get OUT endpoint: $err');
      }
    }
    super.onEnable();
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
    final recipient = USBRecipient.fromByte(bmRequestType);
    final direction = USBDirection.fromByte(bmRequestType);
    final request = type == .standard
        ? USBRequest.fromByte(bRequest)
        : HIDRequest.fromByte(bRequest);

    return switch (type) {
      /// Handle HID standard interface requests
      .standard when request is USBRequest => switch ((request, direction)) {
        (.getDescriptor, .in_) => switch (HIDDescriptorType.fromByte(
          wValue.byte1,
        )) {
          .hid => () {
            log?.debug('Providing HID descriptor');
            final hidDesc = USBHIDDescriptor(
              reportDescriptorLength: reportDescriptor.length,
            );
            final bytes = hidDesc.toBytes();
            log?.debug(bytes.xxd());
            final size = wLength < bytes.length ? wLength : bytes.length;
            // Write completes IN transfer, .little
            ep0.write(bytes.sublist(0, size));
          }(),
          .report => () {
            log?.debug(
              'Providing HID report descriptor:${reportDescriptor.xxd()}',
            );
            final size = math.min(wLength, reportDescriptor.length);
            // Write completes IN transfer, .little
            ep0.write(reportDescriptor.sublist(0, size));
          }(),
          _ => super.onSetup(bmRequestType, bRequest, wValue, wIndex, wLength),
        },
        _ => super.onSetup(bmRequestType, bRequest, wValue, wIndex, wLength),
      },

      /// Handle HID class-specific interface requests
      .class_ => switch ((HIDRequest.fromByte(bRequest), direction)) {
        (.getReport, .in_) => () {
          final reportId = wValue.byte0;
          final reportType = HIDReportType.fromByte(wValue.byte1);
          log?.info(
            'GET_REPORT: type=${reportType.name}, id=$reportId, len=$wLength',
          );
          final data = onGetReport(reportType, reportId);
          if (data == null) {
            log?.error('GET_REPORT: No data available');
            return ep0.halt();
          }

          final response = switch (reportId) {
            0 => data,
            _ => Uint8List.fromList([reportId, ...data]),
          };

          // Write completes IN transfer, .little
          ep0.write(switch ((response.length, wLength)) {
            (final a, final b) when a == b => response,
            (final a, final b) when a > b => .fromList(response.sublist(0, b)),
            (final a, final b) when a < b => .new(b)..setRange(0, a, response),
            _ => throw StateError('Unreachable'),
          });
        }(),
        (.setReport, .out) => () {
          final reportId = wValue.byte0;
          final reportType = HIDReportType.fromByte(wValue.byte1);
          log?.info(
            'SET_REPORT: type=${reportType.name}, id=$reportId, len=$wLength',
          );
          final data = ep0.read(wLength);
          onSetReport(reportType, reportId, data);
        }(),
        (.getIdle, .in_) => () {
          if (wLength != 1) {
            log?.error('GET_IDLE: Invalid parameters');
            return ep0.halt();
          }
          final reportId = wValue.byte0;
          // Look up idle rate for this specific report ID, or use "all reports" (0)
          final idleRate = _idleRates[reportId] ?? _idleRates[0] ?? 0;
          log?.info('GET_IDLE: reportId=$reportId, rate=$idleRate');
          // Write completes IN transfer, .little
          ep0.write(Uint8List(1)..[0] = idleRate);
        }(),
        (.setIdle, .out) => () {
          final reportId = wValue.byte0;
          final duration = wValue.byte1;

          // Store idle rate per report ID
          // reportId=0 means "all reports"
          if (reportId == 0) {
            _idleRates[0] = duration;
          } else {
            _idleRates[reportId] = duration;
          }
          log?.info(
            'SET_IDLE: reportId=$reportId, duration=$duration (${duration * 4}ms)',
          );
          onSetIdle(reportId, duration);
          // ACK the OUT transfer after processing
          ep0.halt();
        }(),
        (.getProtocol, .in_) => () {
          if (wLength != 1 || wValue != 0) {
            log?.error('GET_PROTOCOL: Invalid parameters');
            return ep0.halt();
          }
          log?.info('GET_PROTOCOL: returning ${_currentProtocol.name}');
          // Write completes IN transfer, .little
          ep0.write(Uint8List(1)..[0] = _currentProtocol.value);
        }(),
        (.setProtocol, .out) => () {
          _currentProtocol = HIDProtocol.fromByte(wValue.byte0);
          log?.info('SET_PROTOCOL: set to ${_currentProtocol.name}');
          onSetProtocol(_currentProtocol);
          // ACK the OUT transfer after processing
          ep0.halt();
        }(),
        _ => log?.warn(
          'Invalid HID class request: bRequest=${bRequest.toHex()}',
        ),
      },
      .reserved || .vendor || .standard => super.onSetup(
        bmRequestType,
        bRequest,
        wValue,
        wIndex,
        wLength,
      ),
    };
  }

  /// Streams reports from the interrupt OUT endpoint.
  Stream<Uint8List> streamReports() {
    assert(
      _interruptOut != null,
      'Device has no output endpoint. Ensure config.hasOutputEndpoint '
      'is true and device is enabled.',
    );
    return _interruptOut!.stream();
  }

  // Override hooks for subclasses

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
  void onSetReport(HIDReportType type, int reportId, Uint8List data) {}

  /// Called when the host changes the idle rate via SET_IDLE.
  void onSetIdle(int reportId, int duration) {}

  /// Called when the host changes the protocol via SET_PROTOCOL.
  void onSetProtocol(HIDProtocol protocol) {}
}

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '/usb_gadget.dart';

/// Enhanced HIDFunctionFs with simplified endpoint configuration.
class HIDFunctionFs extends FunctionFs with USBGadgetLogger {
  HIDFunctionFs({
    required super.name,
    required this.subclass,
    required this.protocol,
    required this.config,
    this.reportDescriptor,
    int hidVersion = 0x0111,
    int countryCode = 0x00,
    int physicalDescriptorLength = 0,
    super.speeds,
    super.strings,
    super.flags,
  }) {
    super.descriptors.addAll([
      interface = USBInterfaceDescriptor(
        interfaceNumber: .interface0,
        numEndpoints: .new(config.numEndpoints),
        interfaceClass: .hid,
        interfaceSubClass: subclass.value,
        interfaceProtocol: protocol.value,
      ),
      hidDescriptor = USBHIDDescriptor(
        hidVersion: hidVersion,
        countryCode: countryCode,
        physicalDescriptorLength: physicalDescriptorLength,
        reportLength: reportDescriptor?.length ?? 0,
      ),
      ...config.descriptors,
    ]);
  }

  /// Endpoint configuration (input-only, bidirectional, output-only).
  final HIDEndpointConfig config;

  /// Interface descriptor for this HID function.
  late final USBInterfaceDescriptor interface;

  /// HID class descriptor describing the HID interface version,
  /// country code, and report descriptor length.
  late final USBHIDDescriptor hidDescriptor;

  /// HID report descriptor defining the format of reports sent to/from
  /// the host.
  final Uint8List? reportDescriptor;

  /// HID device subclass (boot device or none).
  final HIDSubclass subclass;

  /// HID protocol (keyboard, mouse, or none).
  HIDProtocol protocol;

  /// Idle rates per report ID (in 4ms units).
  /// Key: Report ID (0 = all reports)
  /// Value: Idle rate (0 = infinite, only report on change)
  final Map<int, int> _idleRates = {};

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
              return ep0.write(hidDescriptor.toBytes());
            case .report:
              if (reportDescriptor == null) {
                log?.warn('No report descriptor available');
                return ep0.halt();
              }
              log?.debug(
                'Providing HID report descriptor (${reportDescriptor!.length} bytes)',
              );
              return ep0.write(reportDescriptor!.sublist(0, wLength));
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
            log?.error('GET_REPORT: No data available');
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
          return ep0.write(Uint8List(1)..[0] = protocol.value);

        case (.setProtocol, .out):
          onSetProtocol(.fromByte(wValue.byte(0)));
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
  /// The returned data is written directly to EP0 truncated to [wLength]
  /// bytes. The Report ID byte is NOT prepended automatically — include it
  /// in the returned data if your report descriptor uses multiple report IDs.
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
    this.protocol = protocol;
  }

  @override
  @mustCallSuper
  Future<void> release() async {
    _idleRates.clear();
    _interruptIn?.release();
    _interruptIn = null;
    _interruptOut?.release();
    _interruptOut = null;
    await super.release();
  }
}

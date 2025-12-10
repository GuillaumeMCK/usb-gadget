/// FunctionFs event definitions and handling.
///
/// Events are delivered on the ep0 file descriptor after the descriptors
/// have been written. These events signal state changes in the USB function.
library;

import 'dart:typed_data';

import '/src/core/utils.dart';
import '/usb_gadget.dart';

/// Event type constants.
enum FunctionFsEventType {
  /// Function has been bound to a UDC.
  bind,

  /// Function has been unbound from the UDC.
  unbind,

  /// Function has been enabled (host configured it).
  enable,

  /// Function has been disabled.
  disable,

  /// Setup packet received.
  setup,

  /// USB suspend signaled.
  suspend,

  /// USB resume signaled.
  resume;

  /// The numeric value of this event type.
  const FunctionFsEventType();

  /// Creates an event type from its numeric value.
  ///
  /// Returns null if the value doesn't match any known event type.
  static FunctionFsEventType? fromValue(int value) {
    try {
      return FunctionFsEventType.values.firstWhere((e) => e.index == value);
    } catch (_) {
      return null;
    }
  }
}

/// Base class for FunctionFs events.
sealed class FunctionFsEvent {
  /// The type of this event.
  FunctionFsEventType get type;

  /// Parses a single FunctionFs event from raw bytes.
  ///
  /// The event structure is 12 bytes:
  /// - 8 bytes for the setup packet (union, only used for setup events)
  /// - 1 byte for event type
  /// - 3 bytes padding
  ///
  /// Returns null if the event type is invalid or unknown.
  static FunctionFsEvent? fromBytes(List<int> data) {
    if (data.length < 12) {
      throw ArgumentError('Event data must be at least 12 bytes');
    }

    final eventType = FunctionFsEventType.fromValue(data[8]);
    if (eventType == null) {
      return null;
    }

    return switch (eventType) {
      FunctionFsEventType.bind => const BindEvent(),
      FunctionFsEventType.unbind => const UnbindEvent(),
      FunctionFsEventType.enable => const EnableEvent(),
      FunctionFsEventType.disable => const DisableEvent(),
      FunctionFsEventType.setup => SetupEvent._fromBytes(data),
      FunctionFsEventType.suspend => const SuspendEvent(),
      FunctionFsEventType.resume => const ResumeEvent(),
    };
  }

  static const size = 12;

  /// Parses multiple events from a buffer.
  ///
  /// FunctionFs can queue up to 4 events (48 bytes).
  /// Invalid or unknown events are skipped.
  static List<FunctionFsEvent> fromBytesMultiple(List<int> data) {
    final events = <FunctionFsEvent>[];

    for (var offset = 0; offset + size <= data.length; offset += size) {
      final event = fromBytes(data.sublist(offset, offset + size));
      if (event != null) {
        events.add(event);
      }
    }

    return events;
  }
}

/// Function has been bound to a UDC.
class BindEvent implements FunctionFsEvent {
  /// Creates a bind event.
  const BindEvent();

  @override
  final FunctionFsEventType type = .bind;

  @override
  String toString() => 'BindEvent()';
}

/// Function has been unbound from the UDC.
class UnbindEvent implements FunctionFsEvent {
  /// Creates an unbind event.
  const UnbindEvent();

  @override
  final FunctionFsEventType type = .unbind;

  @override
  String toString() => 'UnbindEvent()';
}

/// Function has been enabled.
class EnableEvent implements FunctionFsEvent {
  /// Creates an enable event.
  const EnableEvent();

  @override
  final FunctionFsEventType type = .enable;

  @override
  String toString() => 'EnableEvent()';
}

/// Function has been disabled.
class DisableEvent implements FunctionFsEvent {
  /// Creates a disable event.
  const DisableEvent();

  @override
  final FunctionFsEventType type = .disable;

  @override
  String toString() => 'DisableEvent()';
}

/// Setup packet received.
///
/// Contains the 8-byte USB SETUP packet data that describes a control request
/// from the host. Use the convenience getters to access parsed values.
///
/// Example:
/// ```dart
/// void handleSetup(SetupEvent event) {
///   if (event.requestType == USBRequestType.vendor) {
///     // Handle vendor-specific request
///     print('Vendor request: ${event.bRequest}');
///   }
/// }
/// ```
class SetupEvent implements FunctionFsEvent {
  /// Creates a setup event.
  const SetupEvent({
    required this.bRequestType,
    required this.bRequest,
    required this.wValue,
    required this.wIndex,
    required this.wLength,
  });

  /// Internal constructor for parsing from bytes.
  factory SetupEvent._fromBytes(List<int> data) {
    final buffer = ByteData.sublistView(Uint8List.fromList(data));
    return SetupEvent(
      bRequestType: buffer.getUint8(0),
      bRequest: buffer.getUint8(1),
      wValue: buffer.getUint16(2, Endian.little),
      wIndex: buffer.getUint16(4, Endian.little),
      wLength: buffer.getUint16(6, Endian.little),
    );
  }

  @override
  final FunctionFsEventType type = .setup;

  /// Request type and direction.
  final int bRequestType;

  /// Specific request.
  final int bRequest;

  /// Request-specific parameter.
  final int wValue;

  /// Request-specific parameter.
  final int wIndex;

  /// Number of bytes to transfer.
  final int wLength;

  /// Gets the request type (standard, class, vendor).
  USBRequestType get requestType => .fromByte(bRequestType);

  /// Gets the recipient (device, interface, endpoint, other).
  USBRecipient get recipient => .fromByte(bRequestType);

  /// Gets the direction (IN or OUT).
  USBDirection get direction => .fromByte(bRequestType);

  /// Checks if this is a standard USB request.
  bool get isStandardRequest => requestType == .standard;

  /// Checks if this is a class-specific request.
  bool get isClassRequest => requestType == .class_;

  /// Checks if this is a vendor-specific request.
  bool get isVendorRequest => requestType == .vendor;

  /// Gets the standard request type if this is a standard request.
  ///
  /// Returns null if this is not a standard request.
  USBRequest? get standardRequest =>
      isStandardRequest ? .fromValue(bRequest) : null;

  @override
  String toString() =>
      'SetupEvent(type: ${bRequestType.toHex()}, '
      'request: ${bRequest.toHex()}, '
      'value: ${wValue.toHex()}, '
      'index: ${wIndex.toHex()}, '
      'length: $wLength)';
}

/// USB suspend signaled.
class SuspendEvent implements FunctionFsEvent {
  /// Creates a suspend event.
  const SuspendEvent();

  @override
  final FunctionFsEventType type = .suspend;

  @override
  String toString() => 'SuspendEvent()';
}

/// USB resume signaled.
class ResumeEvent implements FunctionFsEvent {
  /// Creates a resume event.
  const ResumeEvent();

  @override
  final FunctionFsEventType type = .resume;

  @override
  String toString() => 'ResumeEvent()';
}

/// USB request types (bits 5-6 of bmRequestType).
enum USBRequestType {
  /// Standard request (0x00).
  standard(0x00),

  /// Class-specific request (0x20).
  class_(0x20),

  /// Vendor-specific request (0x40).
  vendor(0x40),

  /// Reserved (0x60).
  reserved(0x60);

  const USBRequestType(this.value);

  /// Raw value for bits 5-6 of bmRequestType.
  final int value;

  /// Request type mask (bits 5-6).
  static const int mask = 0x60;

  /// Extracts request type from bmRequestType byte.
  static USBRequestType fromByte(int byte) {
    final masked = byte & mask;
    return USBRequestType.values.firstWhere(
      (t) => t.value == masked,
      orElse: () => reserved,
    );
  }
}

/// USB recipients (bits 0-4 of bmRequestType).
enum USBRecipient {
  /// Device recipient (0x00).
  device(0x00),

  /// Interface recipient (0x01).
  interface(0x01),

  /// Endpoint recipient (0x02).
  endpoint(0x02),

  /// Other recipient (0x03).
  other(0x03);

  const USBRecipient(this.value);

  /// Raw value for bits 0-4 of bmRequestType.
  final int value;

  /// Recipient mask (bits 0-4).
  static const int mask = 0x1F;

  /// Extracts recipient from bmRequestType byte.
  static USBRecipient fromByte(int byte) {
    final masked = byte & mask;
    return USBRecipient.values.firstWhere(
      (r) => r.value == masked,
      orElse: () => other,
    );
  }
}

/// Standard USB requests.
enum USBRequest {
  /// GET_STATUS (0x00).
  getStatus(0x00),

  /// CLEAR_FEATURE (0x01).
  clearFeature(0x01),

  /// SET_FEATURE (0x03).
  setFeature(0x03),

  /// SET_ADDRESS (0x05).
  setAddress(0x05),

  /// GET_DESCRIPTOR (0x06).
  getDescriptor(0x06),

  /// SET_DESCRIPTOR (0x07).
  setDescriptor(0x07),

  /// GET_CONFIGURATION (0x08).
  getConfiguration(0x08),

  /// SET_CONFIGURATION (0x09).
  setConfiguration(0x09),

  /// GET_INTERFACE (0x0A).
  getInterface(0x0A),

  /// SET_INTERFACE (0x0B).
  setInterface(0x0B),

  /// SYNCH_FRAME (0x0C).
  synchFrame(0x0C);

  const USBRequest(this.value);

  /// Raw request value.
  final int value;

  /// Creates a request from its raw value.
  static USBRequest? fromValue(int value) {
    try {
      return USBRequest.values.firstWhere((r) => r.value == value);
    } catch (_) {
      return null;
    }
  }
}

/// Standard USB feature selectors.
enum USBFeature {
  /// Endpoint halt feature (0x00).
  endpointHalt(0x00),

  /// Device remote wakeup feature (0x01).
  deviceRemoteWakeup(0x01),

  /// Test mode feature (0x02).
  testMode(0x02),

  /// Interface function suspend feature (0x00).
  intfFuncSuspend(0x00);

  const USBFeature(this.value);

  /// Raw feature value.
  final int value;
}

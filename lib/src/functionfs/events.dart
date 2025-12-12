import 'dart:typed_data';
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
  final FunctionFsEventType type = FunctionFsEventType.bind;

  @override
  String toString() => 'BindEvent()';
}

/// Function has been unbound from the UDC.
class UnbindEvent implements FunctionFsEvent {
  /// Creates an unbind event.
  const UnbindEvent();

  @override
  final FunctionFsEventType type = FunctionFsEventType.unbind;

  @override
  String toString() => 'UnbindEvent()';
}

/// Function has been enabled.
class EnableEvent implements FunctionFsEvent {
  /// Creates an enable event.
  const EnableEvent();

  @override
  final FunctionFsEventType type = FunctionFsEventType.enable;

  @override
  String toString() => 'EnableEvent()';
}

/// Function has been disabled.
class DisableEvent implements FunctionFsEvent {
  /// Creates a disable event.
  const DisableEvent();

  @override
  final FunctionFsEventType type = FunctionFsEventType.disable;

  @override
  String toString() => 'DisableEvent()';
}

/// Setup packet received.
///
/// Contains the 8-byte USB SETUP packet data that describes a control request
/// from the host. Use the convenience getters to access parsed values.
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
  final FunctionFsEventType type = FunctionFsEventType.setup;

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
  USBRequestType get requestType => USBRequestType.fromByte(bRequestType);

  /// Gets the recipient (device, interface, endpoint, other).
  USBRecipient get recipient => USBRecipient.fromByte(bRequestType);

  /// Gets the direction (IN or OUT).
  USBDirection get direction => USBDirection.fromByte(bRequestType);

  /// Checks if this is a standard USB request.
  bool get isStandardRequest => requestType == USBRequestType.standard;

  /// Checks if this is a class-specific request.
  bool get isClassRequest => requestType == USBRequestType.class_;

  /// Checks if this is a vendor-specific request.
  bool get isVendorRequest => requestType == USBRequestType.vendor;

  /// Gets the standard request type if this is a standard request.
  ///
  /// Returns null if this is not a standard request.
  USBRequest? get standardRequest =>
      isStandardRequest ? USBRequest.fromValue(bRequest) : null;

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
  final FunctionFsEventType type = FunctionFsEventType.suspend;

  @override
  String toString() => 'SuspendEvent()';
}

/// USB resume signaled.
class ResumeEvent implements FunctionFsEvent {
  /// Creates a resume event.
  const ResumeEvent();

  @override
  final FunctionFsEventType type = FunctionFsEventType.resume;

  @override
  String toString() => 'ResumeEvent()';
}

import '/usb_gadget.dart';

/// Endpoint number (0-15).
///
/// USB devices can have up to 16 endpoint numbers (0-15). Each endpoint
/// number can have both an IN and OUT endpoint, making up to 32 total
/// endpoints per device (though endpoint 0 is bidirectional control only).
class EndpointNumber {
  const EndpointNumber(this.value)
    : assert(value >= 0 && value <= 15, 'Endpoint number must be 0-15');

  /// Extracts endpoint number from a bEndpointAddress byte.
  ///
  /// Uses mask 0x0F to extract bits 0-3.
  factory EndpointNumber.fromByte(int byte) => EndpointNumber(byte & 0x0F);

  /// The raw endpoint number value (0-15).
  final int value;

  /// Common endpoint numbers.
  static const EndpointNumber ep0 = .new(0);
  static const EndpointNumber ep1 = .new(1);
  static const EndpointNumber ep2 = .new(2);
  static const EndpointNumber ep3 = .new(3);
  static const EndpointNumber ep4 = .new(4);
  static const EndpointNumber ep5 = .new(5);
  static const EndpointNumber ep6 = .new(6);
  static const EndpointNumber ep7 = .new(7);
  static const EndpointNumber ep8 = .new(8);
  static const EndpointNumber ep9 = .new(9);
  static const EndpointNumber ep10 = .new(10);
  static const EndpointNumber ep11 = .new(11);
  static const EndpointNumber ep12 = .new(12);
  static const EndpointNumber ep13 = .new(13);
  static const EndpointNumber ep14 = .new(14);
  static const EndpointNumber ep15 = .new(15);

  @override
  bool operator ==(Object other) =>
      other is EndpointNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EP$value';
}

/// Endpoint address combining number and direction.
///
/// USB endpoint addresses encode both the endpoint number (0-15) and the
/// transfer direction (IN or OUT) in a single byte:
/// - Bits 0-3: Endpoint number
/// - Bit 7: Direction (0 = OUT, 1 = IN)
/// - Bits 4-6: Reserved, must be 0
class EndpointAddress {
  const EndpointAddress(this.number, this.direction);

  /// Creates an IN (device-to-host) endpoint address.
  ///
  /// IN endpoints send data from the device to the host.
  const EndpointAddress.in_(this.number) : direction = USBDirection.in_;

  /// Creates an OUT (host-to-device) endpoint address.
  ///
  /// OUT endpoints receive data from the host to the device.
  const EndpointAddress.out(this.number) : direction = USBDirection.out;

  /// Parses an endpoint address from a bEndpointAddress byte.
  ///
  /// Extracts the endpoint number (bits 0-3) and direction (bit 7).
  factory EndpointAddress.fromByte(int byte) => EndpointAddress(
    EndpointNumber.fromByte(byte),
    USBDirection.fromByte(byte),
  );

  /// The endpoint number (0-15).
  final EndpointNumber number;

  /// The transfer direction (IN or OUT).
  final USBDirection direction;

  /// Converts to a bEndpointAddress byte value.
  ///
  /// Returns a byte with direction in bit 7 and endpoint number in bits 0-3.
  int get value => direction.value | number.value;

  /// True if this is an IN (device-to-host) endpoint.
  bool get isIn => direction.isIn;

  /// True if this is an OUT (host-to-device) endpoint.
  bool get isOut => direction.isOut;

  @override
  bool operator ==(Object other) =>
      other is EndpointAddress &&
      other.number == number &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(number, direction);

  @override
  String toString() => 'EP${number.value} ${direction.isIn ? 'IN' : 'OUT'}';
}

/// Type-safe interface number (0-255).
///
/// USB configurations can have multiple interfaces, each identified by
/// a unique number. Interface numbers are assigned sequentially starting
/// from 0 within each configuration.
class InterfaceNumber {
  const InterfaceNumber(this.value)
    : assert(value >= 0 && value <= 255, 'Interface number must be 0-255');

  /// The interface number (0-255).
  final int value;

  static const InterfaceNumber interface0 = .new(0);
  static const InterfaceNumber interface1 = .new(1);
  static const InterfaceNumber interface2 = .new(2);
  static const InterfaceNumber interface3 = .new(3);

  @override
  bool operator ==(Object other) =>
      other is InterfaceNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Interface $value';
}

/// Type-safe alternate setting number (0-255).
///
/// Interfaces can have multiple alternate settings that provide different
/// configurations of endpoints or bandwidth allocations. Alternate setting
/// 0 is the default and must always be supported.
///
/// Alternate settings allow dynamic reconfiguration without changing the
/// entire device configuration. For example, a webcam might have:
/// - Alt 0: No streaming (no endpoints)
/// - Alt 1: Low resolution streaming (smaller bandwidth)
/// - Alt 2: High resolution streaming (larger bandwidth)
class AlternateSetting {
  const AlternateSetting(this.value)
    : assert(value >= 0 && value <= 255, 'Alternate setting must be 0-255');

  /// The alternate setting number (0-255).
  final int value;

  /// Default alternate setting (always 0).
  static const AlternateSetting default_ = .new(0);
  static const AlternateSetting alt1 = .new(1);
  static const AlternateSetting alt2 = .new(2);

  @override
  bool operator ==(Object other) =>
      other is AlternateSetting && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Alt $value';
}

/// Type-safe endpoint count (0-30).
///
/// Specifies the number of endpoints used by an interface, excluding
/// the default control endpoint (endpoint 0). An interface can declare
/// up to 30 additional endpoints (15 IN + 15 OUT).
class EndpointCount {
  const EndpointCount(this.value)
    : assert(
        value >= 0 && value <= 30,
        'Endpoint count must be 0-30 (excluding EP0)',
      );

  /// Number of endpoints (0-30, excluding endpoint 0).
  final int value;

  static const EndpointCount none = .new(0);
  static const EndpointCount one = .new(1);
  static const EndpointCount two = .new(2);

  @override
  bool operator ==(Object other) =>
      other is EndpointCount && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value endpoint${value == 1 ? '' : 's'}';
}

/// Type-safe string descriptor index (0-255).
///
/// References a string descriptor containing human-readable text.
/// Index 0 means no string descriptor is provided. Common uses:
/// - Index 1: Manufacturer string
/// - Index 2: Product string
/// - Index 3: Serial number string
///
/// String descriptors can be localized to different languages using
/// the language ID in GET_DESCRIPTOR requests.
class StringIndex {
  const StringIndex(this.value)
    : assert(value >= 0 && value <= 255, 'String index must be 0-255');

  /// The string descriptor index (0-255).
  final int value;

  /// No string descriptor (index 0).
  static const StringIndex none = .new(0);

  /// Common string descriptor indices.
  static const StringIndex manufacturer = .new(1);
  static const StringIndex product = .new(2);
  static const StringIndex serialNumber = .new(3);

  /// True if this index references a string descriptor.
  bool get hasString => value != 0;

  @override
  bool operator ==(Object other) =>
      other is StringIndex && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => hasString ? 'String $value' : 'No string';
}

/// Endpoint attributes (bmAttributes field).
///
/// The bmAttributes field describes the endpoint's transfer type and
/// additional characteristics:
/// - Bits 0-1: Transfer type (control/isochronous/bulk/interrupt)
/// - Bits 2-7: Additional attributes depending on transfer type
///
/// For isochronous endpoints:
/// - Bits 2-3: Synchronization type
/// - Bits 4-5: Usage type
class EndpointAttributes {
  /// Control transfer endpoint.
  ///
  /// Structured transfers for device configuration. All devices have a
  /// control endpoint at address 0. Provides reliable delivery with
  /// error checking and retry.
  const EndpointAttributes.control() : transferType = .control, _extraBits = 0;

  /// Isochronous transfer endpoint.
  ///
  /// Time-critical transfers with guaranteed bandwidth but no error correction.
  /// Used for audio/video streaming. Requires synchronization and usage type.
  EndpointAttributes.isochronous({
    required IsoSyncType syncType,
    required IsoUsageType usageType,
  }) : transferType = .isochronous,
       _extraBits = syncType.value | usageType.value;

  /// Bulk transfer endpoint.
  ///
  /// Large, reliable transfers with error correction but no guaranteed timing.
  /// Used for mass storage, file transfers, printers.
  const EndpointAttributes.bulk() : transferType = .bulk, _extraBits = 0;

  /// Interrupt transfer endpoint.
  ///
  /// Small, periodic transfers with bounded latency. Used for keyboards,
  /// mice, HID devices. Guaranteed maximum latency but limited data rate.
  const EndpointAttributes.interrupt()
    : transferType = .interrupt,
      _extraBits = 0;

  /// Parses attributes from a bmAttributes byte.
  factory EndpointAttributes.fromByte(int byte) =>
      switch (TransferType.fromAttributes(byte)) {
        .control => const .control(),
        .isochronous => .isochronous(
          syncType: .fromByte(byte),
          usageType: .fromByte(byte),
        ),
        .bulk => const .bulk(),
        .interrupt => const .interrupt(),
      };

  /// The transfer type of this endpoint.
  final TransferType transferType;
  final int _extraBits;

  /// Final bmAttributes byte value.
  int get value => transferType.value | _extraBits;

  /// Synchronization type for isochronous endpoints.
  ///
  /// Returns null for non-isochronous endpoints.
  IsoSyncType? get syncType =>
      transferType == .isochronous ? IsoSyncType.fromByte(value) : null;

  /// Usage type for isochronous endpoints.
  ///
  /// Returns null for non-isochronous endpoints.
  IsoUsageType? get usageType =>
      transferType == .isochronous ? IsoUsageType.fromByte(value) : null;

  @override
  bool operator ==(Object other) =>
      other is EndpointAttributes && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EndpointAttributes(${transferType.name})';
}

/// Isochronous synchronization type (bits 2-3 of bmAttributes).
///
/// Describes how isochronous data is synchronized:
/// - No synchronization: Asynchronous
/// - Asynchronous: Source has no locked timing
/// - Adaptive: Sink can adjust timing
/// - Synchronous: Source/sink have locked timing
enum IsoSyncType {
  /// No synchronization (asynchronous).
  noSync(0x00),

  /// Asynchronous synchronization.
  ///
  /// The endpoint has no inherent timing requirements.
  async(0x04),

  /// Adaptive synchronization.
  ///
  /// The endpoint can adapt to rate feedback.
  adaptive(0x08),

  /// Synchronous synchronization.
  ///
  /// The endpoint has fixed timing requirements.
  sync(0x0C);

  const IsoSyncType(this.value);

  /// Raw value for bits 2-3 of bmAttributes.
  final int value;

  /// Extracts synchronization type from bmAttributes byte.
  static IsoSyncType fromByte(int byte) {
    final masked = byte & 0x0C;
    return IsoSyncType.values.firstWhere(
      (t) => t.value == masked,
      orElse: () => noSync,
    );
  }
}

/// Isochronous usage type (bits 4-5 of bmAttributes).
///
/// Describes how isochronous endpoint data is used:
/// - Data endpoint: Normal data transfer
/// - Feedback endpoint: Provides rate feedback
/// - Implicit feedback: Data endpoint with implicit feedback
enum IsoUsageType {
  /// Data endpoint.
  ///
  /// Standard isochronous data transfer.
  data(0x00),

  /// Feedback endpoint.
  ///
  /// Provides rate feedback for adaptive synchronization.
  feedback(0x10),

  /// Implicit feedback data endpoint.
  ///
  /// Data endpoint that also provides implicit rate feedback.
  implicit(0x20);

  const IsoUsageType(this.value);

  /// Raw value for bits 4-5 of bmAttributes.
  final int value;

  /// Extracts usage type from bmAttributes byte.
  static IsoUsageType fromByte(int byte) {
    final masked = byte & 0x30;
    return IsoUsageType.values.firstWhere(
      (t) => t.value == masked,
      orElse: () => data,
    );
  }
}

/// Type-safe maximum packet size with speed-specific validation.
///
/// USB endpoints have maximum packet size limits that vary by:
/// - USB speed (Full-Speed, High-Speed, SuperSpeed)
/// - Transfer type (Control, Bulk, Interrupt, Isochronous)
///
/// These constructors enforce USB specification limits at construction time.
///
/// Full-Speed limits (USB 1.1, 12 Mbps):
/// - Control: 8, 16, 32, or 64 bytes
/// - Bulk: 8, 16, 32, or 64 bytes
/// - Interrupt: 0-64 bytes
/// - Isochronous: 0-1023 bytes
///
/// High-Speed limits (USB 2.0, 480 Mbps):
/// - Control: 64 bytes
/// - Bulk: 512 bytes
/// - Interrupt: 0-1024 bytes
/// - Isochronous: 0-1024 bytes (with transactions per microframe)
///
/// SuperSpeed limits (USB 3.0+, 5+ Gbps):
/// - All: 512 or 1024 bytes
class MaxPacketSize {
  /// Full-speed control endpoint (8, 16, 32, or 64 bytes).
  const MaxPacketSize.fullSpeedControl(this.size)
    : assert(
        size == 8 || size == 16 || size == 32 || size == 64,
        'Full-speed control must be 8, 16, 32, or 64 bytes',
      ),
      _extraBits = 0;

  /// Full-speed bulk endpoint (8, 16, 32, or 64 bytes).
  const MaxPacketSize.fullSpeedBulk(this.size)
    : assert(
        size == 8 || size == 16 || size == 32 || size == 64,
        'Full-speed bulk must be 8, 16, 32, or 64 bytes',
      ),
      _extraBits = 0;

  /// Full-speed interrupt endpoint (0-64 bytes).
  const MaxPacketSize.fullSpeedInterrupt(this.size)
    : assert(
        size >= 0 && size <= 64,
        'Full-speed interrupt must be 0-64 bytes',
      ),
      _extraBits = 0;

  /// Full-speed isochronous endpoint (0-1023 bytes).
  const MaxPacketSize.fullSpeedIsochronous(this.size)
    : assert(
        size >= 0 && size <= 1023,
        'Full-speed isochronous must be 0-1023 bytes',
      ),
      _extraBits = 0;

  /// High-speed control endpoint (always 64 bytes).
  const MaxPacketSize.highSpeedControl() : size = 64, _extraBits = 0;

  /// High-speed bulk endpoint (always 512 bytes).
  const MaxPacketSize.highSpeedBulk() : size = 512, _extraBits = 0;

  /// High-speed interrupt endpoint (0-1024 bytes).
  const MaxPacketSize.highSpeedInterrupt(this.size)
    : assert(
        size >= 0 && size <= 1024,
        'High-speed interrupt must be 0-1024 bytes',
      ),
      _extraBits = 0;

  /// High-speed isochronous endpoint (0-1024 bytes).
  ///
  /// [transactionsPerMicroframe] specifies additional transactions per
  /// microframe (1-3). The actual value is encoded as (value - 1) in bits 11-12.
  /// This allows high-bandwidth isochronous endpoints to transfer multiple
  /// packets per 125μs microframe.
  const MaxPacketSize.highSpeedIsochronous({
    required this.size,
    required int transactionsPerMicroframe,
  }) : assert(
         size >= 0 && size <= 1024,
         'High-speed isochronous must be 0-1024 bytes',
       ),
       assert(
         transactionsPerMicroframe >= 1 && transactionsPerMicroframe <= 3,
         'Transactions per microframe must be 1-3',
       ),
       _extraBits = (transactionsPerMicroframe - 1) << 11;

  /// SuperSpeed endpoint (512 or 1024 bytes).
  const MaxPacketSize.superSpeed(this.size)
    : assert(
        size == 512 || size == 1024,
        'SuperSpeed must be 512 or 1024 bytes',
      ),
      _extraBits = 0;

  /// Raw packet size without validation.
  ///
  /// Use this for custom or non-standard packet sizes.
  const MaxPacketSize.raw(this.size)
    : assert(size >= 0 && size <= 0xFFFF, 'Size must fit in 16 bits'),
      _extraBits = 0;

  /// The packet size in bytes.
  final int size;
  final int _extraBits;

  /// Final wMaxPacketSize field value.
  int get value => size | _extraBits;

  /// Number of additional transactions per microframe for high-speed isochronous.
  ///
  /// Returns null for non-high-speed-isochronous endpoints.
  /// Value is decoded from bits 11-12: actual = (bits + 1).
  int? get transactionsPerMicroframe =>
      _extraBits != 0 ? ((_extraBits >> 11) & 0x03) + 1 : null;

  @override
  bool operator ==(Object other) =>
      other is MaxPacketSize && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MaxPacketSize($size bytes)';
}

/// Type-safe polling interval (bInterval field).
///
/// The bInterval field specifies how often an endpoint is polled for data.
/// Interpretation varies by transfer type and USB speed:
///
/// Full-Speed:
/// - Control/Bulk: Ignored (set to 0)
/// - Interrupt/Isochronous: 1-255 frames (1 frame = 1 ms)
///
/// High-Speed:
/// - Control/Bulk: Ignored (set to 0)
/// - Interrupt: 1-16 (actual interval = 2^(value-1) microframes)
/// - Isochronous: Always 1
///
/// SuperSpeed:
/// - Bulk/Control: Ignored (set to 0)
/// - Interrupt/Isochronous: 1-16 (actual interval = 2^(value-1) × 125μs)
class PollingInterval {
  /// No polling (for control/bulk endpoints).
  const PollingInterval.none() : value = 0;

  /// Full-speed interrupt/isochronous interval (1-255 frames).
  ///
  /// Each frame is 1 millisecond, so valid intervals are 1-255 ms.
  const PollingInterval.fullSpeed(int frames)
    : assert(
        frames >= 1 && frames <= 255,
        'Full-speed interval must be 1-255 frames',
      ),
      value = frames;

  /// High-speed interrupt interval (1-16).
  ///
  /// The actual interval is 2^(exponent-1) microframes (125μs units).
  /// For example, exponent=4 gives 2^3 = 8 microframes = 1 ms.
  const PollingInterval.highSpeedInterrupt(int exponent)
    : assert(
        exponent >= 1 && exponent <= 16,
        'High-speed interrupt interval must be 1-16',
      ),
      value = exponent;

  /// High-speed isochronous interval (always 1).
  ///
  /// High-speed isochronous endpoints are always polled every microframe (125μs).
  const PollingInterval.highSpeedIsochronous() : value = 1;

  /// SuperSpeed interval (1-16).
  ///
  /// The actual interval is 2^(exponent-1) × 125μs.
  const PollingInterval.superSpeed(int exponent)
    : assert(
        exponent >= 1 && exponent <= 16,
        'SuperSpeed interval must be 1-16',
      ),
      value = exponent;

  /// Raw interval value without validation.
  const PollingInterval.raw(this.value)
    : assert(value >= 0 && value <= 255, 'Interval must be 0-255');

  /// Final bInterval field value.
  final int value;

  /// Actual interval in microframes for high-speed/SuperSpeed.
  ///
  /// Returns null if this is not a high-speed/SuperSpeed interval.
  /// Calculated as 2^(value-1) for values 1-16.
  int? get microframes => value > 0 && value <= 16 ? 1 << (value - 1) : null;

  @override
  bool operator ==(Object other) =>
      other is PollingInterval && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PollingInterval($value)';
}

/// Endpoint configuration consolidating transfer type, packet size, and
/// polling interval.
///
/// This class simplifies endpoint configuration by automatically
/// determining correct packet sizes and polling intervals based on the
/// transfer type and USB speed, reducing boilerplate and preventing
/// USB specification violations.
class EndpointConfig {
  const EndpointConfig({
    required this.transferType,
    this.pollingMs,
    this.maxPacketSize,
    this.syncType,
    this.usageType,
  });

  /// Bulk transfer endpoint configuration.
  ///
  /// Automatically configures:
  /// - Full-Speed: 64-byte packets
  /// - High-Speed: 512-byte packets
  /// - SuperSpeed: 1024-byte packets (uses default from spec)
  /// - No polling interval (0)
  const EndpointConfig.bulk()
    : transferType = .bulk,
      pollingMs = null,
      maxPacketSize = null,
      syncType = null,
      usageType = null;

  /// Control transfer endpoint configuration.
  ///
  /// Automatically configures:
  /// - Full-Speed: 64-byte packets
  /// - High-Speed: 64-byte packets
  /// - SuperSpeed: 512-byte packets
  /// - No polling interval (0)
  const EndpointConfig.control()
    : transferType = .control,
      pollingMs = null,
      maxPacketSize = null,
      syncType = null,
      usageType = null;

  /// Interrupt transfer endpoint configuration.
  ///
  /// Requires [pollingMs] - polling interval in milliseconds for Full-Speed.
  /// High-Speed and SuperSpeed intervals are calculated automatically.
  ///
  /// [maxPacketSize] can optionally override the default packet size.
  const EndpointConfig.interrupt({required this.pollingMs, this.maxPacketSize})
    : transferType = .interrupt,
      syncType = null,
      usageType = null;

  /// Isochronous transfer endpoint configuration.
  ///
  /// Requires configuration for isochronous-specific parameters.
  /// Polling is fixed at 1ms for full-speed and high-speed.
  ///
  /// [syncType] and [usageType] define isochronous behavior.
  /// [maxPacketSize] can optionally override the default packet size.
  const EndpointConfig.isochronous({
    required this.syncType,
    required this.usageType,
    this.maxPacketSize,
  }) : transferType = .isochronous,
       pollingMs = 1;

  /// The transfer type.
  final TransferType transferType;

  /// Polling interval in milliseconds (for interrupt/isochronous).
  final int? pollingMs;

  /// Optional custom maximum packet size.
  final int? maxPacketSize;

  /// Synchronization type (for isochronous only).
  final IsoSyncType? syncType;

  /// Usage type (for isochronous only).
  final IsoUsageType? usageType;

  /// Gets the endpoint attributes for this configuration.
  EndpointAttributes getAttributes() => switch (transferType) {
    TransferType.control => const .control(),
    TransferType.bulk => const .bulk(),
    TransferType.interrupt => const .interrupt(),
    TransferType.isochronous => .isochronous(
      syncType: syncType ?? IsoSyncType.noSync,
      usageType: usageType ?? IsoUsageType.data,
    ),
  };

  /// Gets the maximum packet size for the specified USB speed.
  ///
  /// If [maxPacketSize] was provided, uses that value with appropriate
  /// validation. Otherwise uses default sizes for the transfer type and speed.
  MaxPacketSize getMaxPacketSize(USBSpeed speed) => switch (speed) {
    _ when maxPacketSize == null => transferType.getDefaultMaxPacketSize(speed),
    USBSpeed.fullSpeed => switch (transferType) {
      TransferType.control => .fullSpeedControl(maxPacketSize!),
      TransferType.bulk => .fullSpeedBulk(maxPacketSize!),
      TransferType.interrupt => .fullSpeedInterrupt(maxPacketSize!),
      TransferType.isochronous => .fullSpeedIsochronous(maxPacketSize!),
    },
    USBSpeed.highSpeed => switch (transferType) {
      TransferType.interrupt => .highSpeedInterrupt(maxPacketSize!),
      TransferType.isochronous => .highSpeedIsochronous(
        size: maxPacketSize!,
        transactionsPerMicroframe: 1,
      ),
      _ => .raw(maxPacketSize!),
    },
    _ => .superSpeed(maxPacketSize!),
  };

  /// Gets the polling interval for the specified USB speed.
  ///
  /// Control and bulk endpoints always return no polling (0).
  /// Other endpoints calculate intervals based on [pollingMs].
  PollingInterval getPollingInterval(USBSpeed speed) {
    if (transferType == .control || transferType == .bulk) {
      return const .none();
    }

    if (transferType == .isochronous) {
      return switch (speed) {
        USBSpeed.fullSpeed => const .fullSpeed(1),
        USBSpeed.highSpeed => const .highSpeedIsochronous(),
        _ => const .superSpeed(1),
      };
    }

    final ms = pollingMs ?? 10;
    return switch (speed) {
      USBSpeed.fullSpeed => .fullSpeed(ms),
      USBSpeed.highSpeed => .highSpeedInterrupt(_msToExponent(ms)),
      _ => .superSpeed(_msToExponent(ms)),
    };
  }

  /// Gets a suggested timeout in milliseconds for this endpoint.
  ///
  /// Returns null for control/bulk (which don't have guaranteed timing).
  /// For interrupt/isochronous, returns polling interval × 10.
  int? getTimeoutMs(USBSpeed speed) {
    if (transferType == .control || transferType == .bulk) {
      return null;
    }
    return (pollingMs ?? 1) * 10;
  }

  /// Converts milliseconds to exponent for high-speed/SuperSpeed intervals.
  ///
  /// Finds the closest exponent where 2^(exp-1) × 0.125ms ≈ ms.
  static int _msToExponent(int ms) {
    if (ms <= 0) return 1;
    final microframes = (ms / 0.125).round().clamp(1, 32768);
    var exp = 1;
    while ((1 << (exp - 1)) < microframes && exp < 16) {
      exp++;
    }
    return exp;
  }
}

/// Extension providing default packet sizes for each transfer type.
extension on TransferType {
  /// Returns the default maximum packet size for the given speed.
  MaxPacketSize getDefaultMaxPacketSize(USBSpeed speed) {
    return switch (speed) {
      USBSpeed.fullSpeed => defaultFullSpeedPacketSize,
      USBSpeed.highSpeed => defaultHighSpeedPacketSize,
      _ => defaultSuperSpeedPacketSize,
    };
  }

  /// Default full-speed packet size for this transfer type.
  MaxPacketSize get defaultFullSpeedPacketSize => switch (this) {
    TransferType.control => const .fullSpeedControl(64),
    TransferType.bulk => const .fullSpeedBulk(64),
    TransferType.interrupt => const .fullSpeedInterrupt(64),
    TransferType.isochronous => const .fullSpeedIsochronous(1023),
  };

  /// Default high-speed packet size for this transfer type.
  MaxPacketSize get defaultHighSpeedPacketSize => switch (this) {
    TransferType.control => const .highSpeedControl(),
    TransferType.bulk => const .highSpeedBulk(),
    TransferType.interrupt => const .highSpeedInterrupt(1024),
    TransferType.isochronous => const .highSpeedIsochronous(
      size: 1024,
      transactionsPerMicroframe: 1,
    ),
  };

  /// Default SuperSpeed packet size for this transfer type.
  MaxPacketSize get defaultSuperSpeedPacketSize => const .superSpeed(512);
}

/// Type-safe SuperSpeed burst size (0-15).
///
/// Specifies the maximum number of packets the endpoint can send or receive
/// as part of a burst in SuperSpeed mode. The actual number of packets is
/// (value + 1), so:
/// - 0 = 1 packet per burst
/// - 15 = 16 packets per burst
///
/// Bursts allow more efficient use of SuperSpeed links by sending multiple
/// packets back-to-back without waiting for individual acknowledgments.
class BurstSize {
  const BurstSize(this.value)
    : assert(value >= 0 && value <= 15, 'Burst size must be 0-15');

  /// Raw burst size value (0-15).
  final int value;

  /// Single packet per burst (value = 0).
  static const BurstSize single = .new(0);

  /// Maximum burst size (16 packets, value = 15).
  static const BurstSize max = .new(15);

  /// Actual number of packets per burst.
  ///
  /// Calculated as (value + 1).
  int get packets => value + 1;

  @override
  bool operator ==(Object other) => other is BurstSize && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$packets packet${packets == 1 ? '' : 's'}';
}

/// Type-safe SuperSpeed endpoint companion attributes.
///
/// The SuperSpeed endpoint companion descriptor includes an attributes
/// field whose interpretation depends on the endpoint transfer type:
///
/// - Bulk endpoints: Bits 0-4 specify max streams (0-31)
/// - Isochronous endpoints: Bits 0-1 specify mult (0-2)
/// - Interrupt/Control endpoints: Reserved, must be 0
class SSEndpointAttributes {
  /// Bulk endpoint attributes.
  ///
  /// [streams] specifies the maximum number of bulk streams supported.
  /// Value 0-31 represents the maximum stream ID (2^streams supported).
  const SSEndpointAttributes.bulk({int streams = 0})
    : assert(streams >= 0 && streams <= 31, 'Streams must be 0-31'),
      value = streams;

  /// Isochronous endpoint attributes.
  ///
  /// [mult] specifies packets per service interval (0-2).
  /// Actual packets = mult + 1.
  const SSEndpointAttributes.isochronous({required int mult})
    : assert(mult >= 0 && mult <= 2, 'Mult must be 0-2'),
      value = mult;

  /// Interrupt endpoint attributes.
  ///
  /// No additional attributes for interrupt endpoints.
  const SSEndpointAttributes.interrupt() : value = 0;

  /// Parses attributes from bmAttributes byte given the transfer type.
  factory SSEndpointAttributes.fromByte(int byte, TransferType transferType) {
    return switch (transferType) {
      TransferType.bulk => .bulk(streams: byte & 0x1F),
      TransferType.isochronous => .isochronous(mult: byte & 0x03),
      _ => const .interrupt(),
    };
  }

  /// The final bmAttributes field value.
  final int value;

  @override
  bool operator ==(Object other) =>
      other is SSEndpointAttributes && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SSEndpointAttributes(0x${value.toRadixString(16)})';
}

/// Type-safe bytes per interval (0-65535).
///
/// Specifies the total number of bytes this endpoint will transfer per
/// service interval. Used in SuperSpeed endpoint companion descriptors
/// for isochronous and interrupt endpoints.
///
/// For isochronous/interrupt endpoints, this helps the host allocate
/// bus bandwidth appropriately.
class BytesPerInterval {
  const BytesPerInterval(this.value)
    : assert(
        value >= 0 && value <= 65535,
        'Bytes per interval must be 0-65535',
      );

  /// Number of bytes per interval (0-65535).
  final int value;

  /// No bytes per interval (not used).
  static const BytesPerInterval none = .new(0);

  /// Converts to wBytesPerInterval field value.
  int toUint16() => value;

  @override
  bool operator ==(Object other) =>
      other is BytesPerInterval && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value bytes/interval';
}

/// Type-safe extended bytes per interval for SuperSpeedPlus (0-4294967295).
///
/// Used in SuperSpeedPlus isochronous endpoint companion descriptors to
/// specify larger transfer sizes that exceed the 16-bit limit. This allows
/// specifying up to 4 GB per service interval for very high bandwidth
/// isochronous transfers.
class ExtendedBytesPerInterval {
  const ExtendedBytesPerInterval(this.value)
    : assert(value >= 0, 'Bytes per interval must be non-negative');

  /// Number of bytes per interval (0-4294967295).
  final int value;

  /// No bytes per interval (not used).
  static const ExtendedBytesPerInterval none = .new(0);

  /// Converts to dwBytesPerInterval field value.
  int toUint32() => value;

  @override
  bool operator ==(Object other) =>
      other is ExtendedBytesPerInterval && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value bytes/interval';
}

/// Type-safe device class code.
///
/// Specifies the functional category when used at the device descriptor level
/// (bDeviceClass field). A value of 0x00 indicates that class information
/// is specified at the interface level instead.
class DeviceClass {
  const DeviceClass(this.value)
    : assert(value >= 0 && value <= 255, 'Device class must be 0-255');

  /// Creates from a USBClass enum value.
  factory DeviceClass.fromUSBClass(USBClass usbClass) => .new(usbClass.value);

  /// The raw device class value (0-255).
  final int value;

  /// Composite device - class info at interface level (0x00).
  ///
  /// Use this when your device has multiple functions that each
  /// specify their own class in interface descriptors.
  static const DeviceClass composite = .new(0x00);

  /// Miscellaneous device class (0xEF).
  ///
  /// Often used with Interface Association Descriptors for
  /// multi-function devices.
  static const DeviceClass miscellaneous = .new(0xEF);

  /// Vendor-specific device class (0xFF).
  ///
  /// For devices with vendor-defined functionality requiring
  /// custom drivers.
  static const DeviceClass vendorSpecific = .new(0xFF);

  @override
  bool operator ==(Object other) =>
      other is DeviceClass && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      'DeviceClass(0x${value.toRadixString(16).padLeft(2, '0')})';
}

/// Type-safe device subclass code.
///
/// Further refines the device class when used at the device descriptor level
/// (bDeviceSubClass field). Interpretation depends on the device class.
class DeviceSubClass {
  const DeviceSubClass(this.value)
    : assert(value >= 0 && value <= 255, 'Device subclass must be 0-255');

  /// The raw device subclass value (0-255).
  final int value;

  /// No subclass specified (0x00).
  static const DeviceSubClass none = .new(0x00);

  /// Common subclass (0x02) for miscellaneous devices.
  ///
  /// Used with DeviceClass.miscellaneous for multi-function
  /// devices using Interface Association Descriptors.
  static const DeviceSubClass common = .new(0x02);

  @override
  bool operator ==(Object other) =>
      other is DeviceSubClass && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      'DeviceSubClass(0x${value.toRadixString(16).padLeft(2, '0')})';
}

/// Type-safe device protocol code.
///
/// Specifies the protocol when used at the device descriptor level
/// (bDeviceProtocol field). Interpretation depends on the device class
/// and subclass.
class DeviceProtocol {
  const DeviceProtocol(this.value)
    : assert(value >= 0 && value <= 255, 'Device protocol must be 0-255');

  /// The raw device protocol value (0-255).
  final int value;

  /// No protocol specified (0x00).
  static const DeviceProtocol none = .new(0x00);

  /// Interface Association Descriptor protocol (0x01).
  ///
  /// Used with DeviceClass.miscellaneous and DeviceSubClass.common
  /// to indicate the device uses Interface Association Descriptors.
  static const DeviceProtocol iad = .new(0x01);

  @override
  bool operator ==(Object other) =>
      other is DeviceProtocol && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      'DeviceProtocol(0x${value.toRadixString(16).padLeft(2, '0')})';
}

/// USB transfer direction.
///
/// Encoded in bit 7 of bEndpointAddress and bmRequestType.
enum USBDirection {
  /// Host to device (OUT transfer).
  out(0x00),

  /// Device to host (IN transfer).
  in_(0x80);

  const USBDirection(this.value);

  /// Raw value for bit 7.
  final int value;

  /// Direction bit mask (bit 7).
  static const int mask = 0x80;

  /// Extracts direction from bEndpointAddress or bmRequestType.
  static USBDirection fromByte(int byte) =>
      (byte & mask) == in_.value ? in_ : out;

  /// True if this is an IN direction.
  bool get isIn => this == in_;

  /// True if this is an OUT direction.
  bool get isOut => this == out;
}

/// USB endpoint transfer types.
///
/// Encoded in bits 0-1 of bmAttributes.
enum TransferType {
  /// Control transfer (structured, reliable, bidirectional).
  control(0x00),

  /// Isochronous transfer (time-critical, guaranteed bandwidth, no retries).
  isochronous(0x01),

  /// Bulk transfer (large, reliable, best-effort bandwidth).
  bulk(0x02),

  /// Interrupt transfer (small, periodic, bounded latency).
  interrupt(0x03);

  const TransferType(this.value);

  /// Raw value for bits 0-1 of bmAttributes.
  final int value;

  /// Extracts transfer type from bmAttributes byte.
  static TransferType fromAttributes(int bmAttributes) {
    final masked = bmAttributes & 0x03;
    return TransferType.values.firstWhere((t) => t.value == masked);
  }
}

/// USB device class codes.
///
/// Identifies the functional category of a device or interface.
/// These codes are standardized by the USB Implementers Forum (USB-IF)
/// and allow operating systems to load appropriate drivers.
///
/// Each device or interface specifies a class, subclass, and protocol
/// that together define its functionality.
enum USBClass {
  /// Class defined at interface level (bDeviceClass = 0x00).
  ///
  /// When used at device level, indicates that class information is
  /// specified in interface descriptors rather than at the device level.
  /// This is common for composite devices with multiple functions.
  interface(0x00),

  /// Audio device class (0x01).
  ///
  /// Devices that handle audio streams: speakers, microphones, headsets,
  /// MIDI interfaces, and audio mixers. Uses the Audio Device Class (ADC)
  /// specification.
  audio(0x01),

  /// Communications device class (CDC, 0x02).
  ///
  /// Telecommunications and networking devices: modems, ISDN adapters,
  /// USB-to-serial converters, network adapters (RNDIS, ECM, NCM).
  /// Uses the Communications Device Class specification.
  comm(0x02),

  /// Human Interface Device class (HID, 0x03).
  ///
  /// Human input and output devices: keyboards, mice, game controllers,
  /// touchscreens, barcode readers. Uses the HID specification with
  /// report descriptors.
  hid(0x03),

  /// Physical Interface Device class (0x05).
  ///
  /// Devices that provide force feedback or other physical interactions,
  /// such as force-feedback game controllers and haptic devices.
  physical(0x05),

  /// Still Imaging Device class (0x06).
  ///
  /// Digital cameras and scanners. Uses the Picture Transfer Protocol (PTP)
  /// or other imaging protocols.
  image(0x06),

  /// Printer device class (0x07).
  ///
  /// Printers and print servers. Supports various printer languages and
  /// bidirectional communication for status reporting.
  printer(0x07),

  /// Mass Storage Device class (0x08).
  ///
  /// Storage devices: USB flash drives, external hard drives, card readers,
  /// optical drives. Typically uses SCSI commands over bulk-only transport.
  massStorage(0x08),

  /// Hub device class (0x09).
  ///
  /// USB hubs that provide additional USB ports. Includes both external
  /// hubs and root hubs built into host controllers.
  hub(0x09),

  /// CDC-Data device class (0x0A).
  ///
  /// Data interfaces for CDC devices. Works in conjunction with a CDC
  /// Communications interface to transfer data.
  cdcData(0x0A),

  /// Smart Card device class (0x0B).
  ///
  /// Smart card readers and Chip Card Interface Devices (CCID).
  /// Used for authentication tokens and secure elements.
  smartCard(0x0B),

  /// Content Security device class (0x0D).
  ///
  /// Devices related to content protection and digital rights management.
  contentSecurity(0x0D),

  /// Video device class (0x0E).
  ///
  /// Video streaming devices: webcams, video capture cards, video
  /// conferencing equipment. Uses the USB Video Class (UVC) specification.
  video(0x0E),

  /// Personal Healthcare device class (0x0F).
  ///
  /// Medical and fitness devices: blood pressure monitors, glucose meters,
  /// pulse oximeters, thermometers. Uses IEEE 11073 protocols.
  personalHealthcare(0x0F),

  /// Audio/Video device class (0x10).
  ///
  /// Devices that combine audio and video functionality, such as
  /// videoconferencing systems and multimedia streaming devices.
  audioVideo(0x10),

  /// Billboard device class (0x11).
  ///
  /// USB Type-C billboard devices that provide information about
  /// alternate modes and connection state.
  billboard(0x11),

  /// USB Type-C Bridge device class (0x12).
  ///
  /// Devices that bridge USB Type-C functionality.
  usbTypeCBridge(0x12),

  /// Diagnostic device class (0xDC).
  ///
  /// Devices used for USB debugging and diagnostics.
  diagnostic(0xDC),

  /// Wireless Controller class (0xE0).
  ///
  /// Wireless adapters and controllers: Bluetooth adapters, Wi-Fi dongles,
  /// wireless USB host controllers.
  wirelessController(0xE0),

  /// Miscellaneous device class (0xEF).
  ///
  /// Devices that don't fit into other standard classes but use
  /// common protocols. Often used with Interface Association Descriptors
  /// for multi-function devices.
  miscellaneous(0xEF),

  /// Application Specific device class (0xFE).
  ///
  /// Devices implementing application-specific protocols such as
  /// Device Firmware Update (DFU) or IrDA Bridge.
  applicationSpecific(0xFE),

  /// Vendor-specific class (0xFF).
  ///
  /// Devices with vendor-defined functionality that doesn't fit into
  /// standard USB classes. Requires vendor-specific drivers.
  vendorSpecific(0xFF);

  const USBClass(this.value);

  /// Raw class code value.
  final int value;
}

/// USB descriptor types.
///
/// These type codes identify different kinds of USB descriptors
/// returned by GET_DESCRIPTOR requests.
enum USBDescriptorType {
  /// Device descriptor (0x01).
  device(0x01),

  /// Configuration descriptor (0x02).
  config(0x02),

  /// String descriptor (0x03).
  string(0x03),

  /// Interface descriptor (0x04).
  interface(0x04),

  /// Endpoint descriptor (0x05).
  endpoint(0x05),

  /// Device qualifier descriptor (0x06).
  deviceQualifier(0x06),

  /// Other speed configuration descriptor (0x07).
  otherSpeedConfig(0x07),

  /// Interface power descriptor (0x08).
  interfacePower(0x08),

  /// OTG descriptor (0x09).
  otg(0x09),

  /// Debug descriptor (0x0A).
  debug(0x0A),

  /// Interface association descriptor (0x0B).
  interfaceAssociation(0x0B),

  /// SuperSpeed endpoint companion descriptor (0x30).
  ssEndpointComp(0x30),

  /// SuperSpeedPlus isochronous endpoint companion descriptor (0x31).
  sspIsocEndpointComp(0x31);

  const USBDescriptorType(this.value);

  /// The raw descriptor type value.
  final int value;
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

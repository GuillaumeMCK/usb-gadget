import 'dart:convert';
import 'dart:typed_data';

import '/usb_gadget.dart';

/// USB specification version.
///
/// Used to specify the USB version in the `bcdUSB` field of the device
/// descriptor. The BCD (Binary Coded Decimal) format encodes the version
/// as four hexadecimal digits (e.g., `0x0200` for USB 2.0).
enum UsbVersion {
  /// USB 1.1 (bcdUSB = 0x0110)
  v11(0x0110),

  /// USB 2.0 (bcdUSB = 0x0200)
  v20(0x0200),

  /// USB 2.0 with BOS descriptor support (bcdUSB = 0x0201).
  ///
  /// Needed for WinUSB and other BOS-based features.
  v21(0x0201),

  /// USB 3.0 (bcdUSB = 0x0300)
  v30(0x0300),

  /// USB 3.1 (bcdUSB = 0x0310)
  v31(0x0310);

  const UsbVersion(this.value);

  /// The BCD value for this USB version.
  final int value;
}

/// USB Language IDs for string descriptors.
///
/// String descriptors can be localized to different languages. The language
/// is specified using a 16-bit language ID that combines:
/// - Primary language (low 10 bits)
/// - Sublanguage/dialect (high 6 bits)
///
/// These IDs follow the Microsoft Language ID specification used by USB.
enum USBLanguageId {
  /// English (United States) - 0x0409
  ///
  /// The most common language ID used in USB devices.
  enUS(0x0409),

  /// English (United Kingdom) - 0x0809
  enGB(0x0809),

  /// German (Germany) - 0x0407
  deDE(0x0407),

  /// French (France) - 0x040C
  frFR(0x040C),

  /// Spanish (Spain) - 0x0C0A
  esES(0x0C0A),

  /// Italian (Italy) - 0x0410
  itIT(0x0410),

  /// Japanese (Japan) - 0x0411
  jaJP(0x0411),

  /// Korean (Korea) - 0x0412
  koKR(0x0412),

  /// Chinese (Simplified, PRC) - 0x0804
  zhCN(0x0804),

  /// Chinese (Traditional, Taiwan) - 0x0404
  zhTW(0x0404),

  /// Portuguese (Brazil) - 0x0416
  ptBR(0x0416),

  /// Russian (Russia) - 0x0419
  ruRU(0x0419),

  /// Dutch (Netherlands) - 0x0413
  nlNL(0x0413),

  /// Swedish (Sweden) - 0x041D
  svSE(0x041D),

  /// Polish (Poland) - 0x0415
  plPL(0x0415);

  const USBLanguageId(this.value);

  /// The raw language ID value.
  final int value;

  /// Creates a language ID from its raw value, defaulting to [enUS] if not found.
  static USBLanguageId fromValue(int value, [USBLanguageId orElse = enUS]) =>
      USBLanguageId.values.firstWhere(
        (lang) => lang.value == value,
        orElse: () => orElse,
      );
}

/// A set of USB descriptors for a specific speed.
///
/// Each USB speed (Full-Speed, High-Speed, SuperSpeed, SuperSpeedPlus) can
/// have different descriptor configurations. A descriptor set contains all
/// descriptors needed for operation at that speed:
/// - Interface descriptors
/// - Endpoint descriptors
/// - Companion descriptors (for SuperSpeed+)
/// - Class-specific descriptors
class DescriptorSet {
  /// Creates a descriptor set from a list of descriptors.
  ///
  /// The descriptors should be in the order they appear in the configuration:
  /// 1. Interface descriptors
  /// 2. Class-specific descriptors (if any)
  /// 3. Endpoint descriptors
  /// 4. SuperSpeed companion descriptors (if applicable)
  const DescriptorSet(this.descriptors);

  final List<USBDescriptor> descriptors;

  int get totalLength => descriptors.fold(0, (sum, desc) => sum + desc.bLength);

  int get count => descriptors.length;

  Uint8List toBytes() {
    final buffer = BytesBuilder(copy: false);
    for (final descriptor in descriptors) {
      buffer.add(descriptor.toBytes());
    }
    return buffer.toBytes();
  }

  @override
  String toString() => 'DescriptorSet($count descriptors, $totalLength bytes)';
}

/// String descriptors for a specific language.
///
/// USB string descriptors can be localized to different languages. Each
/// language has its own set of strings indexed by string descriptor index.
///
/// String index 0 is reserved for the language ID list and should not be
/// included in the strings array.
class LanguageStrings {
  /// Creates a string set for a specific language.
  ///
  /// The [strings] list contains the actual string values, where:
  /// - Index 0 corresponds to string descriptor index 1
  /// - Index 1 corresponds to string descriptor index 2
  /// and so on. The language ID is specified separately in [language].
  const LanguageStrings({required this.language, required this.strings});

  /// The language ID for these strings.
  final USBLanguageId language;

  /// The string values (index 0 = descriptor index 1).
  final List<String> strings;

  /// Number of strings in this set.
  int get count => strings.length;

  /// Serializes the language strings to bytes.
  ///
  /// Format:
  /// - Language ID (2 bytes, little-endian)
  /// - NULL-separated, NULL-terminated UTF-8 strings
  ///   (string1\0string2\0...\0stringN\0)
  Uint8List toBytes() {
    final buffer = BytesBuilder(copy: false);

    // Write language ID
    final langId = ByteData(2)..setUint16(0, language.value, .little);
    buffer.add(langId.buffer.asUint8List());

    // Write NULL-separated, NULL-terminated strings
    for (final string in strings) {
      buffer
        ..add(utf8.encode(string))
        ..addByte(0);
    }

    return buffer.toBytes();
  }

  @override
  String toString() => 'LanguageStrings(${language.name}, $count strings)';
}

/// Descriptor generator for creating speed-specific descriptors.
///
/// Generates Full-Speed, High-Speed, SuperSpeed, and SuperSpeedPlus
/// descriptor sets from a shared base template. Handles endpoint
/// descriptor transformations based on USB speed requirements.
abstract class DescriptorGenerator {
  /// Generates a descriptor set for a specific USB speed.
  ///
  /// Takes a list of base descriptors and produces speed-specific variants:
  /// - Interface descriptors are copied as-is
  /// - EndpointDescriptor descriptors are converted to [USBEndpointDescriptor]
  ///   with speed-appropriate packet sizes and intervals
  /// - SuperSpeed endpoints include companion descriptors
  ///
  /// Returns a DescriptorSet ready for use at the specified speed.
  static DescriptorSet generateForSpeed(
    List<USBDescriptor> baseDescriptors,
    Speed speed,
  ) {
    final result = <USBDescriptor>[];

    for (final desc in baseDescriptors) {
      if (desc is EndpointDescriptor) {
        // Generate endpoint descriptor with speed-specific values
        result.add(
          USBEndpointDescriptor(
            address: desc.address,
            attributes: EndpointAttributes.from(
              desc.config.transferType,
              syncType: switch (desc.config) {
                IsochronousEndpointConfig(:final syncType) => syncType,
                _ => null,
              },
              usageType: switch (desc.config) {
                IsochronousEndpointConfig(:final usageType) => usageType,
                _ => null,
              },
            ),
            maxPacketSize: desc.config.getMaxPacketSize(speed),
            interval: desc.config.getPollingInterval(speed),
          ),
        );

        // Add SuperSpeed companion descriptor if needed
        if (speed.isSuperSpeed) {
          result.add(const USBSSEPCompDescriptor());
        }
      } else {
        // Copy other descriptors as-is (interfaces, class-specific, etc.)
        result.add(desc);
      }
    }

    return DescriptorSet(result);
  }
}

/// Base class for all USB descriptors.
///
/// All USB descriptors share a common header format:
/// - First byte: bLength (total descriptor length including header)
/// - Second byte: bDescriptorType (descriptor type code)
///
/// This abstract class defines the interface that all descriptor
/// implementations must provide.
abstract class USBDescriptor {
  /// Wraps a raw descriptor blob.
  ///
  /// Use this to supply pre-built descriptors without needing explicit
  /// Dart structures. The first byte must contain the descriptor length,
  /// and the second byte must contain the descriptor type.
  factory USBDescriptor.raw(List<int> bytes) = RawUSBDescriptor;

  /// Length of the descriptor in bytes.
  ///
  /// This includes the bLength and bDescriptorType fields themselves.
  /// Must match the actual serialized size returned by [toBytes].
  int get bLength;

  /// Type of the descriptor.
  ///
  /// Identifies what kind of descriptor this is (device, configuration,
  /// interface, endpoint, etc.). See [USBDescriptorType] for standard types.
  int get bDescriptorType;

  /// Serializes the descriptor to bytes.
  ///
  /// Returns a byte array representation suitable for transmission to the host
  /// or writing to FunctionFs. The returned array must be exactly [bLength] bytes
  /// and start with bLength and bDescriptorType.
  Uint8List toBytes();
}

/// Raw USB descriptor wrapper.
class RawUSBDescriptor implements USBDescriptor {
  RawUSBDescriptor(List<int> bytes)
    : assert(bytes.length >= 2, 'Descriptor data must be at least 2 bytes'),
      _data = Uint8List.fromList(bytes);

  final Uint8List _data;

  @override
  int get bLength => _data[0];

  @override
  int get bDescriptorType => _data[1];

  @override
  Uint8List toBytes() => Uint8List.fromList(_data);
}

/// USB Interface Descriptor.
///
/// Describes a logical grouping of endpoints that perform a related function
/// within a USB device configuration. An interface represents a single function
/// (like mass storage, audio input, etc.) and can have multiple alternate
/// settings to provide different bandwidth or endpoint configurations.
class USBInterfaceDescriptor implements USBDescriptor {
  /// Creates a USB interface descriptor.
  ///
  /// Parameters:
  /// - [interfaceNumber]: Interface index within the configuration (required)
  /// - [alternateSetting]: Alternate setting index (default: 0)
  /// - [numEndpoints]: Number of endpoints excluding EP0 (required)
  /// - [class_]: Class code (required, use [ClassType] enum)
  /// - [stringIndex]: String descriptor index (default: none)
  const USBInterfaceDescriptor({
    required this.interfaceNumber,
    this.alternateSetting = AlternateSetting.default_,
    required this.numEndpoints,
    required this.class_,
    this.stringIndex = StringIndex.none,
  });

  @override
  int get bLength => 9;

  @override
  int get bDescriptorType => USBDescriptorType.interface.value;

  /// Interface number.
  ///
  /// Zero-based index identifying this interface within its configuration.
  final InterfaceNumber interfaceNumber;

  /// Alternate setting number.
  ///
  /// Identifies which alternate setting this descriptor describes. Interface
  /// alternate settings allow changing interface characteristics (like endpoints
  /// or bandwidth) without changing the configuration.
  final AlternateSetting alternateSetting;

  /// Number of endpoints (excluding endpoint zero).
  ///
  /// The control endpoint (endpoint 0) is not counted here.
  final EndpointCount numEndpoints;

  /// Interface class code.
  ///
  /// Identifies the class specification this interface adheres to.
  final Class class_;

  /// Index of string descriptor describing this interface.
  final StringIndex stringIndex;

  @override
  Uint8List toBytes() {
    return Uint8List.fromList([
      bLength,
      bDescriptorType,
      interfaceNumber.value,
      alternateSetting.value,
      numEndpoints.value,
      class_.code,
      class_.subClass,
      class_.protocol,
      stringIndex.value,
    ]);
  }
}

/// USB Endpoint Descriptor.
///
/// Describes a USB endpoint within an interface. Endpoints are the ultimate
/// source or sink of data in USB transfers. Each endpoint has a unique address
/// within a device and specific transfer characteristics.
///
/// By default this produces a standard 7-byte descriptor (`bLength = 7`).
/// When [bRefresh] or [bSynchAddress] are non-zero (USB Audio Class usage),
/// `bLength` becomes 9 to include those extra fields.
class USBEndpointDescriptor implements USBDescriptor {
  /// Creates a USB endpoint descriptor.
  ///
  /// Parameters:
  /// - [address]: Endpoint address with direction (required)
  /// - [attributes]: Transfer type and attributes (required)
  /// - [maxPacketSize]: Maximum packet size (required)
  /// - [interval]: Polling interval (default: none)
  /// - [bRefresh]: Audio refresh rate (default: 0, non-audio endpoints)
  /// - [bSynchAddress]: Audio sync endpoint address (default: 0, non-audio endpoints)
  const USBEndpointDescriptor({
    required this.address,
    required this.attributes,
    required this.maxPacketSize,
    this.interval = const PollingInterval.none(),
    this.bRefresh = 0,
    this.bSynchAddress = 0,
  });

  /// Endpoint address (includes direction and number).
  final EndpointAddress address;

  /// Endpoint attributes (transfer type and characteristics).
  final EndpointAttributes attributes;

  /// Maximum packet size this endpoint can send/receive.
  final MaxPacketSize maxPacketSize;

  /// Interval for polling endpoint for data transfers.
  final PollingInterval interval;

  /// Refresh rate for audio endpoints (USB Audio Class).
  ///
  /// Indicates how often the host should read/update the synchronization
  /// endpoint. Value is 2^(bRefresh-1) frames (full-speed) or
  /// 2^(bRefresh-1) × 125μs (high-speed). Set to 0 for non-audio endpoints.
  final int bRefresh;

  /// Synchronization endpoint address for audio endpoints (USB Audio Class).
  ///
  /// Address of the associated synchronization endpoint for isochronous data
  /// endpoints that require explicit synchronization. Set to 0 if not used.
  final int bSynchAddress;

  /// Returns 9 for audio endpoints (non-zero [bRefresh] or [bSynchAddress]),
  /// 7 for all other endpoints.
  @override
  int get bLength => (bRefresh != 0 || bSynchAddress != 0) ? 9 : 7;

  @override
  int get bDescriptorType => USBDescriptorType.endpoint.value;

  @override
  Uint8List toBytes() {
    final bytes = ByteData(bLength)
      ..setUint8(0, bLength)
      ..setUint8(1, bDescriptorType)
      ..setUint8(2, address.value)
      ..setUint8(3, attributes.value)
      ..setUint16(4, maxPacketSize.value, .little)
      ..setUint8(6, interval.value);
    if (bLength == 9) {
      bytes
        ..setUint8(7, bRefresh)
        ..setUint8(8, bSynchAddress);
    }
    return bytes.buffer.asUint8List();
  }
}

/// USB SuperSpeed Endpoint Companion Descriptor.
///
/// Provides additional information for SuperSpeed endpoints. Required for all
/// endpoints when operating at SuperSpeed (5 Gbps). This descriptor immediately
/// follows the endpoint descriptor it describes.
class USBSSEPCompDescriptor implements USBDescriptor {
  /// Creates a SuperSpeed endpoint companion descriptor.
  ///
  /// Parameters:
  /// - [maxBurst]: Maximum burst size (default: single packet)
  /// - [attributes]: Endpoint-specific attributes (default: interrupt/control)
  /// - [bytesPerInterval]: Bytes per interval (default: none)
  const USBSSEPCompDescriptor({
    this.maxBurst = BurstSize.single,
    this.attributes = const SSEndpointAttributes.interrupt(),
    this.bytesPerInterval = BytesPerInterval.none,
  });

  @override
  int get bLength => 6;

  @override
  int get bDescriptorType => USBDescriptorType.ssEndpointComp.value;

  /// Maximum number of packets per burst.
  final BurstSize maxBurst;

  /// Endpoint-specific attributes.
  ///
  /// For bulk: stream support
  /// For isochronous: mult (packets per interval)
  /// For interrupt/control: reserved (0)
  final SSEndpointAttributes attributes;

  /// Total bytes per service interval.
  final BytesPerInterval bytesPerInterval;

  /// Legacy getter for compatibility.
  int get bMaxBurst => maxBurst.value;

  /// Legacy getter for compatibility.
  int get bmAttributes => attributes.value;

  /// Legacy getter for compatibility.
  int get wBytesPerInterval => bytesPerInterval.toUint16();

  @override
  Uint8List toBytes() {
    final bytes = ByteData(6)
      ..setUint8(0, bLength)
      ..setUint8(1, bDescriptorType)
      ..setUint8(2, maxBurst.value)
      ..setUint8(3, attributes.value)
      ..setUint16(4, bytesPerInterval.toUint16(), .little);
    return bytes.buffer.asUint8List();
  }
}

/// USB SuperSpeedPlus Isochronous Endpoint Companion Descriptor.
///
/// Provides additional information for SuperSpeedPlus isochronous endpoints.
/// Used when operating at SuperSpeedPlus speeds (10+ Gbps) with isochronous
/// transfer type.
class USBSSPIsocEndpointDescriptor implements USBDescriptor {
  /// Creates a SuperSpeedPlus isochronous endpoint companion descriptor.
  ///
  /// Parameters:
  /// - [wReserved]: Reserved field (default: 0)
  /// - [bytesPerInterval]: Extended bytes per interval (required)
  const USBSSPIsocEndpointDescriptor({
    this.wReserved = 0,
    required this.bytesPerInterval,
  });

  @override
  int get bLength => 8;

  @override
  int get bDescriptorType => USBDescriptorType.sspIsocEndpointComp.value;

  /// Reserved field, must be 0.
  final int wReserved;

  /// Number of bytes per service interval.
  ///
  /// Specifies the total bytes this isochronous endpoint will transfer per
  /// service interval at SuperSpeedPlus. Can be larger than the 16-bit limit
  /// of wBytesPerInterval in the SS companion descriptor.
  final ExtendedBytesPerInterval bytesPerInterval;

  /// Legacy getter for compatibility.
  int get dwBytesPerInterval => bytesPerInterval.toUint32();

  @override
  Uint8List toBytes() {
    final bytes = ByteData(8)
      ..setUint8(0, bLength)
      ..setUint8(1, bDescriptorType)
      ..setUint16(2, wReserved, .little)
      ..setUint32(4, bytesPerInterval.toUint32(), .little);
    return bytes.buffer.asUint8List();
  }
}

/// USB Interface Association Descriptor.
///
/// Groups multiple interfaces that form a single function. This allows a
/// single device driver to manage multiple related interfaces. Commonly used
/// by composite devices like USB webcams (video + audio interfaces) or
/// multi-function peripherals.
class USBInterfaceAssocDescriptor implements USBDescriptor {
  /// Creates an interface association descriptor.
  ///
  /// Parameters:
  /// - [firstInterface]: First interface number (required)
  /// - [interfaceCount]: Number of interfaces in group (required)
  /// - [functionClass]: Function class code (required)
  /// - [functionSubClass]: Function subclass (default: 0)
  /// - [functionProtocol]: Function protocol (default: 0)
  /// - [functionString]: String descriptor index (default: none)
  const USBInterfaceAssocDescriptor({
    required this.firstInterface,
    required this.interfaceCount,
    required this.functionClass,
    this.functionSubClass = 0,
    this.functionProtocol = 0,
    this.functionString = StringIndex.none,
  });

  @override
  int get bLength => 8;

  @override
  int get bDescriptorType => USBDescriptorType.interfaceAssociation.value;

  /// Interface number of the first interface in the function.
  ///
  /// Interfaces must be contiguous, starting from this number.
  final InterfaceNumber firstInterface;

  /// Number of contiguous interfaces in the function.
  ///
  /// The function includes interfaces [firstInterface] through
  /// (firstInterface + interfaceCount - 1).
  final int interfaceCount;

  /// Function class code.
  ///
  /// Identifies the class specification that applies to this function as a whole.
  final int functionClass;

  /// Function subclass code.
  ///
  /// Further qualifies the function class.
  final int functionSubClass;

  /// Function protocol code.
  ///
  /// Protocol used by this function.
  final int functionProtocol;

  /// Index of string descriptor describing this function.
  final StringIndex functionString;

  /// Legacy getter for compatibility.
  int get bFirstInterface => firstInterface.value;

  /// Legacy getter for compatibility.
  int get bInterfaceCount => interfaceCount;

  /// Legacy getter for compatibility.
  int get bFunctionClass => functionClass;

  /// Legacy getter for compatibility.
  int get bFunctionSubClass => functionSubClass;

  /// Legacy getter for compatibility.
  int get bFunctionProtocol => functionProtocol;

  /// Legacy getter for compatibility.
  int get iFunction => functionString.value;

  @override
  Uint8List toBytes() {
    return Uint8List.fromList([
      bLength,
      bDescriptorType,
      firstInterface.value,
      interfaceCount,
      functionClass,
      functionSubClass,
      functionProtocol,
      functionString.value,
    ]);
  }
}

/// Endpoint configuration: transfer type, packet size, and polling interval.
///
/// Use one of the subtypes to describe your endpoint:
/// - [BulkEndpointConfig] — reliable large transfers, no timing guarantee
/// - [ControlEndpointConfig] — structured bidirectional control transfers
/// - [InterruptEndpointConfig] — bounded-latency periodic transfers
/// - [IsochronousEndpointConfig] — guaranteed-bandwidth streaming transfers
///
/// Each subtype carries only the fields relevant to its transfer type and
/// overrides [getMaxPacketSize] and [getPollingInterval] directly — no
/// runtime dispatch on a `transferType` field is needed.
sealed class EndpointConfig {
  const EndpointConfig({this.maxPacketSize});

  const factory EndpointConfig.bulk({int? maxPacketSize}) = BulkEndpointConfig;

  const factory EndpointConfig.control({int? maxPacketSize}) =
      ControlEndpointConfig;

  const factory EndpointConfig.interrupt({
    required Duration interval,
    int? maxPacketSize,
  }) = InterruptEndpointConfig;

  const factory EndpointConfig.isochronous({
    required IsoSyncType syncType,
    required IsoUsageType usageType,
    int? maxPacketSize,
  }) = IsochronousEndpointConfig;

  /// Optional custom maximum packet size override (bytes).
  ///
  /// When `null`, the spec-mandated default for the transfer type and speed
  /// is used automatically. Set this only when you need a non-default size.
  final int? maxPacketSize;

  /// Transfer type of this endpoint.
  TransferType get transferType;

  /// Returns the [MaxPacketSize] for [speed].
  ///
  /// Applies [maxPacketSize] override when set; otherwise uses the
  /// USB-spec default for this transfer type and speed.
  MaxPacketSize getMaxPacketSize(Speed speed);

  /// Returns the [PollingInterval] for [speed].
  PollingInterval getPollingInterval(Speed speed);
}

/// Bulk transfer endpoint configuration.
///
/// Automatically selects packet size by speed:
/// - Full-Speed: 64 bytes
/// - High-Speed: 512 bytes
/// - SuperSpeed / SuperSpeedPlus: 512 bytes (USB 3.x spec §9.6.6)
///
/// Polling interval is irrelevant for bulk endpoints (always zero).
final class BulkEndpointConfig extends EndpointConfig {
  const BulkEndpointConfig({super.maxPacketSize});

  @override
  TransferType get transferType => TransferType.bulk;

  @override
  MaxPacketSize getMaxPacketSize(Speed speed) => switch (speed) {
    .fullSpeed => .fullSpeedBulk(maxPacketSize ?? 64),
    .highSpeed => const .highSpeedBulk(),
    _ => .superSpeed(maxPacketSize ?? 512),
  };

  @override
  PollingInterval getPollingInterval(Speed speed) => const .none();
}

/// Control transfer endpoint configuration.
///
/// Automatically selects packet size by speed:
/// - Full-Speed: 64 bytes
/// - High-Speed: 64 bytes (fixed by spec)
/// - SuperSpeed / SuperSpeedPlus: 512 bytes (fixed by spec)
///
/// Polling interval is irrelevant for control endpoints (always zero).
final class ControlEndpointConfig extends EndpointConfig {
  const ControlEndpointConfig({super.maxPacketSize});

  @override
  TransferType get transferType => TransferType.control;

  @override
  MaxPacketSize getMaxPacketSize(Speed speed) => switch (speed) {
    .fullSpeed => .fullSpeedControl(maxPacketSize ?? 64),
    .highSpeed => const .highSpeedControl(),
    _ => .superSpeed(maxPacketSize ?? 512),
  };

  @override
  PollingInterval getPollingInterval(Speed speed) => const .none();
}

/// Interrupt transfer endpoint configuration.
///
/// [interval] is the polling interval for Full-Speed (1–255 ms).
/// High-Speed and SuperSpeed exponents are derived automatically from it.
///
/// Automatically selects packet size by speed:
/// - Full-Speed: up to 64 bytes
/// - High-Speed: up to 1024 bytes
/// - SuperSpeed: up to 1024 bytes
final class InterruptEndpointConfig extends EndpointConfig {
  const InterruptEndpointConfig({required this.interval, super.maxPacketSize});

  /// Polling interval (used directly for Full-Speed; converted for HS/SS).
  final Duration interval;

  @override
  TransferType get transferType => TransferType.interrupt;

  @override
  MaxPacketSize getMaxPacketSize(Speed speed) => switch (speed) {
    .fullSpeed => .fullSpeedInterrupt(maxPacketSize ?? 64),
    .highSpeed => .highSpeedInterrupt(maxPacketSize ?? 1024),
    _ => .superSpeed(maxPacketSize ?? 1024),
  };

  @override
  PollingInterval getPollingInterval(Speed speed) {
    final ms = interval.inMilliseconds.clamp(1, 255);
    return switch (speed) {
      .fullSpeed => .fullSpeed(ms),
      .highSpeed => .highSpeedInterrupt(_msToExponent(ms)),
      _ => .superSpeed(_msToExponent(ms)),
    };
  }

  /// Maps a millisecond interval to a high-speed/SuperSpeed bInterval exponent.
  ///
  /// The actual interval is 2^(exp-1) × 125 µs; this method finds the
  /// smallest exponent whose interval is ≥ [ms].
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

/// Isochronous transfer endpoint configuration.
///
/// [syncType] and [usageType] define the isochronous synchronization model.
/// Polling interval is fixed by the spec (1 frame for FS, 1 microframe for HS).
///
/// Automatically selects packet size by speed:
/// - Full-Speed: up to 1023 bytes
/// - High-Speed: up to 1024 bytes (1 transaction/microframe)
/// - SuperSpeed: up to 1024 bytes
final class IsochronousEndpointConfig extends EndpointConfig {
  const IsochronousEndpointConfig({
    required this.syncType,
    required this.usageType,
    super.maxPacketSize,
  });

  /// Isochronous synchronization type (bits 2–3 of bmAttributes).
  final IsoSyncType syncType;

  /// Isochronous usage type (bits 4–5 of bmAttributes).
  final IsoUsageType usageType;

  @override
  TransferType get transferType => TransferType.isochronous;

  @override
  MaxPacketSize getMaxPacketSize(Speed speed) => switch (speed) {
    .fullSpeed => .fullSpeedIsochronous(maxPacketSize ?? 1023),
    .highSpeed => .highSpeedIsochronous(
      size: maxPacketSize ?? 1024,
      transactionsPerMicroframe: 1,
    ),
    _ => .superSpeed(maxPacketSize ?? 1024),
  };

  @override
  PollingInterval getPollingInterval(Speed speed) => switch (speed) {
    .fullSpeed => const PollingInterval.fullSpeed(1),
    .highSpeed => const PollingInterval.highSpeedIsochronous(),
    _ => const PollingInterval.superSpeed(1),
  };
}

/// Endpoint template for speed-independent endpoint definitions.
///
/// Provides a high-level endpoint specification that can be converted
/// to speed-specific descriptors. This is useful when you need to define
/// an endpoint once and generate descriptors for multiple USB speeds.
///
/// Use [DescriptorGenerator.generateForSpeed()] to convert this template
/// into actual endpoint descriptors appropriate for a specific USB speed.
class EndpointDescriptor implements USBDescriptor {
  /// Creates an endpoint template.
  ///
  /// Parameters:
  /// - [address]: Endpoint address with direction (required)
  /// - [config]: Endpoint configuration (required)
  const EndpointDescriptor({required this.address, required this.config});

  /// Endpoint address (number and direction).
  final EndpointAddress address;

  /// Endpoint configuration (transfer type, polling, packet size).
  final EndpointConfig config;

  @override
  int get bLength => 7;

  @override
  int get bDescriptorType => USBDescriptorType.endpoint.value;

  @override
  Uint8List toBytes() {
    throw UnsupportedError(
      'EndpointDescriptor must be converted to speed-specific descriptor '
      'using DescriptorGenerator.generateForSpeed()',
    );
  }
}

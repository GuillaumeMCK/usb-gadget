import 'dart:convert';
import 'dart:typed_data';

import '/usb_gadget.dart';

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
  /// - strings[0] is string descriptor index 1
  /// - strings[1] is string descriptor index 2
  /// - etc.
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
    final langId = ByteData(2)..setUint16(0, language.value, Endian.little);
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
  /// - EndpointTemplate descriptors are converted to USBEndpointDescriptorNoAudio
  ///   with speed-appropriate packet sizes and intervals
  /// - SuperSpeed endpoints include companion descriptors
  ///
  /// Returns a DescriptorSet ready for use at the specified speed.
  static DescriptorSet generateForSpeed(
    List<USBDescriptor> baseDescriptors,
    USBSpeed speed,
  ) {
    final result = <USBDescriptor>[];

    for (final desc in baseDescriptors) {
      if (desc is EndpointTemplate) {
        // Generate endpoint descriptor with speed-specific values
        result.add(
          USBEndpointDescriptorNoAudio(
            address: desc.address,
            attributes: desc.config.getAttributes(),
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
  factory USBDescriptor.raw(List<int> bytes) = _RawUSBDescriptor;

  /// Parses a descriptor from bytes.
  ///
  /// Automatically detects the descriptor type and returns the appropriate
  /// descriptor class. Supports interface, endpoint, SuperSpeed companion,
  /// and interface association descriptors.
  ///
  /// Throws [FormatException] if the descriptor is invalid or too short.
  static USBDescriptor parse(List<int> bytes) {
    if (bytes.length < 2) {
      throw FormatException('Descriptor too short: ${bytes.length}');
    }

    return switch (bytes[1]) {
      0x04 => USBInterfaceDescriptor.parse(bytes),
      0x05 => () {
        if (bytes.length < 7) {
          throw FormatException(
            'Endpoint descriptor too short: ${bytes.length}',
          );
        }

        final address = EndpointAddress.fromByte(bytes[2]);
        final attributes = EndpointAttributes.fromByte(bytes[3]);
        final maxPacketSize = MaxPacketSize.raw(bytes[4] | (bytes[5] << 8));
        final interval = PollingInterval.raw(bytes[6]);

        return switch (bytes.length) {
          7 => USBEndpointDescriptorNoAudio(
            address: address,
            attributes: attributes,
            maxPacketSize: maxPacketSize,
            interval: interval,
          ),
          9 => USBEndpointDescriptor(
            address: address,
            attributes: attributes,
            maxPacketSize: maxPacketSize,
            interval: interval,
            bRefresh: bytes[7],
            bSynchAddress: bytes[8],
          ),
          _ => throw FormatException(
            'Invalid endpoint descriptor length: ${bytes.length}',
          ),
        };
      }(),
      0x30 => USBSSEPCompDescriptor.parse(bytes),
      0x31 => USBSSPIsocEndpointDescriptor.parse(bytes),
      0x0B => USBInterfaceAssocDescriptor.parse(bytes),
      _ => _RawUSBDescriptor(bytes),
    };
  }

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
class _RawUSBDescriptor implements USBDescriptor {
  _RawUSBDescriptor(List<int> bytes)
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
  /// - [interfaceClass]: Class code (required, use [USBClass] enum)
  /// - [interfaceSubClass]: Subclass code (default: 0)
  /// - [interfaceProtocol]: Protocol code (default: 0)
  /// - [stringIndex]: String descriptor index (default: none)
  const USBInterfaceDescriptor({
    required this.interfaceNumber,
    this.alternateSetting = AlternateSetting.default_,
    required this.numEndpoints,
    required this.interfaceClass,
    this.interfaceSubClass = 0,
    this.interfaceProtocol = 0,
    this.stringIndex = StringIndex.none,
  });

  /// Parses an interface descriptor from bytes.
  ///
  /// Throws [FormatException] if the descriptor is too short.
  factory USBInterfaceDescriptor.parse(List<int> bytes) {
    if (bytes.length < 9) {
      throw FormatException('Interface descriptor too short: ${bytes.length}');
    }
    return USBInterfaceDescriptor(
      interfaceNumber: InterfaceNumber(bytes[2]),
      alternateSetting: AlternateSetting(bytes[3]),
      numEndpoints: EndpointCount(bytes[4]),
      interfaceClass: USBClass.values.firstWhere(
        (c) => c.value == bytes[5],
        orElse: () => USBClass.interface,
      ),
      interfaceSubClass: bytes[6],
      interfaceProtocol: bytes[7],
      stringIndex: StringIndex(bytes[8]),
    );
  }

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
  final USBClass interfaceClass;

  /// Interface subclass code.
  ///
  /// Further qualifies the class. Interpretation depends on [interfaceClass].
  final int interfaceSubClass;

  /// Interface protocol code.
  ///
  /// Protocol within the class and subclass. Interpretation depends on
  /// [interfaceClass] and [interfaceSubClass].
  final int interfaceProtocol;

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
      interfaceClass.value,
      interfaceSubClass,
      interfaceProtocol,
      stringIndex.value,
    ]);
  }
}

/// USB Endpoint Descriptor (standard 7-byte version).
///
/// Describes a USB endpoint within an interface. Endpoints are the ultimate
/// source or sink of data in USB transfers. Each endpoint has a unique address
/// within a device and specific transfer characteristics.
class USBEndpointDescriptorNoAudio implements USBDescriptor {
  /// Creates a USB endpoint descriptor without audio fields.
  ///
  /// This is the standard 7-byte endpoint descriptor used by most devices.
  /// Audio devices may use the extended 9-byte version with additional fields.
  ///
  /// Parameters:
  /// - [address]: Endpoint address with direction (required)
  /// - [attributes]: Transfer type and attributes (required)
  /// - [maxPacketSize]: Maximum packet size (required)
  /// - [interval]: Polling interval (default: none)
  const USBEndpointDescriptorNoAudio({
    required this.address,
    required this.attributes,
    required this.maxPacketSize,
    this.interval = const PollingInterval.none(),
  });

  @override
  int get bLength => 7;

  @override
  int get bDescriptorType => USBDescriptorType.endpoint.value;

  /// Endpoint address (includes direction and number).
  final EndpointAddress address;

  /// Endpoint attributes (transfer type and characteristics).
  final EndpointAttributes attributes;

  /// Maximum packet size this endpoint can send/receive.
  final MaxPacketSize maxPacketSize;

  /// Interval for polling endpoint for data transfers.
  final PollingInterval interval;

  /// Legacy getter for compatibility.
  int get bEndpointAddress => address.value;

  /// Legacy getter for compatibility.
  int get bmAttributes => attributes.value;

  /// Legacy getter for compatibility.
  int get wMaxPacketSize => maxPacketSize.value;

  /// Legacy getter for compatibility.
  int get bInterval => interval.value;

  @override
  Uint8List toBytes() {
    final bytes = ByteData(7)
      ..setUint8(0, bLength)
      ..setUint8(1, bDescriptorType)
      ..setUint8(2, address.value)
      ..setUint8(3, attributes.value)
      ..setUint16(4, maxPacketSize.value, Endian.little)
      ..setUint8(6, interval.value);
    return bytes.buffer.asUint8List();
  }
}

/// USB Endpoint Descriptor (extended 9-byte version with audio fields).
///
/// Extended version of endpoint descriptor with fields used by audio endpoints.
/// Most non-audio devices should use [USBEndpointDescriptorNoAudio] instead.
class USBEndpointDescriptor extends USBEndpointDescriptorNoAudio {
  /// Creates a USB endpoint descriptor with audio fields.
  ///
  /// Parameters:
  /// - [address]: Endpoint address with direction (required)
  /// - [attributes]: Transfer type and attributes (required)
  /// - [maxPacketSize]: Maximum packet size (required)
  /// - [interval]: Polling interval (default: none)
  /// - [bRefresh]: Audio refresh rate (default: 0)
  /// - [bSynchAddress]: Audio sync endpoint address (default: 0)
  const USBEndpointDescriptor({
    required super.address,
    required super.attributes,
    required super.maxPacketSize,
    super.interval,
    this.bRefresh = 0,
    this.bSynchAddress = 0,
  });

  @override
  int get bLength => 9;

  /// Refresh rate for audio endpoints.
  ///
  /// Used by audio isochronous endpoints to indicate how often the host
  /// should read/update the synchronization endpoint. Value is 2^(bRefresh-1)
  /// frames for full-speed and 2^(bRefresh-1) * 125μs for high-speed.
  final int bRefresh;

  /// Synchronization endpoint address for audio endpoints.
  ///
  /// For audio isochronous data endpoints that require explicit synchronization,
  /// this indicates the address of the synchronization endpoint. 0 if not used.
  final int bSynchAddress;

  @override
  Uint8List toBytes() {
    return Uint8List.fromList([...super.toBytes(), bRefresh, bSynchAddress]);
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

  /// Parses a SuperSpeed endpoint companion descriptor from bytes.
  ///
  /// Throws [FormatException] if the descriptor is too short.
  factory USBSSEPCompDescriptor.parse(List<int> bytes) {
    if (bytes.length < 6) {
      throw FormatException('SS endpoint companion too short: ${bytes.length}');
    }
    return USBSSEPCompDescriptor(
      maxBurst: BurstSize(bytes[2]),
      bytesPerInterval: BytesPerInterval(bytes[4] | (bytes[5] << 8)),
    );
  }

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
      ..setUint16(4, bytesPerInterval.toUint16(), Endian.little);
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

  /// Parses a SuperSpeedPlus isochronous endpoint companion descriptor from bytes.
  ///
  /// Throws [FormatException] if the descriptor is too short.
  factory USBSSPIsocEndpointDescriptor.parse(List<int> bytes) {
    if (bytes.length < 8) {
      throw FormatException(
        'SSP isoc endpoint companion too short: ${bytes.length}',
      );
    }
    final dwBytesPerInterval =
        bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);

    return USBSSPIsocEndpointDescriptor(
      wReserved: bytes[2] | (bytes[3] << 8),
      bytesPerInterval: ExtendedBytesPerInterval(dwBytesPerInterval),
    );
  }

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
      ..setUint16(2, wReserved, Endian.little)
      ..setUint32(4, bytesPerInterval.toUint32(), Endian.little);
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

  /// Parses an interface association descriptor from bytes.
  ///
  /// Throws [FormatException] if the descriptor is too short.
  factory USBInterfaceAssocDescriptor.parse(List<int> bytes) {
    if (bytes.length < 8) {
      throw FormatException('Interface association too short: ${bytes.length}');
    }
    return USBInterfaceAssocDescriptor(
      firstInterface: InterfaceNumber(bytes[2]),
      interfaceCount: bytes[3],
      functionClass: bytes[4],
      functionSubClass: bytes[5],
      functionProtocol: bytes[6],
      functionString: StringIndex(bytes[7]),
    );
  }

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
  /// [firstInterface + interfaceCount - 1].
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

/// Endpoint template for speed-independent endpoint definitions.
///
/// Provides a high-level endpoint specification that can be converted
/// to speed-specific descriptors. This is useful when you need to define
/// an endpoint once and generate descriptors for multiple USB speeds.
///
/// Use [DescriptorGenerator.generateForSpeed()] to convert this template
/// into actual endpoint descriptors appropriate for a specific USB speed.
class EndpointTemplate implements USBDescriptor {
  /// Creates an endpoint template.
  ///
  /// Parameters:
  /// - [address]: Endpoint address with direction (required)
  /// - [config]: Endpoint configuration (required)
  const EndpointTemplate({required this.address, required this.config});

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
      'EndpointTemplate must be converted to speed-specific descriptor '
      'using DescriptorGenerator.generateForSpeed()',
    );
  }
}

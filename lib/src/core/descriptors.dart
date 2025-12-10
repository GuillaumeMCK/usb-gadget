/// FunctionFS descriptor management for USB Gadget devices.
///
/// This library provides types and builders for working with Linux FunctionFS,
/// which allows userspace USB gadget implementation. It handles:
/// - Descriptor sets for different USB speeds (FS/HS/SS/SSP)
/// - String descriptors with language support
/// - Parsing and serialization of USB descriptors
library;

import 'dart:convert';
import 'dart:typed_data';

import '/usb_gadget.dart';

/// Magic numbers for FunctionFS descriptor headers.
///
/// These identify the format version of the descriptor data written to
/// FunctionFS. Different versions support different features and descriptor
/// layouts.
///
/// The magic number is written as the first 4 bytes when writing descriptors
/// to the FunctionFS ep0 file.
enum FunctionFsMagic {
  /// Original FunctionFS format (v1).
  ///
  /// Basic descriptor support without flags or extended features.
  /// Magic: 0x00000001
  v1(0x00000001),

  /// Strings only format.
  ///
  /// Magic: 0x00000002
  strings(0x00000002),

  /// FunctionFS v2 format with flags.
  ///
  /// Adds support for feature flags and SuperSpeed descriptors.
  /// Magic: 0x00000003
  v2(0x00000003);

  const FunctionFsMagic(this.value);

  /// The raw magic number value.
  final int value;

  /// Creates a magic number from its raw value.
  ///
  /// Returns null if the value doesn't match any known magic number.
  static FunctionFsMagic? fromValue(int value) {
    try {
      return FunctionFsMagic.values.firstWhere((m) => m.value == value);
    } catch (_) {
      return null;
    }
  }
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

/// Flags for FunctionFS v2 descriptor format.
///
/// These flags enable optional features when using FunctionFS v2 magic.
/// Multiple flags can be combined using bitwise OR.
///
/// Example:
/// ```dart
/// final flags = FunctionFsFlags(
///   hasFullSpeed: true,
///   hasHighSpeed: true,
///   hasSuperSpeed: true,
/// );
/// ```
class FunctionFsFlags {
  const FunctionFsFlags({
    this.hasFullSpeed = false,
    this.hasHighSpeed = false,
    this.hasSuperSpeed = false,
    this.hasSuperSpeedPlus = false,
    this.virtualAddressBased = false,
    this.allControlRequests = false,
    this.config0Settings = false,
  });

  factory FunctionFsFlags.fromUint32(int value) => FunctionFsFlags(
    hasFullSpeed: (value & _fullSpeedFlag) != 0,
    hasHighSpeed: (value & _highSpeedFlag) != 0,
    hasSuperSpeed: (value & _superSpeedFlag) != 0,
    hasSuperSpeedPlus: (value & _superSpeedPlusFlag) != 0,
    virtualAddressBased: (value & _virtualAddressFlag) != 0,
    allControlRequests: (value & _allCtrlReqFlag) != 0,
    config0Settings: (value & _config0Flag) != 0,
  );

  // Flag bit masks
  static const int _fullSpeedFlag = 0x00000001;
  static const int _highSpeedFlag = 0x00000002;
  static const int _superSpeedFlag = 0x00000004;
  static const int _superSpeedPlusFlag = 0x00000008;
  static const int _virtualAddressFlag = 0x00000010;
  static const int _allCtrlReqFlag = 0x00000020;
  static const int _config0Flag = 0x00000040;

  /// Full-Speed (12 Mbps) descriptors are present.
  final bool hasFullSpeed;

  /// High-Speed (480 Mbps) descriptors are present.
  final bool hasHighSpeed;

  /// SuperSpeed (5 Gbps) descriptors are present.
  final bool hasSuperSpeed;

  /// SuperSpeedPlus (10+ Gbps) descriptors are present.
  final bool hasSuperSpeedPlus;

  /// Use virtual endpoint addresses.
  ///
  /// When set, endpoint addresses in descriptors are virtual and mapped
  /// to physical endpoints by the kernel. This simplifies descriptor
  /// creation as you can use sequential addresses (0, 1, 2, ...).
  final bool virtualAddressBased;

  /// Deliver all control requests to userspace.
  ///
  /// By default, the kernel handles standard control requests. When set,
  /// all control requests are passed to userspace for handling.
  final bool allControlRequests;

  /// Support configuration 0 (unconfigured state).
  ///
  /// Allows the gadget to operate in configuration 0, which is the
  /// unconfigured state after USB reset before SET_CONFIGURATION.
  final bool config0Settings;

  int toUint32() {
    var value = 0;
    if (hasFullSpeed) value |= _fullSpeedFlag;
    if (hasHighSpeed) value |= _highSpeedFlag;
    if (hasSuperSpeed) value |= _superSpeedFlag;
    if (hasSuperSpeedPlus) value |= _superSpeedPlusFlag;
    if (virtualAddressBased) value |= _virtualAddressFlag;
    if (allControlRequests) value |= _allCtrlReqFlag;
    if (config0Settings) value |= _config0Flag;
    return value;
  }

  @override
  String toString() {
    final features = <String>[];
    if (hasFullSpeed) features.add('FS');
    if (hasHighSpeed) features.add('HS');
    if (hasSuperSpeed) features.add('SS');
    if (hasSuperSpeedPlus) features.add('SSP');
    if (virtualAddressBased) features.add('VirtualAddr');
    if (allControlRequests) features.add('AllCtrlReq');
    if (config0Settings) features.add('Config0');
    return 'FunctionFsFlags(${features.join(', ')})';
  }
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
///
/// Example:
/// ```dart
/// final fsDescriptors = DescriptorSet([
///   USBInterfaceDescriptor(...),
///   USBEndpointDescriptorNoAudio(...),
/// ]);
/// ```
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

/// Builder for FunctionFS descriptor data.
///
/// Constructs the descriptor blob that must be written to FunctionFS ep0
/// before activating the gadget. Handles different USB speeds and feature
/// flags.
///
/// Example:
/// ```dart
/// final descriptors = FunctionFsDescriptorsBuilder()
///   ..fullSpeed = DescriptorSet([...])
///   ..highSpeed = DescriptorSet([...])
///   ..superSpeed = DescriptorSet([...])
///   ..build();
/// ```
class FunctionFsDescriptorsBuilder {
  /// Creates a new descriptor builder with v2 format by default.
  FunctionFsDescriptorsBuilder({this.magic = FunctionFsMagic.v2});

  /// FunctionFS format version (default: v2).
  FunctionFsMagic magic;

  /// Full-Speed descriptors (USB 1.1, 12 Mbps).
  DescriptorSet? fullSpeed;

  /// High-Speed descriptors (USB 2.0, 480 Mbps).
  DescriptorSet? highSpeed;

  /// SuperSpeed descriptors (USB 3.0, 5 Gbps).
  DescriptorSet? superSpeed;

  /// SuperSpeedPlus descriptors (USB 3.1+, 10+ Gbps).
  DescriptorSet? superSpeedPlus;

  /// Optional flags for v2 format.
  ///
  /// If null, flags are automatically determined from descriptor presence.
  FunctionFsFlags? flags;

  /// Builds the FunctionFS descriptor data.
  ///
  /// Returns a [FunctionFsDescriptors] ready to be written to ep0.
  /// Throws [StateError] if no descriptor sets are provided.
  FunctionFsDescriptors build() {
    if (fullSpeed == null &&
        highSpeed == null &&
        superSpeed == null &&
        superSpeedPlus == null) {
      throw StateError('At least one descriptor set must be provided');
    }

    return FunctionFsDescriptors._(
      magic: magic,
      flags:
          flags ??
          FunctionFsFlags(
            hasFullSpeed: fullSpeed != null,
            hasHighSpeed: highSpeed != null,
            hasSuperSpeed: superSpeed != null,
            hasSuperSpeedPlus: superSpeedPlus != null,
          ),
      fullSpeed: fullSpeed,
      highSpeed: highSpeed,
      superSpeed: superSpeed,
      superSpeedPlus: superSpeedPlus,
    );
  }
}

/// FunctionFS descriptor data ready to be written to ep0.
///
/// This represents the complete descriptor blob in the format expected by
/// FunctionFS. The data includes:
/// - Magic number (4 bytes)
/// - Length (4 bytes)
/// - Flags (4 bytes, v2 only)
/// - Full-Speed descriptor count and data
/// - High-Speed descriptor count and data
/// - SuperSpeed descriptor count and data
/// - SuperSpeedPlus descriptor count and data
///
/// Use [FunctionFsDescriptorsBuilder] to construct instances.
class FunctionFsDescriptors {
  const FunctionFsDescriptors._({
    required this.magic,
    required this.flags,
    required this.fullSpeed,
    required this.highSpeed,
    required this.superSpeed,
    required this.superSpeedPlus,
  });

  /// FunctionFS format magic number.
  final FunctionFsMagic magic;

  /// Feature flags (v2 only).
  final FunctionFsFlags flags;

  /// Full-Speed descriptors.
  final DescriptorSet? fullSpeed;

  /// High-Speed descriptors.
  final DescriptorSet? highSpeed;

  /// SuperSpeed descriptors.
  final DescriptorSet? superSpeed;

  /// SuperSpeedPlus descriptors.
  final DescriptorSet? superSpeedPlus;

  /// Serializes to the FunctionFS descriptor format.
  Uint8List toBytes() {
    final buffer = BytesBuilder(copy: false);

    // Calculate total length
    var length = 12; // magic(4) + length(4) + flags(4)

    // Add count fields
    if (flags.hasFullSpeed && fullSpeed != null) length += 4;
    if (flags.hasHighSpeed && highSpeed != null) length += 4;
    if (flags.hasSuperSpeed && superSpeed != null) length += 4;
    if (flags.hasSuperSpeedPlus && superSpeedPlus != null) length += 4;

    // Add descriptor data lengths
    if (flags.hasFullSpeed && fullSpeed != null) {
      length += fullSpeed!.totalLength;
    }
    if (flags.hasHighSpeed && highSpeed != null) {
      length += highSpeed!.totalLength;
    }
    if (flags.hasSuperSpeed && superSpeed != null) {
      length += superSpeed!.totalLength;
    }
    if (flags.hasSuperSpeedPlus && superSpeedPlus != null) {
      length += superSpeedPlus!.totalLength;
    }

    // Write header
    final header = ByteData(12)
      ..setUint32(0, magic.value, Endian.little)
      ..setUint32(4, length, Endian.little)
      ..setUint32(8, flags.toUint32(), Endian.little);
    buffer.add(header.buffer.asUint8List());

    // Write all counts first
    if (flags.hasFullSpeed && fullSpeed != null) {
      final count = ByteData(4)..setUint32(0, fullSpeed!.count, Endian.little);
      buffer.add(count.buffer.asUint8List());
    }
    if (flags.hasHighSpeed && highSpeed != null) {
      final count = ByteData(4)..setUint32(0, highSpeed!.count, Endian.little);
      buffer.add(count.buffer.asUint8List());
    }
    if (flags.hasSuperSpeed && superSpeed != null) {
      final count = ByteData(4)..setUint32(0, superSpeed!.count, Endian.little);
      buffer.add(count.buffer.asUint8List());
    }
    if (flags.hasSuperSpeedPlus && superSpeedPlus != null) {
      final count = ByteData(4)
        ..setUint32(0, superSpeedPlus!.count, Endian.little);
      buffer.add(count.buffer.asUint8List());
    }

    // Then write all descriptor data
    if (flags.hasFullSpeed && fullSpeed != null) {
      buffer.add(fullSpeed!.toBytes());
    }
    if (flags.hasHighSpeed && highSpeed != null) {
      buffer.add(highSpeed!.toBytes());
    }
    if (flags.hasSuperSpeed && superSpeed != null) {
      buffer.add(superSpeed!.toBytes());
    }
    if (flags.hasSuperSpeedPlus && superSpeedPlus != null) {
      buffer.add(superSpeedPlus!.toBytes());
    }

    return buffer.toBytes();
  }

  /// Serializes to legacy FunctionFS v1 format (without flags).
  ///
  /// This is a fallback for older kernels that don't support v2 format.
  Uint8List toLegacyBytes() {
    final buffer = BytesBuilder(copy: false);

    // Count total descriptors
    final int fsCount = fullSpeed?.count ?? 0;
    final int hsCount = highSpeed?.count ?? 0;
    final int ssCount = superSpeed?.count ?? 0;

    // Write counts
    final header = ByteData(12)
      ..setUint32(0, fsCount, Endian.little)
      ..setUint32(4, hsCount, Endian.little)
      ..setUint32(8, ssCount, Endian.little);
    buffer.add(header.buffer.asUint8List());

    // Write descriptor data
    if (fullSpeed != null) buffer.add(fullSpeed!.toBytes());
    if (highSpeed != null) buffer.add(highSpeed!.toBytes());
    if (superSpeed != null) buffer.add(superSpeed!.toBytes());

    return buffer.toBytes();
  }

  @override
  String toString() {
    final sets = <String>[];
    if (fullSpeed != null) sets.add('FS:${fullSpeed!.count}');
    if (highSpeed != null) sets.add('HS:${highSpeed!.count}');
    if (superSpeed != null) sets.add('SS:${superSpeed!.count}');
    if (superSpeedPlus != null) sets.add('SSP:${superSpeedPlus!.count}');
    return 'FunctionFsDescriptors(${magic.name}, ${sets.join(', ')})';
  }
}

/// String descriptors for a specific language.
///
/// USB string descriptors can be localized to different languages. Each
/// language has its own set of strings indexed by string descriptor index.
///
/// String index 0 is reserved for the language ID list and should not be
/// included in the strings array.
///
/// Example:
/// ```dart
/// final enStrings = LanguageStrings(
///   language: USBLanguageId.enUS,
///   strings: [
///     'ACME Corporation',
///     'SuperWidget 3000',
///     'SN123456789',
///   ],
/// );
/// ```
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

  /// Serializes to FunctionFS string format.
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

/// Builder for FunctionFS string data.
///
/// Constructs the string blob that must be written to FunctionFS ep0 after
/// the descriptors. Supports multiple languages.
///
/// Example:
/// ```dart
/// final strings = FunctionFSStringsBuilder()
///   ..addLanguage(LanguageStrings(
///     language: USBLanguageId.enUS,
///     strings: ['ACME Corp', 'Widget'],
///   ))
///   ..build();
/// ```
class FunctionFSStringsBuilder {
  FunctionFSStringsBuilder();

  final List<LanguageStrings> _languages = [];

  void addLanguage(LanguageStrings language) {
    _languages.add(language);
  }

  FunctionFSStrings build() {
    if (_languages.isEmpty) {
      throw StateError('At least one language must be provided');
    }

    // Validate all languages have same string count
    final stringCounts = _languages.map((l) => l.count).toSet();
    if (stringCounts.length > 1) {
      throw ArgumentError(
        'All languages must have the same number of strings. '
        'Found: ${_languages.map((l) => '${l.language.name}:${l.count}').join(', ')}',
      );
    }

    return FunctionFSStrings._(_languages);
  }
}

/// FunctionFS string data ready to be written to ep0.
///
/// This represents the complete string blob in the format expected by
/// FunctionFS. The data includes:
/// - Magic number (0x00000002, same as v2 magic)
/// - Length (4 bytes)
/// - For each language:
///   - Language ID (2 bytes)
///   - String count (1 byte per string, followed by string data)
///
/// Use [FunctionFSStringsBuilder] to construct instances.
class FunctionFSStrings {
  const FunctionFSStrings._(this.languages);

  /// String sets for each supported language.
  final List<LanguageStrings> languages;

  /// Number of supported languages.
  int get languageCount => languages.length;

  /// Serializes to the FunctionFS string format.
  ///
  /// Format (matches Python StringsHead):
  /// - magic (4 bytes): FUNCTIONFS_STRINGS_MAGIC (0x00000002)
  /// - length (4 bytes): total length of structure
  /// - str_count (4 bytes): number of strings per language
  /// - lang_count (4 bytes): number of languages
  /// - For each language:
  ///   - lang_id (2 bytes)
  ///   - NULL-separated, NULL-terminated UTF-8 strings
  ///
  /// Returns a byte array ready to be written to /dev/usb-gadget/<function>/ep0
  /// after writing the descriptors.
  Uint8List toBytes() {
    final buffer = BytesBuilder(copy: false);

    // Collect all language data first to calculate total length
    final languageData = <Uint8List>[];
    for (final lang in languages) {
      languageData.add(lang.toBytes());
    }

    final strCount = languages.isNotEmpty ? languages.first.count : 0;

    // Calculate total length
    var length = 16; // magic(4) + length(4) + str_count(4) + lang_count(4)
    for (final data in languageData) {
      length += data.length;
    }

    // Write header
    final header = ByteData(16)
      ..setUint32(0, FunctionFsMagic.strings.value, Endian.little)
      ..setUint32(4, length, Endian.little)
      ..setUint32(8, strCount, Endian.little)
      ..setUint32(12, languageCount, Endian.little);
    buffer.add(header.buffer.asUint8List());

    // Write language data
    languageData.forEach(buffer.add);

    return buffer.toBytes();
  }

  @override
  String toString() {
    final langs = languages.map((l) => l.language.name).join(', ');
    return 'FunctionFSStrings($languageCount languages: $langs)';
  }
}

/// Descriptor generator for creating speed-specific descriptors.
///
/// Generates Full-Speed, High-Speed, SuperSpeed, and SuperSpeedPlus
/// descriptor sets from a shared base template. Handles endpoint
/// descriptor transformations based on USB speed requirements.
///
/// Example:
/// ```dart
/// final descriptors = [
///   USBInterfaceDescriptor(...),
///   EndpointTemplate(
///     address: EndpointAddress.in_(EndpointNumber.ep1),
///     config: EndpointConfig.bulk(),
///   ),
/// ];
///
/// final fs = DescriptorGenerator.generateForSpeed(
///   descriptors,
///   USBSpeed.fullSpeed,
/// );
/// ```
abstract class DescriptorGenerator {
  /// Generates a descriptor set for a specific USB speed.
  ///
  /// Takes a list of base descriptors and produces speed-specific variants:
  /// - Interface descriptors are copied as-is
  /// - EndpointTemplate descriptors are converted to USBEndpointDescriptorNoAudio
  ///   with speed-appropriate packet sizes and intervals
  /// - SuperSpeed endpoints include companion descriptors
  ///
  /// Returns a DescriptorSet ready for use with FunctionFS.
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

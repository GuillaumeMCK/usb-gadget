import 'dart:typed_data';

import '/usb_gadget.dart';

/// USB HID Descriptor.
///
/// The HID descriptor provides information about the HID device and references
/// to additional HID-specific descriptors (report descriptor, physical descriptor).
/// It immediately follows the interface descriptor in the configuration.
///
/// The HID descriptor includes:
/// - HID specification version
/// - Country code (for localization)
/// - Number and types of subordinate descriptors
/// - Lengths of subordinate descriptors
class USBHIDDescriptor implements USBDescriptor {
  /// Creates a HID descriptor.
  ///
  /// Parameters:
  /// - [hidVersion]: HID specification version in BCD (default: 0x0111 for HID 1.11)
  /// - [countryCode]: Hardware target country code (default: 0, not localized)
  /// - [reportDescriptorLength]: Length of report descriptor in bytes (required)
  /// - [physicalDescriptorLength]: Length of physical descriptor (default: 0, not used)
  const USBHIDDescriptor({
    this.hidVersion = 0x0111,
    this.countryCode = 0x00,
    required this.reportDescriptorLength,
    this.physicalDescriptorLength = 0,
  }) : assert(
         reportDescriptorLength > 0,
         'Report descriptor length must be greater than 0',
       );

  @override
  int get bLength => physicalDescriptorLength > 0 ? 12 : 9;

  @override
  int get bDescriptorType => HIDDescriptorType.hid.value;

  /// HID specification release number in BCD.
  ///
  /// Common values:
  /// - 0x0100: HID 1.0
  /// - 0x0110: HID 1.1
  /// - 0x0111: HID 1.11 (most common)
  ///
  /// Format: 0xJJMN where JJ = major version, M = minor, N = sub-minor
  final int hidVersion;

  /// Country code for hardware localization.
  ///
  /// Values:
  /// - 0x00: Not supported (most common)
  /// - 0x01-0x23: Various country codes (rarely used)
  ///
  /// Most devices use 0 as keyboard layouts are handled by the OS.
  final int countryCode;

  /// Length of the report descriptor in bytes.
  ///
  /// The report descriptor defines all inputs, outputs, and features
  /// of the HID device. This field tells the host how many bytes to
  /// request when fetching the report descriptor.
  final int reportDescriptorLength;

  /// Length of the physical descriptor in bytes.
  ///
  /// Optional descriptor describing physical characteristics. Most devices
  /// set this to 0 (no physical descriptor).
  final int physicalDescriptorLength;

  /// Number of subordinate descriptors.
  ///
  /// Always at least 1 (for the report descriptor). Incremented if a
  /// physical descriptor is present.
  int get numDescriptors => physicalDescriptorLength > 0 ? 2 : 1;

  /// BCD version major number.
  int get majorVersion => (hidVersion >> 8) & 0xFF;

  /// BCD version minor number.
  int get minorVersion => hidVersion & 0xFF;

  @override
  Uint8List toBytes() {
    final bytes = ByteData(bLength)
      ..setUint8(0, bLength)
      ..setUint8(1, bDescriptorType)
      ..setUint16(2, hidVersion, Endian.little)
      ..setUint8(4, countryCode)
      ..setUint8(5, numDescriptors)
      // First subordinate descriptor (report descriptor)
      ..setUint8(6, HIDDescriptorType.report.value)
      ..setUint16(7, reportDescriptorLength, Endian.little);
    if (physicalDescriptorLength > 0) {
      // Second subordinate descriptor (physical descriptor)
      bytes
        ..setUint8(9, HIDDescriptorType.physical.value)
        ..setUint16(10, physicalDescriptorLength, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  @override
  String toString() =>
      'USBHIDDescriptor(HID $majorVersion.$minorVersion, '
      'reportLen=$reportDescriptorLength)';
}

import 'dart:io';

import '/usb_gadget.dart';

/// USB Device Controller (UDC).
///
/// Represents a USB device controller available on the system. UDCs are
/// discovered by scanning `/sys/class/udc/` and their properties are read
/// from sysfs attribute files.
///
/// Example:
/// ```dart
/// final udcs = await queryUdcs();
/// for (final udc in udcs) {
///   print('UDC: ${udc.name}');
///   print('Max speed: ${udc.maxSpeed}');
///   print('Current speed: ${udc.currentSpeed}');
///   print('State: ${udc.state}');
/// }
/// ```
class Udc {
  Udc._(this._directory);

  /// The sysfs directory path for this UDC.
  final Directory _directory;

  /// The name of the USB device controller.
  String get name => _directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

  /// Indicates if an OTG A-Host supports HNP at an alternate port.
  Future<bool> get aAltHnpSupport async {
    final content = await _readAttribute('a_alt_hnp_support');
    return content.trim() != '0';
  }

  /// Indicates if an OTG A-Host supports HNP at this port.
  Future<bool> get aHnpSupport async {
    final content = await _readAttribute('a_hnp_support');
    return content.trim() != '0';
  }

  /// Indicates if an OTG A-Host enabled HNP support.
  Future<bool> get bHnpEnable async {
    final content = await _readAttribute('b_hnp_enable');
    return content.trim() != '0';
  }

  /// Indicates the current negotiated speed at this port.
  Future<Speed> get currentSpeed async {
    final content = await _readAttribute('current_speed');
    return Speed.fromString(content.trim());
  }

  /// Indicates the maximum USB speed supported by this port.
  Future<Speed> get maxSpeed async {
    final content = await _readAttribute('maximum_speed');
    return Speed.fromString(content.trim());
  }

  /// Indicates that this port is the default Host on an OTG session but HNP
  /// was used to switch roles.
  Future<bool> get isAPeripheral async {
    final content = await _readAttribute('is_a_peripheral');
    return content.trim() != '0';
  }

  /// Indicates that this port supports OTG.
  Future<bool> get isOtg async {
    final content = await _readAttribute('is_otg');
    return content.trim() != '0';
  }

  /// Indicates current state of the USB Device Controller.
  ///
  /// However not all USB Device Controllers support reporting all states.
  Future<USBDeviceState> get state async {
    final content = await _readAttribute('state');
    return USBDeviceState.fromString(content.trim());
  }

  /// Name of currently running USB Gadget Driver.
  ///
  /// Returns null if no gadget is bound.
  Future<String?> get function async {
    final content = await _readAttribute('function');
    final trimmed = _trimString(content);
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Manually start Session Request Protocol (SRP).
  Future<void> startSrp() async {
    await _writeAttribute('srp', '1');
  }

  /// Connect or disconnect data pull-up resistors thus causing a logical
  /// connection to or disconnection from the USB host.
  Future<void> setSoftConnect(bool connect) async {
    await _writeAttribute('soft_connect', connect ? 'connect' : 'disconnect');
  }

  /// Reads a sysfs attribute file for this UDC.
  Future<String> _readAttribute(String name) async {
    final file = File('${_directory.path}/$name');
    return await file.readAsString();
  }

  /// Writes to a sysfs attribute file for this UDC.
  Future<void> _writeAttribute(String name, String value) async {
    final file = File('${_directory.path}/$name');
    await file.writeAsString(value);
  }

  @override
  String toString() => 'Udc(name: $name)';
}

/// Gets the available USB device controllers (UDCs) in the system.
///
/// Scans `/sys/class/udc/` and returns a list of all available UDCs.
/// Returns an empty list if no UDCs are found or sysfs is not available.
///
/// Example:
/// ```dart
/// final udcs = queryUdcs();
/// if (udcs.isEmpty) {
///   print('No UDCs available');
/// }
/// ```
List<Udc> queryUdcs() {
  const classDir = '/sys/class';
  if (!Directory(classDir).existsSync()) {
    return [];
  }

  const udcDir = '$classDir/udc';
  final dir = Directory(udcDir);
  if (!dir.existsSync()) {
    return [];
  }

  final udcs = <Udc>[];
  for (final entry in dir.listSync()) {
    if (entry is Directory) {
      udcs.add(Udc._(entry));
    }
  }

  return udcs;
}

/// The default USB device controller (UDC) in the system by alphabetical sorting.
///
/// Returns null if no UDC is present.
///
/// Example:
/// ```dart
/// final udc = getDefaultUdc();
/// if (udc != null) {
///   print('Using UDC: ${udc.name}');
/// }
/// ```
Udc? getDefaultUdc() {
  final udcs = queryUdcs();
  if (udcs.isEmpty) {
    return null;
  }

  udcs.sort((a, b) => a.name.compareTo(b.name));
  return udcs.first;
}

/// Trims whitespace, newlines, and null bytes from a string.
///
/// Files in sysfs/configfs often have trailing newlines or null bytes.
String _trimString(String value) {
  var result = value;

  // Trim from start
  while (result.isNotEmpty &&
      (result[0] == '\n' || result[0] == ' ' || result[0] == '\x00')) {
    result = result.substring(1);
  }

  // Trim from end
  while (result.isNotEmpty &&
      (result[result.length - 1] == '\n' ||
          result[result.length - 1] == ' ' ||
          result[result.length - 1] == '\x00')) {
    result = result.substring(0, result.length - 1);
  }

  return result;
}

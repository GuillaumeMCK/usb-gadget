import '/usb_gadget.dart';

/// A USB Vendor ID and Product ID pair.
///
/// Official VIDs are assigned by the USB Implementers Forum (USB-IF).
/// Use vendor `0x1234` for testing.
class Id {
  const Id(this.vendor, this.product);

  /// USB Vendor ID (VID).
  final int vendor;

  /// USB Product ID (PID).
  final int product;
}

/// USB device or interface class code, grouping class, subclass, and protocol.
///
/// Most composite devices use [Class.interfaceSpecific], which defers class
/// information to each interface descriptor.
///
/// ```dart
/// final cls = Class.interfaceSpecific();
/// final cls = Class.vendorSpecific(0x00, 0x00);
/// ```
class Class {
  const Class(this.classCode, this.subClass, this.protocol);

  /// Defers class information to each interface descriptor.
  ///
  /// Can only be used as a device class, not an interface class.
  const Class.interfaceSpecific() : this(0, 0, 0);

  /// Creates a vendor-specific class (code `0xFF`) with the given [subClass] and [protocol].
  const Class.vendorSpecific(int subClass, int protocol)
    : this(0xFF, subClass, protocol);

  /// USB class code.
  final int classCode;

  /// USB subclass code.
  final int subClass;

  /// USB protocol code.
  final int protocol;
}

/// Handles USB bMaxPower values for gadget configurations.
///
/// bMaxPower specifies the maximum power consumption of the device from the
/// USB bus.
final class MaxPower {
  /// Creates a MaxPower value from a raw USB bMaxPower value
  const MaxPower(this.milliAmps) : assert(milliAmps >= 0 && milliAmps <= 510);

  final int milliAmps;

  int get value => milliAmps ~/ 2;

  @override
  String toString() => 'MaxPower(value=$value, mA=$milliAmps)';
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// USB gadget configuration containing functions and attributes.
///
/// A configuration is a set of functions the USB host can select.
/// Most gadgets have a single configuration.
///
/// Example:
/// ```dart
/// final config = Config(
///   'My config',
///   functions: [myFunction],
///   maxPower: 500,
///   selfPowered: false,
/// );
/// ```
class Config {
  /// Creates a gadget configuration.
  ///
  /// Parameters:
  /// - [description]: Human-readable configuration name (written per language)
  /// - [functions]: Functions (interfaces) in this configuration
  /// - [maxPower]: Maximum bus power in milliamps (default: 500)
  /// - [selfPowered]: Whether the device has an external power source
  /// - [remoteWakeup]: Whether the device supports remote wakeup
  /// - [strings]: Per-language overrides for the configuration description
  /// - [index]: Configuration number (1-based)
  Config(
    this.description, {
    this.functions = const [],
    this.maxPower = const MaxPower(500),
    this.selfPowered = false,
    this.remoteWakeup = false,
    this.strings = const {},
    this.index = 1,
  }) : assert(index > 0, 'Configuration index must be positive');

  /// Default description string (written for the default language).
  final String description;

  /// Functions (USB interfaces) in this configuration.
  final List<GadgetFunction> functions;

  /// Maximum power consumption from the USB bus, in milliamps.
  ///
  /// Written as `MaxPower` in configfs. Max 500 mA for USB 2.0.
  final MaxPower maxPower;

  /// Whether the device has an external power source.
  final bool selfPowered;

  /// Whether the device supports remote wakeup.
  final bool remoteWakeup;

  /// Per-language configuration description overrides.
  final Map<USBLanguageId, String> strings;

  /// Configuration index (1-based).
  final int index;

  int get bmAttributes {
    var v = 1 << 7;
    if (selfPowered) v |= 1 << 6;
    if (remoteWakeup) v |= 1 << 5;
    return v;
  }
}

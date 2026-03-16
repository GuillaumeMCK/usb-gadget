import '/usb_gadget.dart';
export '/src/usb/usb.dart' show UsbVersion;

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
final class Config {
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
  Config({
    this.description = '',
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

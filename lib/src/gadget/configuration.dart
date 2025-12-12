import '/usb_gadget.dart';

/// A gadget configuration containing functions and attributes.
///
/// A configuration is a set of functions that can be selected by the USB host.
/// Most gadgets have a single configuration (index 1), but multiple
/// configurations allow the host to choose between different sets of functions.
final class GadgetConfiguration {
  /// Creates a gadget configuration.
  ///
  /// Parameters:
  /// - [functions]: List of functions in this configuration
  /// - [attributes]: Power and wakeup attributes
  /// - [maxPower]: Maximum power consumption
  /// - [strings]: Configuration name per language
  /// - [index]: Configuration number (1-based, must be positive)
  const GadgetConfiguration({
    required this.functions,
    this.attributes,
    this.maxPower,
    this.strings = const {},
    this.index = 1,
  }) : assert(index > 0, 'Configuration index must be positive');

  /// Functions available in this configuration.
  final List<GadgetFunction> functions;

  /// Power attributes (bus-powered, self-powered, remote wakeup).
  final GadgetAttributes? attributes;

  /// Maximum power consumption from the USB bus.
  final GadgetMaxPower? maxPower;

  /// Configuration name strings per language.
  final Map<USBLanguageId, String> strings;

  /// Configuration index (1-based).
  ///
  /// Multiple configurations allow the host to choose between different
  /// function sets. Most devices use a single configuration (index 1).
  final int index;
}

/// Type of gadget function.
///
/// - **FFS (FunctionFs)**: Userspace-implemented functions that require
///   descriptor setup and endpoint handling in userspace (e.g., ADB, MTP).
/// - **Kernel**: Kernel-implemented functions that only require configuration
///   attributes (e.g., mass storage, serial port).
enum GadgetFunctionType { ffs, kernel }

/// USB configuration attributes (bmAttributes field).
///
/// Specifies power source and wakeup capability of the device.
enum GadgetAttributes {
  /// Device is powered from the USB bus only (default).
  ///
  /// Maximum power draw is limited by bMaxPower (typically 500 mA for USB 2.0).
  busPowered(0x80),

  /// Device has an external power source.
  ///
  /// Can draw more power than USB provides. The device may or may not also
  /// draw power from the bus.
  selfPowered(0xC0),

  /// Device supports remote wakeup.
  ///
  /// Can signal the host to exit suspend mode. Requires host approval.
  remoteWakeup(0xA0);

  const GadgetAttributes(this.value);

  /// Raw bmAttributes byte value.
  final int value;
}

/// Handles USB bMaxPower values for gadget configurations.
///
/// bMaxPower specifies the maximum power consumption of the device from the
/// USB bus. The value is stored in USB units (2 mA per unit) in the range 0-255.
final class GadgetMaxPower {
  /// Creates a MaxPower value from a raw USB bMaxPower value (0-255).
  ///
  /// The raw value represents units of 2 mA each. For example:
  /// - 0 = 0 mA
  /// - 50 = 100 mA
  /// - 250 = 500 mA
  ///
  /// Most users should prefer [fromMilliAmps] for clarity.
  ///
  /// Throws [ArgumentError] if value is outside the 0-255 range.
  GadgetMaxPower(this.value) {
    if (value < 0 || value > 0xFF) {
      throw ArgumentError(
        'Raw USB bMaxPower value must be in 0–255 range (was $value).',
      );
    }
  }

  /// Creates a MaxPower value from milliamps.
  ///
  /// The USB spec uses 2 mA units, so values are rounded down if not aligned.
  /// For example:
  /// - 100 mA → value 50
  /// - 101 mA → value 50 (rounded down)
  /// - 500 mA → value 250
  ///
  /// Maximum supported value is 510 mA (255 * 2 mA).
  ///
  /// Throws:
  /// - [ArgumentError] if mA is negative
  /// - [ArgumentError] if mA exceeds 510 (USB limit)
  factory GadgetMaxPower.fromMilliAmps(int mA) {
    if (mA < 0) {
      throw ArgumentError('Milliamp value must be >= 0 (was $mA).');
    }

    final value = mA ~/ _unitMilliAmps; // integer division (truncate)

    if (value > 0xFF) {
      throw ArgumentError(
        'Requested $mA mA exceeds USB limit (${0xFF * _unitMilliAmps} mA).',
      );
    }

    return GadgetMaxPower(value);
  }

  /// Raw USB bMaxPower value (0–255).
  ///
  /// This is the value written to the USB configuration descriptor.
  /// Each unit represents 2 mA of power consumption.
  final int value;

  /// USB 2.x power unit in milliamps.
  ///
  /// The USB specification defines power in units of 2 mA for USB 2.0 and
  /// earlier. USB 3.0 uses 8 mA units, but this library currently only
  /// supports USB 2.0 power units.
  static const int _unitMilliAmps = 2;

  /// Converts the raw USB value to milliamps.
  ///
  /// Returns the actual power consumption represented by this bMaxPower value.
  int toMilliAmps() => value * _unitMilliAmps;

  /// Returns a human-readable representation of the power value.
  ///
  /// Shows both the raw USB value and the milliamp equivalent.
  @override
  String toString() => 'GadgetMaxPower(value=$value, mA=${toMilliAmps()})';
}

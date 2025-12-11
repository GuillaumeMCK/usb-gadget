/// String descriptors for a gadget.
///
/// Provides human-readable information about the device in various languages.
/// All fields are optional; the USB spec only requires the serial number for
/// certain device classes.
class GadgetStrings {
  /// Creates string descriptors with optional values.
  const GadgetStrings({this.serialnumber, this.manufacturer, this.product});

  /// Serial number string (e.g., "123456789ABC").
  ///
  /// Should be unique per device. Required for mass storage devices.
  final String? serialnumber;

  /// Manufacturer string (e.g., "ACME Corporation").
  final String? manufacturer;

  /// Product string (e.g., "Rocket Sled 3000").
  final String? product;
}

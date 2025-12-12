/// HID subclass codes (bInterfaceSubClass).
///
/// Subclass codes identify specific types of HID devices. Most HID devices
/// use the "no subclass" value and rely on the report descriptor to define
/// their functionality. The boot interface subclass is used for BIOS-level
/// support before the full HID driver loads.
enum HIDSubclass {
  /// No subclass (0x00).
  ///
  /// Most HID devices use this. The report descriptor fully defines the device.
  none(0x00),

  /// Boot interface subclass (0x01).
  ///
  /// Indicates a device that implements a simplified "boot protocol" for
  /// BIOS compatibility. Used by keyboards and mice to function before the
  /// OS HID driver loads. Boot devices can also support a full report protocol.
  boot(0x01);

  const HIDSubclass(this.value);

  /// Raw subclass code value.
  final int value;

  /// Creates a subclass from its raw value.
  static HIDSubclass fromValue(int value) {
    return HIDSubclass.values.firstWhere(
      (s) => s.value == value,
      orElse: () => none,
    );
  }
}

/// HID protocol codes (bInterfaceProtocol).
///
/// Protocol codes identify specific device types within the boot interface
/// subclass. These are only meaningful when using HIDSubclass.boot.
enum HIDProtocol {
  /// No protocol or non-boot device (0x00).
  ///
  /// Used by all non-boot HID devices and as the default.
  none(0x00),

  /// Keyboard protocol (0x01).
  ///
  /// Boot interface keyboard. Sends 8-byte reports with modifier keys
  /// and up to 6 simultaneous key presses.
  keyboard(0x01),

  /// Mouse protocol (0x02).
  ///
  /// Boot interface mouse. Sends reports with button states and
  /// relative X/Y movement.
  mouse(0x02);

  const HIDProtocol(this.value);

  /// Raw protocol code value.
  final int value;

  /// Creates a protocol from its raw value.
  static HIDProtocol fromValue(int value) {
    return HIDProtocol.values.firstWhere(
      (p) => p.value == value,
      orElse: () => none,
    );
  }
}

/// HID class-specific request codes (bRequest).
///
/// These request codes are used in control transfers to configure and
/// control HID devices. They extend the standard USB requests with
/// HID-specific operations.
enum HIDRequest {
  /// GET_REPORT (0x01).
  ///
  /// Retrieves a report from the device. Used to read the current state
  /// of input reports, get feature reports, or read output reports.
  ///
  /// Direction: Device-to-Host
  /// wValue: Report Type (high byte) and Report ID (low byte)
  /// wIndex: Interface number
  /// wLength: Report length
  getReport(0x01),

  /// GET_IDLE (0x02).
  ///
  /// Retrieves the current idle rate for an input report. The idle rate
  /// determines how often the device sends reports when data hasn't changed.
  ///
  /// Direction: Device-to-Host
  /// wValue: Report ID (low byte), 0 (high byte)
  /// wIndex: Interface number
  /// wLength: 1
  getIdle(0x02),

  /// GET_PROTOCOL (0x03).
  ///
  /// Retrieves the current protocol (boot or report). Only used by boot
  /// interface devices.
  ///
  /// Direction: Device-to-Host
  /// wValue: 0
  /// wIndex: Interface number
  /// wLength: 1
  /// Returns: 0 = boot protocol, 1 = report protocol
  getProtocol(0x03),

  /// SET_REPORT (0x09).
  ///
  /// Sends a report to the device. Used to send output reports (like LED
  /// states for keyboards) or configure feature reports.
  ///
  /// Direction: Host-to-Device
  /// wValue: Report Type (high byte) and Report ID (low byte)
  /// wIndex: Interface number
  /// wLength: Report length
  setReport(0x09),

  /// SET_IDLE (0x0A).
  ///
  /// Sets the idle rate for an input report. Value is in 4ms units,
  /// where 0 means infinite (only report on change).
  ///
  /// Direction: Host-to-Device
  /// wValue: Duration (high byte), Report ID (low byte)
  /// wIndex: Interface number
  /// wLength: 0
  setIdle(0x0A),

  /// SET_PROTOCOL (0x0B).
  ///
  /// Switches between boot and report protocol. Only used by boot
  /// interface devices.
  ///
  /// Direction: Host-to-Device
  /// wValue: 0 = boot protocol, 1 = report protocol
  /// wIndex: Interface number
  /// wLength: 0
  setProtocol(0x0B);

  const HIDRequest(this.value);

  /// Raw request code value.
  final int value;

  /// Creates a request from its raw value.
  static HIDRequest? fromValue(int value) {
    try {
      return HIDRequest.values.firstWhere((r) => r.value == value);
    } catch (_) {
      return null;
    }
  }
}

/// HID descriptor type codes (bDescriptorType).
///
/// These type codes identify different kinds of HID-specific descriptors.
/// They are used in addition to the standard USB descriptor types.
enum HIDDescriptorType {
  /// HID descriptor (0x21).
  ///
  /// The main HID descriptor that follows the interface descriptor.
  /// Contains HID version, country code, and references to other
  /// HID descriptors (report, physical).
  hid(0x21),

  /// Report descriptor (0x22).
  ///
  /// Defines the format and meaning of data exchanged with the device.
  /// This is the most important HID descriptor as it describes all
  /// inputs, outputs, and features of the device.
  report(0x22),

  /// Physical descriptor (0x23).
  ///
  /// Optional descriptor that describes the physical characteristics
  /// of the device (like button locations). Rarely used in practice.
  physical(0x23);

  const HIDDescriptorType(this.value);

  /// Raw descriptor type value.
  final int value;

  /// Creates a descriptor type from its raw value.
  static HIDDescriptorType fromValue(
    int value, {
    HIDDescriptorType orElse = HIDDescriptorType.hid,
  }) {
    try {
      return HIDDescriptorType.values.firstWhere((t) => t.value == value);
    } catch (_) {
      return orElse;
    }
  }
}

/// HID report types.
enum HIDReportType {
  /// Input report (1).
  input(1),

  /// Output report (2).
  output(2),

  /// Feature report (3).
  feature(3);

  const HIDReportType(this.value);

  final int value;

  static HIDReportType? fromValue(int value) {
    try {
      return HIDReportType.values.firstWhere((t) => t.value == value);
    } catch (_) {
      return null;
    }
  }
}

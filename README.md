# usb-gadget

> [!IMPORTANT]
> This library is experimental and not suitable for production use. Breaking changes may occur without warning.

> [!CAUTION]
> Misconfigured USB gadgets can destabilize your system or prevent booting. Always test on non-essential devices with
> physical recovery access available.

A comprehensive Dart library for creating USB gadgets on Linux using ConfigFS and FunctionFS. Transform your Linux
device into a USB peripheral—implement keyboards, mice, storage devices, network interfaces, or create entirely custom
USB protocols in pure Dart.

[![pub package](https://img.shields.io/pub/v/usb_gadget.svg)](https://pub.dev/packages/usb_gadget)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Features

### Kernel-Based Functions

Pre-configured USB functions implemented by kernel drivers, ready to use with minimal setup:

#### **Network Interfaces**

- **CDC ECM** - Ethernet over USB (widely supported)
- **CDC ECM Subset** - Simplified ECM for legacy hosts
- **CDC EEM** - Ethernet Emulation Model (lowest overhead)
- **CDC NCM** - Network Control Model (high performance)
- **RNDIS** - Remote NDIS (Windows compatibility)

#### **Serial Ports**

- **CDC ACM** - Abstract Control Model (standard virtual serial)
- **Generic Serial** - Non-CDC serial implementation

#### **Human Interface Devices**

- **HID** - Keyboards, mice, gamepads, and custom HID devices

#### **Storage & Media**

- **Mass Storage Device (MSD)** - USB flash drive emulation
- **Printer** - USB printer class device

#### **Audio & Video**

- **MIDI** - Musical Instrument Digital Interface
- **UAC1** - USB Audio Class 1.0
- **UAC2** - USB Audio Class 2.0
- **UVC** - USB Video Class (webcam emulation)

#### **Testing & Development**

- **Loopback** - Data loopback for testing
- **SourceSink** - Pattern generation and validation

### FunctionFS (Custom USB Functions)

FunctionFS provides complete control over USB functionality in userspace, enabling you to:

- **Define custom USB descriptors** - Create devices with any interface, endpoint configuration, or capability
- **Handle USB endpoints directly** - Full control over data transfer, timing, and flow control
- **Implement custom protocols** - Build proprietary or specialized USB communication protocols
- **Process control requests** - Handle vendor-specific, class-specific, or standard USB requests
- **React to USB events** - Respond to bind, unbind, enable, disable, suspend, and resume events

**Ideal for:**

- Complex HID devices with custom report descriptors
- Proprietary USB protocols and interfaces
- USB device prototyping and experimentation
- Devices requiring precise timing or advanced USB features
- Applications needing complete protocol control

The library includes `HIDFunctionFs` as a specialized FunctionFS implementation with built-in HID protocol handling,
making custom HID devices straightforward to implement.

## Requirements

### Platform Support

- **Operating System**: Linux with USB Device Controller (UDC) support
- **Architecture**: ARM, ARM64, x86_64 (any architecture with Linux UDC support)
- **Dart SDK**: 3.10.0 or higher

### Hardware Requirements

A Linux device with a USB Device Controller (UDC) is required. Standard desktop PCs typically do **not** include a
UDC—they only have USB host controllers.

**Compatible devices include:**

- Raspberry Pi 4, Pi Zero (USB-C or micro-USB port)
- Raspberry Pi 5 (USB-C port)
- Orange Pi, Banana Pi (model-dependent)
- BeagleBone Black, BeagleBone AI
- Most embedded Linux boards with USB OTG capability

**To check if your device has a UDC:**

```bash
ls /sys/class/udc/
# Should list one or more UDC devices (e.g., fe980000.usb)
```

### System Dependencies

Install the Linux Asynchronous I/O library:

**Debian/Ubuntu:**

```bash
sudo apt-get install libaio-dev
```

**Arch Linux:**

```bash
sudo pacman -S libaio
```

**Fedora/RHEL:**

```bash
sudo dnf install libaio-devel
```

### Linux Kernel Configuration

The following kernel options must be enabled. Most modern embedded Linux distributions include these by default.

<details>
<summary>Required Kernel Configuration Options</summary>

**Core USB Gadget Support:**

- `CONFIG_USB_GADGET` - USB Gadget framework
- `CONFIG_USB_CONFIGFS` - ConfigFS-based gadget configuration
- `CONFIG_USB_FUNCTIONFS` - FunctionFS support

**Kernel Function Drivers:**

- `CONFIG_USB_CONFIGFS_SERIAL` - Serial functions
- `CONFIG_USB_CONFIGFS_ACM` - CDC ACM serial
- `CONFIG_USB_CONFIGFS_NCM` - CDC NCM ethernet
- `CONFIG_USB_CONFIGFS_ECM` - CDC ECM ethernet
- `CONFIG_USB_CONFIGFS_ECM_SUBSET` - ECM Subset ethernet
- `CONFIG_USB_CONFIGFS_RNDIS` - RNDIS ethernet
- `CONFIG_USB_CONFIGFS_EEM` - CDC EEM ethernet
- `CONFIG_USB_CONFIGFS_MASS_STORAGE` - Mass storage
- `CONFIG_USB_CONFIGFS_F_HID` - HID functions
- `CONFIG_USB_CONFIGFS_F_PRINTER` - Printer function
- `CONFIG_USB_CONFIGFS_F_MIDI` - MIDI function
- `CONFIG_USB_CONFIGFS_F_UAC1` - Audio Class 1.0
- `CONFIG_USB_CONFIGFS_F_UAC2` - Audio Class 2.0
- `CONFIG_USB_CONFIGFS_F_UVC` - Video Class

**Check your kernel configuration:**

```bash
zcat /proc/config.gz | grep -E 'CONFIG_USB_(GADGET|CONFIGFS|FUNCTIONFS)'
# or
grep -E 'CONFIG_USB_(GADGET|CONFIGFS|FUNCTIONFS)' /boot/config-$(uname -r)
```

</details>

### Permissions

Root privileges or the `CAP_SYS_ADMIN` capability are required to configure USB gadgets.

**Verify ConfigFS is mounted:**

```bash
mount | grep configfs
# Should show: configfs on /sys/kernel/config type configfs (rw,relatime)
```

**Mount ConfigFS if needed:**

```bash
sudo mount -t configfs none /sys/kernel/config
```

**Running without full root (using capabilities):**

```bash
# Grant CAP_SYS_ADMIN to your Dart executable
sudo setcap cap_sys_admin+ep /path/to/your/dart/executable
```

## Installation & Usage

### Add the Package

```bash
dart pub add usb_gadget
```

### Basic Example: USB Keyboard

This example creates a USB HID keyboard that types "hello world" when connected:

```dart

final _descriptor = Uint8List.fromList([ /* ... */]);

class Keyboard extends HIDFunction {
  Keyboard()
      : super(
    name: 'keyboard',
    descriptor: _descriptor,
    protocol: HIDProtocol.keyboard,
    subclass: HIDSubclass.boot,
    reportLength: 8,
  );

  void sendKey(int keyCode, {int modifiers = 0}) {
    // Press key
    file.writeFromSync(
      Uint8List(8)
        ..[0] = modifiers
        ..[2] = keyCode,
    );
    // Release key
    file.writeFromSync(Uint8List(8));
  }
}

Future<void> main() async {
  final keyboard = Keyboard();
  final gadget = Gadget(
    name: 'hid_keyboard',
    idVendor: 0x1234,
    idProduct: 0x5679,
    deviceClass: USBClass.composite,
    deviceSubClass: USBSubClass.none,
    deviceProtocol: USBProtocol.none,
    strings: {
      Language.enUS: const GadgetStrings(
        manufacturer: 'ACME Corp',
        product: 'USB Keyboard',
        serialnumber: 'KB001',
      ),
    },
    config: Config(functions: [keyboard]),
  );
  try {
    await gadget.bind();
    await gadget.waitForState(.configured);
    // An additional delay here prevents the first few keypresses from
    // being missed on some hosts.
    await Future.delayed(const .new(milliseconds: 100));
    [0x0B, 0x08, 0x0F, 0x0F, 0x12, 0x2C, 0x1A, 0x12, 0x15, 0x0F, 0x07, 0x28]
    // Write "hello world\n" keycodes
    .forEach(keyboard.sendKey);
    stdout.writeln('Keyboard ready. Press Ctrl+C to exit.');
    await ProcessSignal.sigint.watch().first;
  } finally {
    await gadget.unbind();
  }
}
```

### Running Your Gadget

**Standard execution (requires root):**

```bash
sudo dart run bin/your_app.dart
```

**Compiled executable:**

```bash
dart compile exe bin/your_app.dart -o keyboard
sudo ./keyboard
```

**With debug logging:**

```bash
dart compile exe -DUSB_GADGET_DEBUG=true bin/your_app.dart -o keyboard
sudo ./keyboard
```

### More Examples

The [examples](example/) directory contains ready-to-run implementations:

## Resources

- **[API Documentation](https://pub.dev/documentation/usb_gadget/latest/)** - Complete API reference
- **[Linux USB Gadget API](https://www.kernel.org/doc/html/latest/usb/gadget.html)** - Kernel documentation
- **[HID Usage Tables](https://usb.org/sites/default/files/hut1_3_0.pdf)** - HID keyboard/mouse codes
- **[usb-gadget (Rust)](https://github.com/surban/usb-gadget)** - Inspiration and reference implementation

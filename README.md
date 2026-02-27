# usb-gadget

> [!IMPORTANT]
> This library is experimental and not suitable for production use. Breaking changes may occur without warning.

A Dart library for creating USB gadgets on Linux using ConfigFS and FunctionFS. Transform your Linux device into a USB
peripheral — implement keyboards, mice, storage devices, network interfaces, or create entirely custom USB protocols in
pure Dart.

[![pub package](https://img.shields.io/pub/v/usb_gadget.svg)](https://pub.dev/packages/usb_gadget)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation & Usage](#installation--usage)
- [Android Support](#android-support)
- [Resources](#resources)

---

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

### FunctionFS — Custom USB Functions

FunctionFS gives you complete control over USB functionality in userspace. Use it to define custom USB descriptors,
handle endpoints directly, implement proprietary protocols, process control requests, and react to USB events (bind,
unbind, enable, disable, suspend, resume).

Ideal for complex HID devices with custom report descriptors, proprietary USB protocols, device prototyping, or anything
requiring precise timing or full protocol control.

The library ships `HIDFunctionFs` as a ready-made FunctionFS specialization with built-in HID protocol handling.

---

## Requirements

### Platform Support

- **OS**: Linux with USB Device Controller (UDC) support
- **Architecture**: ARM, ARM64, x86_64, RISC-V64 (any architecture with Linux UDC support)
- **Dart SDK**: ≥ 3.11.0

### Hardware

A device with a USB Device Controller (UDC) is required. Standard desktop PCs typically do **not** include a UDC — they
only have USB host controllers.

**Tested devices include:**

- Raspberry Pi 4/5 (ARM64)
- Raspberry Pi Zero 2 W (ARM64)
- One Plus 7 Pro (Android, ARM64)

To check if your device has a UDC:

```bash
ls /sys/class/udc/
# Should list one or more UDC devices (e.g., fe980000.usb)
```

### Dependencies

Install the Linux Asynchronous I/O library:

```bash
# Debian/Ubuntu
sudo apt-get install libaio-dev
# Arch Linux
sudo pacman -S libaio
# Fedora/RHEL
sudo dnf install libaio-devel
```

### Linux Kernel Configuration

The following kernel options must be enabled. Most modern embedded Linux distributions include these by default.

**Core USB Gadget Support**

- `CONFIG_USB_GADGET` — USB Gadget framework
- `CONFIG_USB_CONFIGFS` — ConfigFS-based gadget configuration
- `CONFIG_USB_FUNCTIONFS` — FunctionFS support

**Kernel Function Drivers**

- `CONFIG_USB_CONFIGFS_SERIAL` — Serial functions
- `CONFIG_USB_CONFIGFS_ACM` — CDC ACM serial
- `CONFIG_USB_CONFIGFS_NCM` — CDC NCM ethernet
- `CONFIG_USB_CONFIGFS_ECM` — CDC ECM ethernet
- `CONFIG_USB_CONFIGFS_ECM_SUBSET` — ECM Subset ethernet
- `CONFIG_USB_CONFIGFS_RNDIS` — RNDIS ethernet
- `CONFIG_USB_CONFIGFS_EEM` — CDC EEM ethernet
- `CONFIG_USB_CONFIGFS_MASS_STORAGE` — Mass storage
- `CONFIG_USB_CONFIGFS_F_HID` — HID functions
- `CONFIG_USB_CONFIGFS_F_PRINTER` — Printer function
- `CONFIG_USB_CONFIGFS_F_MIDI` — MIDI function
- `CONFIG_USB_CONFIGFS_F_UAC1` — Audio Class 1.0
- `CONFIG_USB_CONFIGFS_F_UAC2` — Audio Class 2.0
- `CONFIG_USB_CONFIGFS_F_UVC` — Video Class

**Check your kernel configuration:**

```bash
zcat /proc/config.gz | grep -E 'CONFIG_USB_(GADGET|CONFIGFS|FUNCTIONFS)'
# or
grep -E 'CONFIG_USB_(GADGET|CONFIGFS|FUNCTIONFS)' /boot/config-$(uname -r)
```

### Permissions

Root privileges or the `CAP_SYS_ADMIN` capability are required to configure USB gadgets.

```bash
# Verify ConfigFS is mounted
mount | grep configfs
# Should show: configfs on /sys/kernel/config type configfs (rw,relatime)

# Mount ConfigFS if needed
sudo mount -t configfs none /sys/kernel/config

# Running without full root (using capabilities)
sudo setcap cap_sys_admin+ep /path/to/your/dart/executable
```

---

## Installation & Usage

### Add the Package

```bash
dart pub add usb_gadget
```

### Basic Example: USB Keyboard

This example creates a USB HID keyboard that types "hello world" when connected:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

final _descriptor = Uint8List.fromList([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01, 0x75, 0x08, 0x81, 0x01, 0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00, 0xC0]);

class Keyboard extends HIDFunction {
  Keyboard()
      : super(
    name: 'keyboard',
    descriptor: _descriptor,
    protocol: .keyboard,
    subclass: .boot,
    reportLength: 8,
  );

  void sendKey(int keyCode, {int modifiers = 0}) =>
      file..writeFromSync(
        Uint8List(8)
          ..[0] = modifiers
          ..[2] = keyCode,
      )..writeFromSync(Uint8List(8));
}

Future<void> main() async {
  final keyboard = Keyboard();
  final gadget = Gadget(
    name: 'hid_keyboard',
    idVendor: 0x1234,
    idProduct: 0x5679,
    deviceClass: .composite,
    deviceSubClass: .none,
    deviceProtocol: .none,
    strings: {
          .enUS: const .new(
        manufacturer: 'ACME Corp',
        product: 'USB Keyboard',
        serialnumber: 'KB001',
      ),
    },
    config: .new(functions: [keyboard]),
  );

  try {
    await gadget.bind();
    await gadget.awaitState(.configured);
    // A short delay prevents the first few keypresses from being missed on some hosts.
    await Future<void>.delayed(const .new(milliseconds: 100));
    [0x0B, 0x08, 0x0F, 0x0F, 0x12, 0x2C, 0x1A, 0x12, 0x15, 0x0F, 0x07, 0x28]
    // Write "hello world\n"
    .forEach(keyboard.sendKey);
    stdout.writeln('Ctrl+C to exit.');
    await ProcessSignal.sigint.watch().first;
  } finally {
    await gadget.unbind();
  }
}
```

### Running Your Gadget

```bash
# During development (requires root)
sudo dart run bin/your_app.dart

# Compile to a self-contained executable
dart compile exe bin/your_app.dart -o my_gadget
sudo ./my_gadget

# With debug logging
dart compile exe -DUSB_GADGET_DEBUG=true bin/your_app.dart -o my_gadget
sudo ./my_gadget
```

### Examples

The [`example/`](example/) directory contains ready-to-run implementations.

---

## Android Support

> [!WARNING]
> Running `usb-gadget` on Android requires a **rooted device** with USB OTG/device controller (UDC) support. Not all
> Android devices expose a UDC — this is hardware-dependent. Stock Android kernels rarely ship with `CONFIG_USB_GADGET`
> or
> ConfigFS enabled; this is more common on development boards running AOSP or custom kernels.

Android devices with USB OTG capability can act as USB gadgets. Because Dart does not ship a pre-built SDK for Android,
you must compile the **Dart SDK** and **libaio** yourself, then compile your app **on the device**.

---

### Set up the Dart SDK source tree

> Refer to the official guide:
>
> [Building Dart SDK for ARM or RISC-V](https://github.com/dart-lang/sdk/blob/main/docs/Building-Dart-SDK-for-ARM-or-RISC-V.md)
> and
> [Building the Dart VM for Android](https://github.com/dart-lang/sdk/blob/main/docs/Building-the-Dart-VM-for-Android.md)

Follow the [standard Dart SDK build setup](https://github.com/dart-lang/sdk/blob/main/docs/Building.md) first — cloning
the repository directly will not work. You must use `gclient`.

Then enable Android dependencies by adding this line to your `.gclient` file (in the parent directory of `dart/`):

```
solutions = [ { 'custom_vars': {'download_android_deps': True},
    'deps_file': 'DEPS',
    'managed': True,
    'name': 'sdk',
    'url': 'https://dart.googlesource.com/sdk.git'}]
target_os = ['android']
```

Run `gclient sync` to download the Android NDK/SDK (~2 GB):

```bash
gclient sync
```

---

### Cross-compile the Dart SDK for Android

The build scripts include a Clang toolchain that can target ARM, ARM64, and RISC-V64 from an x64 or ARM64 host — no
separate cross-compiler is needed for these architectures.

```bash
./tools/build.py --mode=release --arch=arm64 --os=android create_sdk
```

Push the full SDK to your device (the full SDK is required to compile on-device — not just the `dart` binary):

```bash
adb push out/ReleaseAndroidARM64/dart-sdk /data/local/tmp/dart-sdk
```

---

### Cross-compile `libaio` for Android

`usb-gadget` depends on `libaio`. Cross-compile it using the Android NDK bundled with the Dart SDK source tree.

```bash
git clone https://pagure.io/libaio.git
cd libaio

# Point to the NDK bundled in the Dart SDK source
export ANDROID_NDK=$HOME/dart-android/sdk/third_party/android_tools/ndk

# Adjust the host prebuilt path for your OS:
export TOOLCHAIN=$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64

# Set the target triple — see the architecture table below
export CC=$TOOLCHAIN/bin/aarch64-linux-android21-clang
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip

# Verify the toolchain
$CC --version

make clean
make CC="$CC" AR="$AR" RANLIB="$RANLIB"
```

Push the compiled library to the device:

```bash
adb push src/libaio.so.1.0.2 /data/local/tmp/
adb shell ln -s /data/local/tmp/libaio.so.1.0.2 /data/local/tmp/libaio.so
```

---

### Compile and run your app on-device

Because `dart compile exe` must run on the **same platform as the target**, you must compile your app directly on the
Android device using the SDK you pushed in Step 2.

```bash
# Push your project to the device
adb push /path/to/your/usb_gadget_project /data/local/tmp/usb_gadget_project

# Open a root shell
adb shell
su

export PATH=/data/local/tmp/dart-sdk/bin:$PATH
cd /data/local/tmp/usb_gadget_project

# Fetch dependencies
dart pub get

# Compile
dart compile exe bin/your_app.dart -o usb_gadget_app

# Run
LD_LIBRARY_PATH=/data/local/tmp ./usb_gadget_app
```

Before running, make sure no other USB gadget is active and ConfigFS is mounted:

```bash
# Save the current USB config before disabling it
ORIGINAL_USB_CONFIG=$(getprop sys.usb.config)

# Disable any active Android USB gadget (MTP, ADB, etc.)
# Without this, the UDC may already be claimed and gadget binding will fail
setprop sys.usb.config none
sleep 1

# To restore Android's USB gadget after you're done:
# setprop sys.usb.config "$ORIGINAL_USB_CONFIG"

# Mount ConfigFS if not already mounted
mount -t configfs none /sys/kernel/config
```

---

## Resources

- [API Documentation](https://pub.dev/documentation/usb_gadget/latest/)
- [Linux USB Gadget API](https://www.kernel.org/doc/html/latest/usb/gadget.html)
- [USB in a Nutshell](https://www.beyondlogic.org/usbnutshell/usb1.shtml)
- [HID Usage Tables](https://usb.org/sites/default/files/hut1_3_0.pdf)
- [usb-gadget (Rust)](https://github.com/surban/usb-gadget)
- [functionfs (Python)](https://github.com/vpelletier/python-functionfs)
- [Building the Dart VM for Android](https://github.com/dart-lang/sdk/blob/main/docs/Building-the-Dart-VM-for-Android.md)
- [Building Dart SDK for ARM or RISC-V](https://github.com/dart-lang/sdk/blob/main/docs/Building-Dart-SDK-for-ARM-or-RISC-V.md)
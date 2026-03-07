# usb-gadget

> [!WARNING]
> This library is under active development. Breaking changes may occur without warning.

Turn any Linux device with a USB controller into a USB peripheral — keyboard, mouse, storage, network adapter, audio
device, or your own custom protocol — written entirely in Dart.

[![pub package](https://img.shields.io/pub/v/usb_gadget.svg)](https://pub.dev/packages/usb_gadget)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

---

## What You Can Build

### Ready-Made Kernel Functions

These work with zero protocol boilerplate — just configure and go.

| Category        | Functions                                       |
|-----------------|-------------------------------------------------|
| **Network**     | CDC ECM, ECM Subset, EEM, NCM, RNDIS            |
| **Serial**      | CDC ACM, Generic Serial                         |
| **HID**         | Keyboards, mice, gamepads, custom devices       |
| **Storage**     | Mass Storage Device (USB flash drive emulation) |
| **Audio/Video** | MIDI, UAC1, UAC2, UVC (webcam)                  |
| **Printer**     | USB Printer Class                               |
| **Testing**     | Loopback, SourceSink                            |

### Custom Functions with FunctionFS

Need full control? FunctionFS lets you define your own USB descriptors, handle endpoints directly, implement proprietary
protocols, and respond to USB lifecycle events (bind, unbind, enable, disable, suspend, resume).

The library includes `HIDFunctionFs` — a ready-made FunctionFS specialization for custom HID devices with complex report
descriptors.

---

## Quick Start

### 1. Check hardware compatibility

You need a device with a USB Device Controller (UDC). Desktop PCs typically don't have one — embedded boards like the
Raspberry Pi do.

```bash
ls /sys/class/udc/
# Should list at least one device, e.g.: fe980000.usb
```

**Tested devices:** Raspberry Pi 4/5, Raspberry Pi Zero 2 W, OnePlus 7 Pro (Android)

### 2. Install the system dependency

```bash
# Debian/Ubuntu
sudo apt-get install libaio-dev

# Arch Linux
sudo pacman -S libaio

# Fedora/RHEL
sudo dnf install libaio-devel
```

### 3. Add the package

```bash
dart pub add usb_gadget
```

### 4. Mount ConfigFS (if needed)

```bash
# Check if already mounted
mount | grep configfs

# Mount if not present
sudo mount -t configfs none /sys/kernel/config
```

---

## Example: USB Keyboard

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

final _descriptor = Uint8List.fromList([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01, 0x75, 0x08, 0x81, 0x01, 0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00, 0xC0]);

class Keyboard extends HIDFunction {
  Keyboard() : super(
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
    deviceClass: .perInterface,
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

### Run it

```bash
# Development
sudo dart run bin/your_app.dart

# Compiled executable (recommended for deployment)
dart compile exe bin/your_app.dart -o my_gadget
sudo ./my_gadget

# With debug logging
dart compile exe -DUSB_GADGET_DEBUG=true bin/your_app.dart -o my_gadget
sudo ./my_gadget
```

More examples are available in the [`example/`](example/) directory.

---

## Permissions

Root or `CAP_SYS_ADMIN` is required to configure USB gadgets.

```bash
# Option A: run with sudo
sudo ./my_gadget

# Option B: grant capability to the binary (avoids full root)
sudo setcap cap_sys_admin+ep ./my_gadget
./my_gadget
```

---

## Kernel Configuration

Most modern embedded distributions already include the required options. To verify:

```bash
zcat /proc/config.gz | grep -E 'CONFIG_USB_(GADGET|CONFIGFS|FUNCTIONFS)'
```

Key options: `CONFIG_USB_GADGET`, `CONFIG_USB_CONFIGFS`, `CONFIG_USB_FUNCTIONFS`, plus any function-specific drivers you
need (e.g. `CONFIG_USB_CONFIGFS_F_HID` for HID).

---

To incorporate the official Android build documentation into your guide, I have refined the steps to ensure the
`.gclient` configuration is correct and added the necessary dependency installation step required for Linux hosts.

## Android Support

> [!IMPORTANT]
> **Prerequisites:** The host (build) machine must be an x64 Linux machine or a Mac. The target
> Android device must support the Android NDK. The resulting Dart VM can only be run from the
> Android command line and **only has access to `dart:core` APIs** — it does not have access to
> Android C or Java APIs.

Because there are no pre-built Dart SDKs for Android, you must cross-compile the SDK and `libaio`
on your host machine before deploying to your device.

<details>
<summary>Expand Android setup instructions</summary>

### 1. Build the Dart SDK for Android

First, follow the [official Dart SDK build guide](https://github.com/dart-lang/sdk/blob/main/docs/Building.md)
to set up `depot_tools` and fetch the Dart source tree.

Then, use a text editor to add the `download_android_deps` variable to your `.gclient` file
(located in the directory where you ran `fetch dart`):

```python
solutions = [
  {
    "name": "sdk",
    "url": "https://dart.googlesource.com/sdk.git",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {
        "download_android_deps": True,
    },
  },
]
```

Then sync dependencies and build:

```bash
# Download Android NDK and SDK dependencies
gclient sync

# Build the full SDK for ARM64 Android
./tools/build.py --mode=release --arch=arm64 --os=android create_sdk

# Push the built SDK to your device
adb push out/android/ReleaseAndroidARM64/dart-sdk /data/local/tmp/dart-sdk
```

---

### 2. Cross-compile `libaio`

`libaio` is required by this library but is not available via a package manager on Android. You
must cross-compile it on your host using the Clang toolchain bundled with the Dart SDK's
third-party dependencies.

```bash
git clone https://pagure.io/libaio.git && cd libaio

# Adjust the path below to match your Dart SDK checkout location
export TOOLCHAIN=$HOME/dart-sdk/sdk/third_party/android_tools/ndk/toolchains/llvm/prebuilt/linux-x86_64
export CC=$TOOLCHAIN/bin/aarch64-linux-android21-clang
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib

make clean && make CC="$CC" AR="$AR" RANLIB="$RANLIB"

# Deploy to device
adb push src/libaio.so.1.0.2 /data/local/tmp/
adb shell ln -s /data/local/tmp/libaio.so.1.0.2 /data/local/tmp/libaio.so
```

---

### 3. Compile and Execute On-Device

```bash
# Upload your project
adb push /path/to/your/project /data/local/tmp/usb_gadget_project
adb shell
su

# Setup environment
export PATH=/data/local/tmp/dart-sdk/bin:$PATH
export PUB_CACHE=/data/local/tmp/.pub-cache/
cd /data/local/tmp/usb_gadget_project

# Fetch dependencies and compile
dart pub get
dart compile exe bin/your_app.dart -o usb_gadget_app
chmod +x usb_gadget_app

# Detach the UDC from the Android USB stack
ORIGINAL=$(getprop sys.usb.config)
setprop sys.usb.config none && sleep 1
mount -t configfs none /sys/kernel/config

# Run the app with the cross-compiled libaio
LD_LIBRARY_PATH=/data/local/tmp ./usb_gadget_app

# Cleanup: Restore USB config when finished
# setprop sys.usb.config "$ORIGINAL"
```

</details>

---

## Resources

- [API Documentation](https://pub.dev/documentation/usb_gadget/latest/)
- [Linux USB Gadget API](https://www.kernel.org/doc/html/latest/driver-api/usb/gadget.html)
- [USB in a Nutshell](https://www.beyondlogic.org/usbnutshell/usb1.shtml)
- [HID Usage Tables](https://usb.org/sites/default/files/hut1_3_0.pdf)
- [usb-gadget (Rust)](https://github.com/surban/usb-gadget)
- [functionfs (Python)](https://github.com/vpelletier/python-functionfs)
# usb-gadget

[![pub package](https://img.shields.io/pub/v/usb_gadget.svg)](https://pub.dev/packages/usb_gadget)
[![Apache 2.0 license](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A Dart library for turning any Linux device with a USB controller into a USB peripheral —
keyboard, mouse, storage, network adapter, audio device, or your own custom protocol.

Requires a device with a USB Device Controller (UDC). Embedded boards (Raspberry Pi 4/5, Zero 2 W)
and Android phones with NDK support (e.g. OnePlus 7 Pro) work great; standard PCs typically don't 
have one.

```shell
  dart pub add usb_gadget
```

## Requirements

```bash
sudo apt-get install libaio-dev                  # library required by this package
sudo modprobe libcomposite                       # kernel module for USB gadget support
sudo mount -t configfs none /sys/kernel/config   # if not already mounted
```

## Example

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

class Keyboard extends HIDFunction {
  Keyboard() : super(
    name: 'keyboard',
    descriptor: .fromList([
      0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07,
      0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01,
      0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01,
      0x75, 0x08, 0x81, 0x01, 0x95, 0x06, 0x75, 0x08,
      0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00,
      0x29, 0x65, 0x81, 0x00, 0xC0,
    ]),
    protocol: 1,
    subClass: 1,
    reportLength: 8,
  );

  void sendKey(int keyCode, {int modifiers = 0}) => file
    ..writeFromSync(
      Uint8List(8)
        ..[0] = modifiers
        ..[2] = keyCode,
    )
    ..writeFromSync(Uint8List(8));
}

Future<void> main() async {
  final keyboard = Keyboard();
  final gadget = Gadget(
    name: 'hid_keyboard',
    id: Id(vendor: 0x1234, product: 0x5679),
    class_: .interfaceSpecific(),
    strings: {
      .enUS: const .new(
        manufacturer: 'ACME Corp',
        product: 'USB Keyboard',
        serialnumber: 'KB001',
      ),
    },
    configs: [.new(description: 'A Keyboard', functions: [keyboard])],
  );

  try {
    final reg = await gadget.register();
    reg.bind(defaultUDC);
    await reg.udc?.awaitState(.configured);
    await Future.delayed(const .new(milliseconds: 100));
    [0x0B, 0x08, 0x0F, 0x0F, 0x12, 0x2C, 0x1A, 0x12, 0x15, 0x0F, 0x07, 0x28]
    // Write "hello world\n"
    .forEach(keyboard.sendKey);
    await ProcessSignal.sigint.watch().first;
  } finally {
    await gadget.remove();
  }
}
```
> [!NOTE]
> More examples (gamepad, mass storage, custom FunctionFS) are in [`example/`](example/).

> [!TIP]
> Compile to a native executable for production use — JIT latency can cause timing violations 
> in FunctionFS gadgets.
> ```bash
> dart compile exe bin/app.dart -o my_gadget && sudo ./my_gadget
> ```
> Enable debug logging at compile time:
> ```bash
> dart compile exe \
>   -DUSB_GADGET_LOG=true \
>   -DUSB_GADGET_LOG_COLORS=true \
>   -DUSB_GADGET_LOG_LEVEL=0 \
>   bin/app.dart -o my_gadget
> ```

## Kernel configuration

Most embedded distributions ship with the required options already enabled. To verify:

```bash
zcat /proc/config.gz | grep -E 'CONFIG_USB_(GADGET|CONFIGFS|FUNCTIONFS)'
```

<details>
<summary>Full list of kernel options</summary>

- `CONFIG_USB_GADGET`
- `CONFIG_USB_CONFIGFS`
- `CONFIG_USB_FUNCTIONFS`
- `CONFIG_USB_CONFIGFS_F_HID`
- `CONFIG_USB_CONFIGFS_F_FS`
- `CONFIG_USB_CONFIGFS_MASS_STORAGE`
- `CONFIG_USB_CONFIGFS_SERIAL`
- `CONFIG_USB_CONFIGFS_ACM`
- `CONFIG_USB_CONFIGFS_NCM`
- `CONFIG_USB_CONFIGFS_ECM`
- `CONFIG_USB_CONFIGFS_ECM_SUBSET`
- `CONFIG_USB_CONFIGFS_RNDIS`
- `CONFIG_USB_CONFIGFS_EEM`
- `CONFIG_USB_CONFIGFS_F_PRINTER`
- `CONFIG_USB_CONFIGFS_F_MIDI`
- `CONFIG_USB_CONFIGFS_F_UAC1`
- `CONFIG_USB_CONFIGFS_F_UAC2`
- `CONFIG_USB_CONFIGFS_F_UVC`

</details>

## Android

No pre-built Dart SDK exists for Android — you must cross-compile both the SDK and `libaio` and
deploy to the device. The resulting binary runs from the Android command line only, with access to
`dart:core` APIs only.

<details>
<summary>Setup instructions</summary>

**1. Build the Dart SDK for Android**

Follow the [official Dart SDK build guide](https://github.com/dart-lang/sdk/blob/main/docs/Building.md),
then add `"download_android_deps": True` to `custom_vars` in your `.gclient` file and run:

```bash
gclient sync
./tools/build.py --mode=release --arch=arm64 --os=android create_sdk
adb push out/android/ReleaseAndroidARM64/dart-sdk /data/local/tmp/dart-sdk
```

**2. Cross-compile `libaio`**

```bash
git clone https://pagure.io/libaio.git && cd libaio

export TOOLCHAIN=<PATH>/dart-sdk/sdk/third_party/android_tools/ndk/toolchains/llvm/prebuilt/<ARCH>
export CC=$TOOLCHAIN/bin/aarch64-linux-android21-clang
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib

make clean && make CC="$CC" AR="$AR" RANLIB="$RANLIB"
adb push src/libaio.so.1.0.2 /data/local/tmp/
adb shell ln -s /data/local/tmp/libaio.so.1.0.2 /data/local/tmp/libaio.so
```

**3. Compile and run on-device**

```bash
adb push /path/to/your/project /data/local/tmp/project && adb shell
su
export PATH=/data/local/tmp/dart-sdk/bin:$PATH PUB_CACHE=/data/local/tmp/.pub-cache/
cd /data/local/tmp/project && dart pub get
dart compile exe bin/your_app.dart -o app && chmod +x app

# Detach UDC from the Android USB stack
ORIGINAL=$(getprop sys.usb.config)
setprop sys.usb.config none && sleep 1
mount -t configfs none /sys/kernel/config

LD_LIBRARY_PATH=/data/local/tmp ./app
sudo ./app

setprop sys.usb.config "$ORIGINAL"
```

</details>

## Credits & References

- https://github.com/vpelletier/python-functionfs
- https://github.com/surban/usb-gadget
- https://www.beyondlogic.org/usbnutshell/usb1.shtml
- https://www.kernel.org/doc/Documentation/filesystems/configfs/configfs.txt
- https://www.kernel.org/doc/html/latest/driver-api/usb/gadget.html

import 'dart:async';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

/// Standard USB HID keyboard report descriptor.
final _descriptor = Uint8List.fromList([
  0x05, 0x01, // Usage Page (Generic Desktop)
  0x09, 0x06, // Usage (Keyboard)
  0xA1, 0x01, // Collection (Application)
  0x05, 0x07, //   Usage Page (Key Codes)
  0x19, 0xE0, //   Usage Minimum (224) - Left Control
  0x29, 0xE7, //   Usage Maximum (231) - Right GUI
  0x15, 0x00, //   Logical Minimum (0)
  0x25, 0x01, //   Logical Maximum (1)
  0x75, 0x01, //   Report Size (1 bit)
  0x95, 0x08, //   Report Count (8) - 8 modifier keys
  0x81, 0x02, //   Input (Data, Variable, Absolute) - Modifier byte
  0x95, 0x01, //   Report Count (1)
  0x75, 0x08, //   Report Size (8)
  0x81, 0x01, //   Input (Constant) - Reserved byte
  0x95, 0x06, //   Report Count (6)
  0x75, 0x08, //   Report Size (8)
  0x15, 0x00, //   Logical Minimum (0)
  0x25, 0x65, //   Logical Maximum (101)
  0x05, 0x07, //   Usage Page (Key Codes)
  0x19, 0x00, //   Usage Minimum (0)
  0x29, 0x65, //   Usage Maximum (101)
  0x81, 0x00, //   Input (Data, Array) - Key array
  0xC0, // End Collection
]);

class KeyboardFunction extends HIDFunctionFs {
  KeyboardFunction()
    : super(
        name: 'keyboard',
        reportDescriptor: _descriptor,
        subclass: .boot,
        protocol: .keyboard,
        endpointConfig: const .inputOnly(maxPacketSize: 8),
        speeds: {.fullSpeed, .highSpeed},
        strings: {
          .enUS: ['ACME USB Keyboard'],
        },
      );

  final Completer<void> _hostReady = Completer();

  Future<void> get hostReady => _hostReady.future;

  @override
  Future<void> onSetIdle(int reportId, int duration) async {
    super.onSetIdle(reportId, duration);
    // Additional delay to fix some host timing issues
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _hostReady.complete();
  }

  void sendKey(int keyCode, {int modifiers = 0}) {
    sendReport(Uint8List(8)
      ..[0] = modifiers
      ..[2] = keyCode);
    sendReport(Uint8List(8));
  }
}

Future<void> main() async {
  final keyboard = KeyboardFunction();
  final gadget = Gadget(
    name: 'hid_keyboard',
    idVendor: 0x1234,
    idProduct: 0x5679,
    deviceClass: .composite,
    deviceSubClass: .none,
    deviceProtocol: .none,
    strings: {
      .enUS: const GadgetStrings(
        manufacturer: 'ACME Corp',
        product: 'USB Keyboard',
        serialnumber: 'KB001',
      ),
    },
    config: .new(functions: [keyboard]),
  );
  try {
    await gadget.bind();
    await keyboard.hostReady;
    [0x0B, 0x08, 0x0F, 0x0F, 0x12, 0x2C, 0x1A, 0x12, 0x15, 0x0F, 0x07, 0x28]
    // hello world\n
    .forEach(keyboard.sendKey);
  } finally {
    gadget.unbind();
  }
}

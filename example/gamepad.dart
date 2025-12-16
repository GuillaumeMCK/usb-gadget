import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

/// Simple standard HID Gamepad Report Descriptor
final _descriptor = Uint8List.fromList([
  0x05, 0x01, // Usage Page (Generic Desktop)
  0x09, 0x05, // Usage (Gamepad)
  0xA1, 0x01, // Collection (Application)
  // Buttons (12 buttons)
  0x05, 0x09, //   Usage Page (Button)
  0x19, 0x01, //   Usage Minimum (Button 1)
  0x29, 0x0C, //   Usage Maximum (Button 12)
  0x15, 0x00, //   Logical Minimum (0)
  0x25, 0x01, //   Logical Maximum (1)
  0x75, 0x01, //   Report Size (1)
  0x95, 0x0C, //   Report Count (12)
  0x81, 0x02, //   Input (Data, Variable, Absolute)
  // Padding (4 bits to complete the byte)
  0x75, 0x01, //   Report Size (1)
  0x95, 0x04, //   Report Count (4)
  0x81, 0x01, //   Input (Constant)
  // Left Stick X & Y (8-bit each for simplicity)
  0x05, 0x01, //   Usage Page (Generic Desktop)
  0x09, 0x30, //   Usage (X)
  0x09, 0x31, //   Usage (Y)
  0x15, 0x00, //   Logical Minimum (0)
  0x26, 0xFF, 0x00, // Logical Maximum (255)
  0x75, 0x08, //   Report Size (8)
  0x95, 0x02, //   Report Count (2)
  0x81, 0x02, //   Input (Data, Variable, Absolute)
  // Right Stick X & Y (8-bit each)
  0x09, 0x33, //   Usage (Rx)
  0x09, 0x34, //   Usage (Ry)
  0x15, 0x00, //   Logical Minimum (0)
  0x26, 0xFF, 0x00, // Logical Maximum (255)
  0x75, 0x08, //   Report Size (8)
  0x95, 0x02, //   Report Count (2)
  0x81, 0x02, //   Input (Data, Variable, Absolute)
  // Triggers (8-bit each)
  0x09, 0x32, //   Usage (Z) - Left Trigger
  0x09, 0x35, //   Usage (Rz) - Right Trigger
  0x15, 0x00, //   Logical Minimum (0)
  0x26, 0xFF, 0x00, // Logical Maximum (255)
  0x75, 0x08, //   Report Size (8)
  0x95, 0x02, //   Report Count (2)
  0x81, 0x02, //   Input (Data, Variable, Absolute)
  // D-Pad (Hat Switch)
  0x09, 0x39, //   Usage (Hat Switch)
  0x15, 0x00, //   Logical Minimum (0)
  0x25, 0x07, //   Logical Maximum (7)
  0x35, 0x00, //   Physical Minimum (0)
  0x46, 0x3B, 0x01, // Physical Maximum (315)
  0x65, 0x14, //   Unit (Degrees)
  0x75, 0x04, //   Report Size (4)
  0x95, 0x01, //   Report Count (1)
  0x81, 0x42, //   Input (Data, Variable, Absolute, Null State)
  // Padding (4 bits)
  0x75, 0x04, //   Report Size (4)
  0x95, 0x01, //   Report Count (1)
  0x81, 0x01, //   Input (Constant)

  0xC0, // End Collection
]);

/// Gamepad button enumeration
enum GamepadButton {
  a,
  b,
  x,
  y,
  leftBumper,
  rightBumper,
  view,
  menu,
  leftStick,
  rightStick,
  guide,
  extra,
}

/// Analog stick report (8-bit unsigned, 0-255, center at 128)
class AnalogStick {
  int _x = 128;
  int _y = 128;

  int get x => _x;

  int get y => _y;

  set x(int value) => _x = value.clamp(0, 255);

  set y(int value) => _y = value.clamp(0, 255);

  void setPosition(int x, int y) {
    this.x = x;
    this.y = y;
  }

  void center() {
    _x = 128;
    _y = 128;
  }
}

/// Trigger report (8-bit, 0-255)
class Trigger {
  int _value = 0;

  int get value => _value;

  set value(int v) => _value = v.clamp(0, 255);

  void reset() => _value = 0;
}

/// Gamepad report for HID reports
class GamepadReport {
  final AnalogStick leftStick = AnalogStick();
  final AnalogStick rightStick = AnalogStick();
  final Trigger leftTrigger = Trigger();
  final Trigger rightTrigger = Trigger();

  int _buttons = 0;
  int _dpad = 15;

  int get buttons => _buttons;

  int get dpad => _dpad;

  set dpad(int value) => _dpad = value.clamp(0, 15);

  // Report structure: 2 bytes buttons + 2 bytes left stick + 2 bytes right stick + 2 bytes triggers + 1 byte dpad = 9 bytes
  final Uint8List _reportBytes = Uint8List(9);
  late final ByteData _reportBuffer = ByteData.view(_reportBytes.buffer);

  void setButton(GamepadButton button, bool pressed) {
    if (pressed) {
      _buttons |= 1 << button.index;
    } else {
      _buttons &= ~(1 << button.index);
    }
  }

  bool getButton(GamepadButton button) {
    return (_buttons & (1 << button.index)) != 0;
  }

  void pressButton(GamepadButton button) => setButton(button, true);

  void releaseButton(GamepadButton button) => setButton(button, false);

  void releaseAllButtons() => _buttons = 0;

  void reset() {
    _buttons = 0;
    _dpad = 15;
    leftStick.center();
    rightStick.center();
    leftTrigger.reset();
    rightTrigger.reset();
  }

  Uint8List toBytes() {
    _reportBuffer
      ..setUint16(0, _buttons, Endian.little) // Buttons (2 bytes)
      ..setUint8(2, leftStick.x) // Left X
      ..setUint8(3, leftStick.y) // Left Y
      ..setUint8(4, rightStick.x) // Right X
      ..setUint8(5, rightStick.y) // Right Y
      ..setUint8(6, leftTrigger.value) // Left Trigger
      ..setUint8(7, rightTrigger.value) // Right Trigger
      ..setUint8(8, _dpad); // D-pad (lower 4 bits) + padding (upper 4 bits)
    return _reportBytes;
  }
}

class SimpleGamepad extends HIDFunctionFs {
  SimpleGamepad()
    : super(
        name: 'gamepad',
        reportDescriptor: _descriptor,
        subclass: .none,
        protocol: .none,
        config: const .inputOnly(maxPacketSize: 9, reportIntervalMs: 8),
        speeds: {.fullSpeed, .highSpeed},
        strings: {
          .enUS: ['Generic USB Gamepad'],
        },
      );

  int _frameCounter = 0;
  Timer? _reportTimer;

  final GamepadReport report = GamepadReport();

  @override
  Future<void> onEnable() async {
    super.onEnable();
    await waitUSBDeviceState(.configured);
    _reportTimer = Timer.periodic(
      Duration(milliseconds: config.reportIntervalMs),
      (timer) {
        if (state != .enabled) {
          return timer.cancel();
        }
        _animateFrame();
        epIn.write(report.toBytes());
      },
    );
  }

  @override
  Future<void> dispose() async {
    _reportTimer?.cancel();
    _reportTimer = null;
    await super.dispose();
  }

  void _animateFrame() {
    _frameCounter++;
    final time = _frameCounter * config.reportIntervalMs / 1000.0;

    // Left stick: circular motion (slow rotation)
    final leftAngle = time * 0.5 * (2 * pi);
    report.leftStick.x = (128 + 100 * cos(leftAngle)).round();
    report.leftStick.y = (128 + 100 * sin(leftAngle)).round();

    // Right stick: figure-8 pattern (Lissajous curve)
    final rightAngle = time * 0.8 * (2 * pi);
    report.rightStick.x = (128 + 80 * cos(rightAngle)).round();
    report.rightStick.y = (128 + 80 * sin(2 * rightAngle)).round();

    // Left trigger: sine wave (0-255)
    report.leftTrigger.value = ((sin(time * 2) + 1) * 127.5).round();

    // Right trigger: sawtooth wave (0-255)
    final sawtoothPhase = (time * 0.5) % 1.0;
    report.rightTrigger.value = (sawtoothPhase * 255).round();

    // D-pad: rotate through all 8 directions (plus center)
    final dpadCycle = (time * 0.5).floor() % 9;
    report.dpad = dpadCycle < 8
        ? dpadCycle
        : 15; // 0-7 = directions, 15 = center

    // Buttons: sequential toggle pattern
    report.releaseAllButtons();
    final buttonIndex = (_frameCounter ~/ 30) % GamepadButton.values.length;
    report.setButton(GamepadButton.values[buttonIndex], true);
  }
}

Future<void> main() async {
  final gamepad = SimpleGamepad();
  final gadget = Gadget(
    name: 'generic_gamepad',
    idVendor: 0x1209,
    idProduct: 0x0001,
    deviceClass: .composite,
    strings: const {
      .enUS: .new(
        manufacturer: 'Generic',
        product: 'USB Gamepad',
        serialnumber: 'GP000001',
      ),
    },
    config: .new(
      attributes: .busPowered,
      maxPower: .fromMilliAmps(500),
      strings: const {.enUS: 'USB Gamepad Configuration'},
      functions: [gamepad],
    ),
  );

  try {
    await gadget.bind();
    stdout.writeln('Press Ctrl+C to stop');
    await ProcessSignal.sigint.watch().first;
  } finally {
    gadget.unbind();
  }
}

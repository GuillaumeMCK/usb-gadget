import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

/// Standard HID Gamepad Report Descriptor
final _descriptor = Uint8List.fromList([
  0x05, 0x01, // Usage Page (Generic Desktop)
  0x09, 0x05, // Usage (Gamepad)
  0xA1, 0x01, // Collection (Application)
  // Buttons (16 buttons)
  0x05, 0x09, //   Usage Page (Button)
  0x19, 0x01, //   Usage Minimum (Button 1)
  0x29, 0x10, //   Usage Maximum (Button 16)
  0x15, 0x00, //   Logical Minimum (0)
  0x25, 0x01, //   Logical Maximum (1)
  0x75, 0x01, //   Report Size (1)
  0x95, 0x10, //   Report Count (16)
  0x81, 0x02, //   Input (Data, Variable, Absolute)
  // Left Stick X & Y
  0x05, 0x01, //   Usage Page (Generic Desktop)
  0x09, 0x30, //   Usage (X)
  0x09, 0x31, //   Usage (Y)
  0x15, 0x00, //   Logical Minimum (0)
  0x26, 0xFF, 0xFF, // Logical Maximum (65535)
  0x75, 0x10, //   Report Size (16)
  0x95, 0x02, //   Report Count (2)
  0x81, 0x02, //   Input (Data, Variable, Absolute)
  // Right Stick X & Y
  0x09, 0x33, //   Usage (Rx)
  0x09, 0x34, //   Usage (Ry)
  0x15, 0x00, //   Logical Minimum (0)
  0x26, 0xFF, 0xFF, // Logical Maximum (65535)
  0x75, 0x10, //   Report Size (16)
  0x95, 0x02, //   Report Count (2)
  0x81, 0x02, //   Input (Data, Variable, Absolute)
  // Triggers (Z and Rz)
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
  // Padding
  0x75, 0x04, //   Report Size (4)
  0x95, 0x01, //   Report Count (1)
  0x81, 0x03, //   Input (Constant, Variable, Absolute)

  0xC0, // End Collection
]);

/// Gamepad button enumeration matching Xbox controller layout
enum GamepadButton {
  a, // Button 1
  b, // Button 2
  x, // Button 3
  y, // Button 4
  leftBumper, // Button 5
  rightBumper, // Button 6
  view, // Button 7
  menu, // Button 8
  leftStick, // Button 9
  rightStick, // Button 10
  guide; // Button 11

  @override
  String toString() => switch (this) {
    GamepadButton.a => 'A',
    GamepadButton.b => 'B',
    GamepadButton.x => 'X',
    GamepadButton.y => 'Y',
    GamepadButton.leftBumper => 'LB',
    GamepadButton.rightBumper => 'RB',
    GamepadButton.view => 'View',
    GamepadButton.menu => 'Menu',
    GamepadButton.leftStick => 'LS',
    GamepadButton.rightStick => 'RS',
    GamepadButton.guide => 'Guide',
  };
}

/// Analog stick report (16-bit unsigned, 0-65535)
class AnalogStick {
  int _x = 32768;
  int _y = 32768;

  int get x => _x;

  int get y => _y;

  set x(int value) => _x = value.clamp(0, 65535);

  set y(int value) => _y = value.clamp(0, 65535);

  void setPosition(int x, int y) {
    this.x = x;
    this.y = y;
  }

  void center() {
    _x = 32768;
    _y = 32768;
  }

  @override
  String toString() => '($x, $y)';
}

/// Trigger report (8-bit, 0-255)
class Trigger {
  int _value = 0;

  int get value => _value;

  set value(int v) => _value = v.clamp(0, 255);

  void reset() => _value = 0;

  @override
  String toString() => '$_value';
}

/// Gamepad report for HID reports
class GamepadReport {
  final AnalogStick leftStick = AnalogStick();
  final AnalogStick rightStick = AnalogStick();
  final Trigger leftTrigger = Trigger();
  final Trigger rightTrigger = Trigger();

  int _buttons = 0;
  int _dpad = 8;

  int get buttons => _buttons;

  int get dpad => _dpad;

  set dpad(int value) => _dpad = value.clamp(0, 8);

  final Uint8List _reportBytes = Uint8List(14);
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
    _dpad = 8;
    leftStick.center();
    rightStick.center();
    leftTrigger.reset();
    rightTrigger.reset();
  }

  Uint8List toBytes() {
    _reportBuffer
      ..setUint16(0, _buttons, Endian.little)
      ..setUint16(2, leftStick.x, Endian.little)
      ..setUint16(4, leftStick.y, Endian.little)
      ..setUint16(6, rightStick.x, Endian.little)
      ..setUint16(8, rightStick.y, Endian.little)
      ..setUint8(10, leftTrigger.value)
      ..setUint8(11, rightTrigger.value)
      ..setUint8(12, _dpad)
      ..setUint8(13, 0);
    return _reportBytes;
  }
}

class SimpleGamepad extends HIDFunctionFs {
  SimpleGamepad()
    : super(
        name: 'gamepad',
        reportDescriptor: _descriptor,
        subclass: HIDSubclass.none,
        protocol: HIDProtocol.none,
        endpointConfig: const .inputOnly(
          maxPacketSize: 14,
          pollingIntervalMs: 8,
        ),
        speeds: {USBSpeed.fullSpeed, USBSpeed.highSpeed},
        strings: {
          USBLanguageId.enUS: ['Simple Gamepad'],
        },
      );

  int _frameCounter = 0;
  Timer? _reportTimer;

  final GamepadReport report = GamepadReport();

  @override
  void onEnable() {
    _reportTimer = Timer.periodic(
      Duration(milliseconds: endpointConfig.pollingIntervalMs),
      (timer) {
        if (state != .enabled) {
          return timer.cancel();
        }
        _animateFrame();
        sendReport(report.toBytes());
      },
    );
    super.onEnable();
  }

  @override
  void onDisable() {
    _reportTimer?.cancel();
    _reportTimer = null;
    _frameCounter = 0;
    super.onDisable();
  }

  void _animateFrame() {
    _frameCounter++;
    final time = _frameCounter * endpointConfig.pollingIntervalMs / 1000.0;

    // Left stick: circular motion (slow rotation)
    final leftAngle = time * 0.5 * (2 * pi);
    report.leftStick.x = (32768 + 25000 * cos(leftAngle)).round();
    report.leftStick.y = (32768 + 25000 * sin(leftAngle)).round();

    // Right stick: figure-8 pattern (Lissajous curve)
    final rightAngle = time * 0.8 * (2 * pi);
    report.rightStick.x = (32768 + 20000 * cos(rightAngle)).round();
    report.rightStick.y = (32768 + 20000 * sin(2 * rightAngle)).round();

    // Left trigger: sine wave (0-255)
    report.leftTrigger.value = ((sin(time * 2) + 1) * 127.5).round();

    // Right trigger: sawtooth wave (0-255)
    final sawtoothPhase = (time * 0.5) % 1.0;
    report.rightTrigger.value = (sawtoothPhase * 255).round();

    // D-pad: rotate through all 8 directions (plus center)
    final dpadCycle = (time * 0.5).floor() % 9;
    report.dpad = dpadCycle; // 0-7 = directions, 8 = center

    // Buttons: sequential toggle pattern
    report.releaseAllButtons();
    final buttonIndex = (_frameCounter ~/ 30) % GamepadButton.values.length;
    report.setButton(GamepadButton.values[buttonIndex], true);
  }
}

Future<void> main() async {
  final gadget = Gadget(
    name: 'simple_gamepad',
    idVendor: 0x1234,
    idProduct: 0x5678,
    deviceClass: .composite,
    strings: const {
      .enUS: GadgetStrings(
        manufacturer: 'Custom',
        product: 'Simple Gamepad',
        serialnumber: 'GAMEPAD001',
      ),
    },
    config: .new(
      attributes: .busPowered,
      maxPower: .fromMilliAmps(500),
      strings: const {.enUS: 'Gamepad Configuration'},
      functions: [SimpleGamepad()],
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

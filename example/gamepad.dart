import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

// ---------------------------------------------------------------------------
// Logitech F310 – DirectInput mode ("Logitech Dual Action", 046d:c216)
//
// Report layout (7 bytes, no report-ID prefix):
//   Byte 0 : Left-stick X   0x00–0xFF  (centre = 0x80)
//   Byte 1 : Left-stick Y   0x00–0xFF  (centre = 0x80, up = 0x00)
//   Byte 2 : Right-stick X  0x00–0xFF  (centre = 0x80)
//   Byte 3 : Right-stick Y  0x00–0xFF  (centre = 0x80, up = 0x00)
//   Byte 4 : Buttons 1–8    (bit 0 = B1 … bit 7 = B8)
//   Byte 5 : Buttons 9–12 in bits [3:0] + 4 padding bits [7:4]
//   Byte 6 : Hat nibble [3:0] (0–7 = direction, 8 = centre) + 4 padding bits
// ---------------------------------------------------------------------------

enum F310Button implements BitFlag {
  x(1 << 0),
  a(1 << 1),
  b(1 << 2),
  y(1 << 3),
  lb(1 << 4),
  rb(1 << 5),
  lt(1 << 6),
  rt(1 << 7),
  back(1 << 8),
  start(1 << 9),
  ls(1 << 10),
  rs(1 << 11);

  const F310Button(this.value);

  final value;
}

enum F310Hat {
  north(0),
  northEast(1),
  east(2),
  southEast(3),
  south(4),
  southWest(5),
  west(6),
  northWest(7),
  center(8);

  const F310Hat(this.value);

  final int value;
}

class F310Stick {
  int _x = 128;
  int _y = 128;

  int get x => _x;

  int get y => _y;

  set x(int v) => _x = v.clamp(0, 255);

  set y(int v) => _y = v.clamp(0, 255);

  void setPosition(int x, int y) {
    this.x = x;
    this.y = y;
  }

  void center() => setPosition(128, 128);
}

class F310Report {
  final F310Stick leftStick = F310Stick();
  final F310Stick rightStick = F310Stick();

  int _buttons = 0; // 12-bit bitmask
  F310Hat hat = F310Hat.center;

  void pressButton(F310Button btn) => _buttons |= btn.value;

  void releaseButton(F310Button btn) => _buttons &= ~btn.value;

  bool getButton(F310Button btn) => _buttons.bitFlag(btn.index);

  void pressButtons(List<F310Button> btns) => _buttons |= btns.toBitmask();

  void releaseButtons(List<F310Button> btns) => _buttons &= ~btns.toBitmask();

  void releaseAllButtons() => _buttons = 0;

  void reset() {
    _buttons = 0;
    hat = F310Hat.center;
    leftStick.center();
    rightStick.center();
  }

  Uint8List toBytes() {
    final btnLow = _buttons.bitMask(0, 8);
    final btnHigh = _buttons.bitMask(8, 4);

    // Hat occupies the lower nibble; upper nibble is constant (padding = 0).
    final hatByte = hat.value & 0x0F;

    return .fromList([
      leftStick.x, // byte 0 – Left X
      leftStick.y, // byte 1 – Left Y
      rightStick.x, // byte 2 – Right X  (Z axis)
      rightStick.y, // byte 3 – Right Y  (Rz axis)
      btnLow, // byte 4 – buttons 1-8
      btnHigh, // byte 5 – buttons 9-12 + padding
      hatByte, // byte 6 – hat + padding
    ]);
  }
}

class LogitechF310 extends HIDFunctionFs {
  LogitechF310()
    : super(
        name: 'f310',
        reportDescriptor: .fromList([
          0x05, 0x01, // Usage Page (Generic Desktop)
          0x09, 0x04, // Usage (Joystick)
          0xA1, 0x01, // Collection (Application)
          // Left Stick X & Y
          0x09, 0x01, //   Usage (Pointer)
          0xA1, 0x00, //   Collection (Physical)
          0x09, 0x30, //     Usage (X)
          0x09, 0x31, //     Usage (Y)
          0x15, 0x00, //     Logical Minimum (0)
          0x26, 0xFF, 0x00, //     Logical Maximum (255)
          0x35, 0x00, //     Physical Minimum (0)
          0x46, 0xFF, 0x00, //     Physical Maximum (255)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x02, //     Report Count (2)
          0x81, 0x02, //     Input (Data, Variable, Absolute)
          0xC0, //   End Collection
          // Right Stick X (Z) & Y (Rz)
          0x09, 0x01, //   Usage (Pointer)
          0xA1, 0x00, //   Collection (Physical)
          0x09, 0x32, //     Usage (Z)
          0x09, 0x35, //     Usage (Rz)
          0x15, 0x00, //     Logical Minimum (0)
          0x26, 0xFF, 0x00, //     Logical Maximum (255)
          0x35, 0x00, //     Physical Minimum (0)
          0x46, 0xFF, 0x00, //     Physical Maximum (255)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x02, //     Report Count (2)
          0x81, 0x02, //     Input (Data, Variable, Absolute)
          0xC0, //   End Collection
          // 12 Buttons
          0x05, 0x09, //   Usage Page (Button)
          0x19, 0x01, //   Usage Minimum (Button 1)
          0x29, 0x0C, //   Usage Maximum (Button 12)
          0x15, 0x00, //   Logical Minimum (0)
          0x25, 0x01, //   Logical Maximum (1)
          0x75, 0x01, //   Report Size (1)
          0x95, 0x0C, //   Report Count (12)
          0x81, 0x02, //   Input (Data, Variable, Absolute)
          // 4-bit padding
          0x75, 0x01, //   Report Size (1)
          0x95, 0x04, //   Report Count (4)
          0x81, 0x01, //   Input (Constant)
          // Hat Switch (D-pad)
          0x05, 0x01, //   Usage Page (Generic Desktop)
          0x09, 0x39, //   Usage (Hat Switch)
          0x15, 0x00, //   Logical Minimum (0)
          0x25, 0x07, //   Logical Maximum (7)
          0x35, 0x00, //   Physical Minimum (0)
          0x46, 0x3B, 0x01, //   Physical Maximum (315)
          0x65, 0x14, //   Unit (Eng Rot : Angular Pos)
          0x75, 0x04, //   Report Size (4)
          0x95, 0x01, //   Report Count (1)
          0x81, 0x42, //   Input (Data, Variable, Absolute, Null State)
          // 4-bit padding
          0x75, 0x04, //   Report Size (4)
          0x95, 0x01, //   Report Count (1)
          0x81, 0x01, //   Input (Constant)
          0xC0, // End Collection
        ]),
        subclass: 0,
        protocol: 0,
        config: const .inputOnly(
          maxPacketSize: 7,
          reportInterval: .new(milliseconds: 10),
        ),
        speeds: {.fullSpeed, .highSpeed},
        strings: {
          .enUS: ['Logitech Dual Action'],
        },
      );

  final F310Report report = F310Report();

  int _frame = 0;
  Timer? _timer;

  @override
  Future<void> onEnable() async {
    super.onEnable();
    _timer = .periodic(config.reportInterval, (_) {
      _animateFrame();
      epIn.write(report.toBytes());
    });
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    _timer?.cancel();
    _timer = null;
    await super.release();
  }

  void _animateFrame() {
    _frame++;
    final t = _frame * config.reportInterval.inMilliseconds / 1000.0;

    // Left stick: slow clockwise circle
    final la = t * pi;
    report.leftStick.setPosition(
      (128 + 110 * cos(la)).round(),
      (128 + 110 * sin(la)).round(),
    );

    // Right stick: Lissajous figure-8
    final ra = t * 1.5 * pi;
    report.rightStick.setPosition(
      (128 + 90 * cos(ra)).round(),
      (128 + 90 * sin(2 * ra)).round(),
    );

    // D-pad: step through all 8 directions then centre (~0.75 s each)
    final hatPhase = (t / 0.75).floor() % 9;
    report.hat = F310Hat.values[hatPhase];

    // Buttons: press one at a time, advancing every 30 frames (~0.3 s)
    // report.releaseAllButtons();
    // final btnIdx = (_frame ~/ 30) % F310Button.values.length;
    // report.pressButton(F310Button.values[btnIdx]);
  }
}

Future<void> main() async {
  final gamepad = LogitechF310();
  final gadget = Gadget(
    name: 'logitech_f310',
    id: Id(vendor: 0x046D, product: 0xC216),
    class_: .interfaceSpecific(),
    strings: const {
      .enUS: .new(
        manufacturer: 'Logitech',
        product: 'Logitech Dual Action',
        serialnumber: 'DA000001',
      ),
    },
    configs: [
      .new(
        selfPowered: true,
        remoteWakeup: true,
        maxPower: .new(100),
        strings: const {.enUS: 'Logitech Dual Action Configuration'},
        functions: [gamepad],
      ),
    ],
  );

  final reg = await gadget.register();
  try {
    await reg.bind(defaultUDC);
    stdout.writeln(
      'Logitech F310 (DirectInput) gadget active. Press Ctrl+C to stop.',
    );
    await ProcessSignal.sigint.watch().first;
  } finally {
    await reg.bind(null);
    await reg.remove();
  }
}

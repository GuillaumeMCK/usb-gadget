import 'dart:async';
import 'dart:io' show pid;
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

import '../../common.dart';

const kVid = 0x1d6b;
const kPid = 0x0104;

const kBmVendorOut = 0x40; // host-to-device, vendor, device
const kBmVendorIn = 0xC0; // device-to-host, vendor, device

const kReqEcho = 0x01; // OUT stores payload; IN returns it
const kReqStall = 0x02; // always STALLs regardless of direction

class EchoFunction extends FunctionFs {
  EchoFunction()
    : super(
        name: 'echo',
        interfaces: [
          FunctionFsInterface(
            class_: .interfaceSpecific(),
            interfaceNumber: .interface0,
            endpoints: [
              const EndpointDescriptor(address: .in_(.ep1), config: .bulk()),
              const EndpointDescriptor(address: .out(.ep2), config: .bulk()),
            ],
          ),
        ],
        strings: {
          .enUS: ['Echo Function'],
        },
        speeds: {.fullSpeed, .highSpeed},
      );

  late final EndpointInFile epIn = getEndpoint<EndpointInFile>(.ep1);
  late final EndpointOutFile epOut = getEndpoint<EndpointOutFile>(.ep2);

  StreamSubscription<Uint8List>? _sub;
  Uint8List _store = Uint8List(0);

  @override
  void onEnable() {
    super.onEnable();
    _sub?.cancel();
    _sub = epOut.stream.listen(_relay, cancelOnError: false);
  }

  void _relay(Uint8List data) {
    if (state != .enabled) return;
    epIn.write(data.isEmpty ? Uint8List(0) : data);
  }

  @override
  void onDisable() {
    _sub?.cancel();
    _sub = null;
    super.onDisable();
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    _sub?.cancel();
    _sub = null;
    await super.release();
  }

  @override
  void onSetup(
    int bmRequestType,
    int bRequest,
    int wValue,
    int wIndex,
    int wLength,
  ) {
    // Vendor OUT echo: read the payload synchronously from EP0 and store it.
    if (bmRequestType == kBmVendorOut && bRequest == kReqEcho) {
      _store = ep0.read(wLength);
      ep0.ack();
      return;
    }

    // Vendor IN echo: return the stored payload, truncated to wLength.
    if (bmRequestType == kBmVendorIn && bRequest == kReqEcho) {
      ep0.write(
        _store.length > wLength
            ? Uint8List.sublistView(_store, 0, wLength)
            : _store,
      );
      return;
    }

    // Explicit STALL bRequest — covers both directions.
    if (bRequest == kReqStall) {
      ep0.halt();
      return;
    }

    // Fall through to standard request handler (unknown vendor → STALL).
    super.onSetup(bmRequestType, bRequest, wValue, wIndex, wLength);
  }
}

class StallFunction extends EchoFunction {
  @override
  void onSetup(
    int bmRequestType,
    int bRequest,
    int wValue,
    int wIndex,
    int wLength,
  ) => ep0.halt();
}

class ImplicitDropFunction extends EchoFunction {
  @override
  void onSetup(
    int bmRequestType,
    int bRequest,
    int wValue,
    int wIndex,
    int wLength,
  ) {
    // Intentionally no-op.
  }
}

Future<RegGadget> _activateGadget(FunctionFs fn) async {
  final gadgetName = 'echo_gadget_${pid}';

  final gadget = Gadget(
    name: gadgetName,
    id: Id(vendor: kVid, product: kPid),
    configs: [
      Config(functions: [fn]),
    ],
  );

  final reg = await gadget.register();
  await reg.bind(testUDC);

  await reg.udc!.awaitState(.configured);
  await fn.awaitState(.enabled);

  return reg;
}

Future<RegGadget> buildEchoGadget() => _activateGadget(EchoFunction());

Future<void> teardownGadget(RegGadget reg) async {
  await reg.bind(null);
  try {
    await reg.remove();
  } catch (_) {}
}

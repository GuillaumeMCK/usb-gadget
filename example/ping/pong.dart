import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

class PongFunction extends FunctionFs {
  PongFunction()
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
          .enUS: ['Pong Function'],
        },
        speeds: {.fullSpeed, .highSpeed},
      );

  late final EndpointInFile epIn = getEndpoint<EndpointInFile>(.ep1);
  late final EndpointOutFile epOut = getEndpoint<EndpointOutFile>(.ep2);

  StreamSubscription<Uint8List>? _dataSub;

  @override
  Future<void> onEnable() async {
    super.onEnable();
    _dataSub ??= epOut.stream.listen(_onData);
  }

  @override
  Future<void> onDisable() async {
    await release(partial: true);
    super.onDisable();
  }

  @override
  Future<void> release({bool partial = false}) async {
    if (isReleased) return;
    await _dataSub?.cancel();
    _dataSub = null;
    if (partial) return;
    await super.release();
  }

  Future<void> _onData(Uint8List data) async {
    if (state != .enabled) return;
    epIn.write(data);
  }
}

Future<void> main() async {
  final gadget = Gadget(
    name: 'echo_gadget',
    id: Id(vendor: 0x1d6b, product: 0x0104),
    strings: {
      .enUS: const .new(
        manufacturer: 'Dart USB',
        product: 'Pong Device',
        serialnumber: '123456',
      ),
    },
    configs: [
      .new(functions: [PongFunction()]),
    ],
  );

  final reg = await gadget.register();
  try {
    await reg.bind(defaultUDC);
    await reg.udc?.awaitState(.configured);
    stdout.writeln('Pong Device ready. Press Ctrl+C to exit.');
    await ProcessSignal.sigint.watch().first;
  } finally {
    await reg.bind(null);
    await reg.remove();
  }
}

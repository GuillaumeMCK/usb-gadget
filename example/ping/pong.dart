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

  late final epIn = getEndpoint<EndpointInFile>(.ep1);

  late final epOut = getEndpoint<EndpointOutFile>(.ep2);

  StreamSubscription<Uint8List>? _dataSubscription;

  @override
  Future<void> onEnable() async {
    super.onEnable();
    _dataSubscription = epOut.stream.listen((data) {
      log?.debug('Received data:\n${data.xxd()}');
      if (state == .enabled) epIn.write(data);
    }, cancelOnError: false);
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await super.release();
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

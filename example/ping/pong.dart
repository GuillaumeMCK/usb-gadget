import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

class PongFunction extends FunctionFs {
  PongFunction()
    : super(
        name: 'echo',
        descriptors: [
          const USBInterfaceDescriptor(
            interfaceNumber: .interface0,
            numEndpoints: .two,
            interfaceClass: .vendorSpecific,
          ),
          const EndpointTemplate(
            address: EndpointAddress.in_(.ep1),
            config: EndpointConfig.bulk(),
          ),
          const EndpointTemplate(
            address: EndpointAddress.out(.ep2),
            config: EndpointConfig.bulk(),
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
    await waitUSBDeviceState(.configured);
    _dataSubscription = epOut.stream().listen((data) {
      stdout.writeln('Received data:');
      log?.debug(data.xxd());
      epIn.write(data);
    }, cancelOnError: false);
  }

  @override
  Future<void> dispose() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await super.dispose();
  }
}

Future<void> main() async {
  final gadget = Gadget(
    name: 'echo_gadget',
    idVendor: 0x1d6b,
    idProduct: 0x0104,
    strings: {
      .enUS: const .new(
        manufacturer: 'Dart USB',
        product: 'Pong Device',
        serialnumber: '123456',
      ),
    },
    config: .new(
      functions: [PongFunction()],
      attributes: .busPowered,
      strings: {.enUS: 'Pong Configuration'},
    ),
  );

  try {
    await gadget.bind();
    stdout.writeln('Pong Device ready. Press Ctrl+C to exit.');
    await ProcessSignal.sigint.watch().first;
  } finally {
    await gadget.unbind();
  }
}

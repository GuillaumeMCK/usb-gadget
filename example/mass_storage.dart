import 'dart:async';
import 'dart:io';

import 'package:usb_gadget/usb_gadget.dart';

Future<void> main(List<String> args) async {
  String? udc;
  List<String> paths = const [];

  switch (args) {
    case ['--help', ...] || ['-h', ...]:
      stdout.writeln(
        'Usage: dart mass_storage.dart [--udc UDC_NAME] LUN_FILE [LUN_FILE ...]\n',
      );
      exit(0);
    case ['--udc', final String udcName, ...final sources]:
      udc = udcName;
      paths = sources;
    case [...final files]:
      paths = [
        for (final file in files)
          if (File(file).existsSync() || Directory(file).existsSync()) file,
      ];
  }

  if (paths.isEmpty) {
    stderr.writeln(
      'Error: At least one LUN file or directory must be specified.',
    );
    exit(1);
  }

  final gadget = Gadget(
    name: 'mass_storage_gadget',
    idVendor: 0x1d6b,
    idProduct: 0x0104,
    deviceClass: .composite,
    deviceSubClass: .none,
    deviceProtocol: .none,
    udc: udc,
    strings: {
      .enUS: const .new(
        manufacturer: 'Evil Corp',
        product: 'USB Mass Storage Gadget',
        serialnumber: 'MSD123456',
      ),
    },
    config: .new(
      maxPower: .fromMilliAmps(500),
      attributes: .busPowered,
      functions: [
        MassStorageFunction(
          name: 'storage',
          luns: [...paths.map((p) => .new(path: p, removable: true))],
        ),
      ],
      strings: const {.enUS: 'Mass Storage Configuration'},
    ),
  );

  try {
    await gadget.bind();
    stdout.writeln('Ctrl+C to exit.');
    await ProcessSignal.sigint.watch().first;
  } finally {
    gadget.unbind();
  }
}

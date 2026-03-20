import 'dart:async';
import 'dart:io';

import 'package:usb_gadget/usb_gadget.dart';

Future<void> main(List<String> args) async {
  UDC? udc;
  List<String> paths = const [];

  switch (args) {
    case ['--help', ...] || ['-h', ...]:
      stdout.writeln(
        'Usage: dart mass_storage.dart [--udc UDC_NAME] LUN_FILE [LUN_FILE ...]\n',
      );
      exit(0);
    case ['--udc', final String name, ...final sources]:
      udc = .fromName(name);
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
    id: .new(vendor: 0x1d6b, product: 0x0104),
    class_: .interfaceSpecific(),
    strings: {
      .enUS: const .new(
        manufacturer: 'Evil Corp',
        product: 'USB Mass Storage Gadget',
        serialnumber: 'MSD123456',
      ),
    },
    configs: [
      .new(
        description: 'Mass Storage Configuration',
        maxPower: const MaxPower(500),
        functions: [
          MassStorageFunction(
            name: 'storage',
            luns: [...paths.map((p) => .new(path: p, removable: true))],
          ),
        ],
      ),
    ],
  );
  final reg = await gadget.register();
  try {
    await reg.bind(udc ?? defaultUDC);
    stdout.writeln('Ctrl+C to exit.');
    await ProcessSignal.sigint.watch().first;
  } finally {
    reg.remove();
  }
}

import 'dart:io';

import 'package:args/command_runner.dart';

import '../exceptions.dart';
import '../output.dart';
import '../parser.dart';

class CheckCommand extends Command<void> {
  @override
  String get name => 'check';

  @override
  String get description => 'Validate YAML spec(s) without touching hardware.';

  @override
  String get invocation => 'usb-gadget check <gadget.yaml> [...]';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('check requires at least one YAML file path');
    }

    var ok = true;
    for (final path in argResults!.rest) {
      try {
        final (gadget, _) = await parseGadgetSpec(path);
        final fnNames = gadget.configs
            .expand((c) => c.functions)
            .map((f) => f.configfsName)
            .join(', ');
        print(
          '${Fmt.badge('OK')}  $path → ${Fmt.bold(gadget.name ?? '(auto)')}  [$fnNames]',
        );
      } on ConfigException catch (e) {
        print('${Fmt.badge('FAIL', ok: false)}  $path: $e');
        ok = false;
      }
    }

    if (!ok) exit(1);
  }
}

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:usb_gadget/usb_gadget.dart';

import '../exceptions.dart';
import '../output.dart';
import '../parser.dart';

class UpCommand extends Command<void> {
  UpCommand() {
    argParser.addOption(
      'udc',
      abbr: 'u',
      help: 'UDC to bind to (auto-detected if omitted)',
      valueHelp: 'name',
    );
  }

  @override
  String get name => 'up';

  @override
  String get description => 'Register and bind a gadget from a YAML spec.';

  @override
  String get invocation => 'usb-gadget up <gadget.yaml> [--udc <name>]';

  @override
  Future<void> run() async {
    if (argResults!.rest.length != 1) {
      usageException('up requires exactly one YAML file path');
    }

    final (gadget, specUdc) = await parseGadgetSpec(argResults!.rest.first);
    final udcObj = _resolveUdc(argResults!['udc'] as String? ?? specUdc);

    RegGadget reg;
    try {
      reg = await gadget.register();
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == eexist) {
        // A stale configfs entry exists from a previous run (configfs mkdir is
        // idempotent so createSync() didn't throw). Tear it down and retry once.
        final stale = RegGadget.all()
            .where((g) => g.name == gadget.name)
            .firstOrNull;
        if (stale == null) {
          throw GadgetException(
            "gadget '${gadget.name}' already exists but could not be found — "
            "run 'usb-gadget down ${gadget.name}' manually",
          );
        }
        try {
          await stale.remove();
        } catch (err) {
          throw GadgetException(
            "gadget '${gadget.name}' already exists and teardown failed: $err — "
            "run 'usb-gadget down ${gadget.name}' manually",
          );
        }
        try {
          reg = await gadget.register();
        } on FileSystemException catch (e2) {
          throw GadgetException(
            'register failed after stale teardown: ${e2.message}',
          );
        }
      } else {
        throw GadgetException('register failed: ${e.message}');
      }
    }

    try {
      await reg.bind(udcObj);
    } catch (err) {
      await reg.remove();
      throw GadgetException('bind failed: $err');
    }

    final fnCount = reg.functions().length;
    print(
      '${Fmt.badge('UP')}  ${Fmt.bold(reg.name)} '
      '→ ${Fmt.cyan(udcObj.name)} '
      '($fnCount function${fnCount == 1 ? '' : 's'})',
    );
  }
}

UDC _resolveUdc(String? name) {
  if (name != null) return UDC.fromName(name);
  if (!hasUDC) {
    throw GadgetException(
      'no UDC found — is the USB gadget kernel module loaded?',
    );
  }
  return defaultUDC;
}

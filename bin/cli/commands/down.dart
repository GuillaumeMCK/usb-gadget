import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:usb_gadget/usb_gadget.dart';

import '../exceptions.dart';
import '../output.dart';

class DownCommand extends Command<void> {
  DownCommand() {
    argParser.addFlag(
      'all',
      abbr: 'a',
      negatable: false,
      help: 'Remove all registered gadgets',
    );
  }

  @override
  String get name => 'down';

  @override
  String get description => 'Unbind and remove one or more registered gadgets.';

  @override
  String get invocation => 'usb-gadget down (<n>... | --all)';

  @override
  Future<void> run() async {
    final all = argResults!['all'] as bool;
    final names = argResults!.rest;

    if (all && names.isNotEmpty) {
      usageException('--all and explicit names are mutually exclusive');
    }
    if (!all && names.isEmpty) {
      usageException("specify gadget name(s) or '--all'");
    }

    final targets = all
        ? RegGadget.all()
        : names.map((n) {
            final reg = RegGadget.all().firstWhere(
              (g) => g.name == n,
              orElse: () => throw GadgetException("gadget '$n' not found"),
            );
            return reg;
          }).toList();

    if (targets.isEmpty) {
      print('no gadgets to remove');
      return;
    }

    for (final reg in targets) {
      try {
        await reg.remove();
        print(
          "${Fmt.badge('DOWN', ok: false)}  removed '${Fmt.bold(reg.name)}'",
        );
      } catch (e) {
        stderr.writeln('${Fmt.warn}could not remove ${reg.name}: $e');
      }
    }
  }
}

import 'dart:io';

import 'package:args/command_runner.dart';

import 'cli/exceptions.dart';
import 'cli/commands/commands.dart';

const _version = '0.1.0';

Future<void> main(List<String> args) async {
  // Intercept --version/-v before CommandRunner consumes the args.
  if (args.contains('--version') || args.contains('-v')) {
    print('usb-gadget $_version');
    return;
  }

  final runner =
      CommandRunner<void>(
          'usb-gadget',
          'Manage Linux USB gadgets from YAML configuration files.',
        )
        ..addCommand(UpCommand())
        ..addCommand(DownCommand())
        ..addCommand(ListCommand())
        ..addCommand(CheckCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln('\x1B[91merror:\x1B[0m ${e.message}\n');
    stderr.writeln(e.usage);
    exit(64);
  } on GadgetException catch (e) {
    stderr.writeln('\x1B[91merror:\x1B[0m ${e.message}');
    exit(1);
  } on ConfigException catch (e) {
    stderr.writeln('\x1B[91merror:\x1B[0m ${e.message}');
    exit(1);
  } catch (err, st) {
    stderr.writeln('\x1B[91merror:\x1B[0m $err\n$st');
    exit(1);
  }
}

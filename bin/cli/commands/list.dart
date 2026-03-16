import 'package:args/command_runner.dart';
import 'package:usb_gadget/usb_gadget.dart';

import '../output.dart';

class ListCommand extends Command<void> {
  @override
  String get name => 'list';

  @override
  String get description => 'Show all registered gadgets and their status.';

  @override
  Future<void> run() async {
    final all = RegGadget.all();
    if (all.isEmpty) {
      print('no gadgets registered');
      return;
    }

    printTable(
      ['NAME', 'STATUS', 'FUNCTIONS'],
      [
        for (final reg in all)
          [
            reg.name,
            reg.udc != null ? Fmt.bound(reg.udc!.name) : Fmt.unbound(),
            reg.functions().map((f) => f.toString()).join(', ').ifEmpty('—'),
          ],
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

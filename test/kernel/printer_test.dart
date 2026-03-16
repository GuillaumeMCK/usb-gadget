import 'dart:io';

import 'package:test/test.dart';
import 'package:usb_gadget/usb_gadget.dart';

import '../common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  // =========================================================================
  // PrinterFunction — unit tests (no hardware)
  // =========================================================================

  group('PrinterFunction unit', () {
    test('configfsName is "printer.{name}"', () {
      expect(
        PrinterFunction(name: 'printer0').configfsName,
        'printer.printer0',
      );
    });

    test('pnpString is stored', () {
      expect(
        PrinterFunction(name: 'p', pnpString: 'A Printer').pnpString,
        'A Printer',
      );
    });

    test('queueLength is stored', () {
      expect(PrinterFunction(name: 'p', queueLength: 20).queueLength, 20);
    });

    test('pnp_string appears in attributes when set', () {
      final attrs = PrinterFunction(
        name: 'p',
        pnpString: 'Test Printer',
      ).getConfigAttributes();
      expect(attrs['pnp_string'], 'Test Printer');
    });
  });

  // =========================================================================
  // PrinterFunction — integration (requires hardware)
  // =========================================================================

  group('PrinterFunction — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      final fn = PrinterFunction(
        name: 'printer0',
        pnpString: 'Dart Printer',
        queueLength: 20,
      );
      reg = await kernelTestGadget('printer_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() async {
      try {
        await reg.remove();
      } catch (_) {}
    });

    test('gadget name is "printer_test"', () {
      expect(reg.name, 'printer_test');
    });

    test('"printer" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('printer'));
    });

    test('down succeeds', () async {
      await expectLater(reg.remove(), completes);
      expect(
        Directory('/sys/kernel/config/usb_gadget/printer_test').existsSync(),
        isFalse,
      );
    });
  });
}

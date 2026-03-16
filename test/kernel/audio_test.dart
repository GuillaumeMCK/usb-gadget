import 'package:test/test.dart';
import 'package:usb_gadget/usb_gadget.dart';

import '../common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  // =========================================================================
  // Uac1Function — unit tests (no hardware)
  // =========================================================================

  group('Uac1Function unit', () {
    test('configfsName is "uac1.{name}"', () {
      expect(Uac1Function(name: 'audio0').configfsName, 'uac1.audio0');
    });

    test('cChmask defaults to 3 (stereo)', () {
      expect(Uac1Function(name: 'audio0').cChmask, 3);
    });

    test('getConfigAttributes contains c_chmask and p_chmask', () {
      final attrs = Uac1Function(
        name: 'audio0',
        cChmask: 0x03,
        pChmask: 0x03,
      ).getConfigAttributes();
      expect(attrs['c_chmask'], '3');
      expect(attrs['p_chmask'], '3');
    });

    test('optional cSrate appears in attributes when set', () {
      final attrs = Uac1Function(
        name: 'audio0',
        cSrate: 48000,
      ).getConfigAttributes();
      expect(attrs['c_srate'], '48000');
    });
  });

  // =========================================================================
  // Uac1Function — integration (requires hardware)
  // =========================================================================

  group('Uac1Function — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      final fn = Uac1Function(
        name: 'audio0',
        cChmask: 3,
        cSrate: 48000,
        cSsize: 2,
        pChmask: 3,
        pSrate: 48000,
        pSsize: 2,
      );
      reg = await kernelTestGadget('uac1_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() => reg.remove());

    test('gadget name is "uac1_test"', () {
      expect(reg.name, 'uac1_test');
    });

    test('"uac1" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('uac1'));
    });
  });

  // =========================================================================
  // Uac2Function — unit tests (no hardware)
  // =========================================================================

  group('Uac2Function unit', () {
    test('configfsName is "uac2.{name}"', () {
      expect(Uac2Function(name: 'audio0').configfsName, 'uac2.audio0');
    });

    test('cSrate defaults to 48000', () {
      expect(Uac2Function(name: 'audio0').cSrate, 48000);
    });

    test('valid config passes validate()', () {
      expect(
        Uac2Function(
          name: 'audio0',
          cSrate: 48000,
          cSsize: 2,
          pSrate: 48000,
          pSsize: 2,
        ).validate(),
        isTrue,
      );
    });

    test('invalid cSsize fails validate()', () {
      expect(Uac2Function(name: 'audio0', cSsize: 5).validate(), isFalse);
    });

    test('invalid pSrate fails validate()', () {
      expect(Uac2Function(name: 'audio0', pSrate: 0).validate(), isFalse);
    });

    test('getConfigAttributes contains required fields', () {
      final attrs = Uac2Function(
        name: 'audio0',
        cChmask: 0xFF,
        cSrate: 48000,
        cSsize: 3,
        pChmask: 0x03,
        pSrate: 48000,
        pSsize: 2,
      ).getConfigAttributes();
      expect(attrs['c_chmask'], '255');
      expect(attrs['c_srate'], '48000');
      expect(attrs['c_ssize'], '3');
      expect(attrs['p_srate'], '48000');
      expect(attrs['p_ssize'], '2');
    });
  });

  // =========================================================================
  // Uac2Function — integration (requires hardware)
  // =========================================================================

  group('Uac2Function — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      final fn = Uac2Function(
        name: 'audio0',
        cChmask: 0xFF,
        cSrate: 48000,
        cSsize: 3,
        pChmask: 3,
        pSrate: 48000,
        pSsize: 2,
      );
      reg = await kernelTestGadget('uac2_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() => reg.remove());

    test('gadget name is "uac2_test"', () {
      expect(reg.name, 'uac2_test');
    });

    test('"uac2" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('uac2'));
    });
  });
}

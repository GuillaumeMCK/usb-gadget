import 'dart:io';

import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  group('EthernetFunction shared helpers', () {
    test('EcmFunction configfsName is "ecm.{name}"', () {
      expect(EcmFunction(name: 'usb0').configfsName, 'ecm.usb0');
    });

    test('NcmFunction configfsName is "ncm.{name}"', () {
      expect(NcmFunction(name: 'usb0').configfsName, 'ncm.usb0');
    });

    test('EemFunction configfsName is "eem.{name}"', () {
      expect(EemFunction(name: 'usb0').configfsName, 'eem.usb0');
    });

    test('EcmSubsetFunction configfsName is "geth.{name}"', () {
      expect(EcmSubsetFunction(name: 'usb0').configfsName, 'geth.usb0');
    });

    test('RndisFunction configfsName is "rndis.{name}"', () {
      expect(RndisFunction(name: 'usb0').configfsName, 'rndis.usb0');
    });

    test('valid MAC address passes isValidMacAddress()', () {
      expect(EthernetFunction.isValidMacAddress('66:f9:7d:f2:3e:2a'), isTrue);
    });

    test('null MAC address passes isValidMacAddress()', () {
      expect(EthernetFunction.isValidMacAddress(null), isTrue);
    });

    test('malformed MAC address fails isValidMacAddress()', () {
      expect(EthernetFunction.isValidMacAddress('not-a-mac'), isFalse);
    });

    test('host_addr appears in ECM attributes when provided', () {
      final attrs = EcmFunction(
        name: 'usb0',
        hostAddr: '7e:21:b2:cb:d4:51',
      ).getConfigAttributes();
      expect(attrs['host_addr'], '7e:21:b2:cb:d4:51');
    });

    test('dev_addr appears in ECM attributes when provided', () {
      final attrs = EcmFunction(
        name: 'usb0',
        devAddr: '66:f9:7d:f2:3e:2a',
      ).getConfigAttributes();
      expect(attrs['dev_addr'], '66:f9:7d:f2:3e:2a');
    });

    test(
      'RndisFunction stores wceis (written in prepare(), not attributes map)',
      () {
        final fn = RndisFunction(name: 'usb0', wceis: true);
        expect(fn.wceis, isTrue);
        expect(fn.getConfigAttributes().containsKey('wceis'), isFalse);
      },
    );
  });

  group('EcmFunction — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      final fn = EcmFunction(
        name: 'usb0',
        hostAddr: '7e:21:b2:cb:d4:51',
        devAddr: '66:f9:7d:f2:3e:2a',
      );
      reg = await kernelTestGadget('ecm_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() => reg.remove());

    test('gadget name is "ecm_test"', () {
      expect(reg.name, 'ecm_test');
    });

    test('"ecm" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('ecm'));
    });
  });

  group('NcmFunction — integration', skip: !hasUDC, () {
    RegGadget? reg;

    setUp(() async {
      final fn = NcmFunction(name: 'usb0');
      reg = await kernelTestGadget('ncm_test', fn).register();
      await reg!.bind(testUDC);
    });

    tearDown(() async {
      try {
        await reg?.remove();
      } catch (_) {}
      reg = null;
    });

    test('gadget name is "ncm_test"', () {
      expect(reg!.name, 'ncm_test');
    });

    test('"ncm" driver is present in registered functions', () {
      expect(reg!.functions().map((f) => f.driver), contains('ncm'));
    });

    test(
      'down succeeds — release() clears os_desc subgroup before rmdir',
      () async {
        await expectLater(reg!.remove(), completes);
        expect(
          Directory('/sys/kernel/config/usb_gadget/ncm_test').existsSync(),
          isFalse,
        );
      },
    );
  });

  group('EemFunction — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      final fn = EemFunction(name: 'usb0');
      reg = await kernelTestGadget('eem_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() => reg.remove());

    test('gadget name is "eem_test"', () {
      expect(reg.name, 'eem_test');
    });

    test('"eem" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('eem'));
    });
  });

  group('RndisFunction — integration', skip: !hasUDC, () {
    RegGadget? reg;

    setUp(() async {
      final fn = RndisFunction(name: 'usb0', wceis: true);
      reg = await kernelTestGadget('rndis_test', fn).register();
      await reg!.bind(testUDC);
    });

    tearDown(() async {
      try {
        await reg?.remove();
      } catch (_) {}
      reg = null;
    });

    test('gadget name is "rndis_test"', () {
      expect(reg!.name, 'rndis_test');
    });

    test('"rndis" driver is present in registered functions', () {
      expect(reg!.functions().map((f) => f.driver), contains('rndis'));
    });

    test(
      'down succeeds — release() clears os_desc subgroup before rmdir',
      () async {
        await expectLater(reg!.remove(), completes);
        expect(
          Directory('/sys/kernel/config/usb_gadget/rndis_test').existsSync(),
          isFalse,
        );
      },
    );
  });

  group('EcmSubsetFunction — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      final fn = EcmSubsetFunction(name: 'usb0');
      reg = await kernelTestGadget('ecm_subset_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() => reg.remove());

    test('gadget name is "ecm_subset_test"', () {
      expect(reg.name, 'ecm_subset_test');
    });

    test('"geth" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('geth'));
    });
  });
}

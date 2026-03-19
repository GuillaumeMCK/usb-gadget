import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  group('MassStorageFunction unit', () {
    test('configfsName is "mass_storage.{name}"', () {
      expect(
        MassStorageFunction(
          name: 'storage',
          luns: [const LunConfig()],
        ).configfsName,
        'mass_storage.storage',
      );
    });

    test('stall defaults to true', () {
      expect(
        MassStorageFunction(name: 's', luns: [const LunConfig()]).stall,
        isTrue,
      );
    });

    test('stall: false writes "0" attribute', () {
      final attrs = MassStorageFunction(
        name: 's',
        luns: [const LunConfig()],
        stall: false,
      ).getConfigAttributes();
      expect(attrs['stall'], '0');
    });

    test('empty luns fails validate()', () {
      expect(
        MassStorageFunction(name: 's', luns: const []).validate(),
        isFalse,
      );
    });
  });

  group('LunConfig unit', () {
    test('cdrom defaults to false', () {
      expect(const LunConfig().cdrom, isFalse);
    });

    test('removable defaults to false', () {
      expect(const LunConfig().removable, isFalse);
    });

    test('path stores the provided value', () {
      expect(const LunConfig(path: '/tmp/disk.img').path, '/tmp/disk.img');
    });
  });

  group('MassStorageFunction — integration', skip: !hasUDC, () {
    RegGadget? reg;

    setUp(() async {
      final fn = MassStorageFunction(
        name: 'storage',
        luns: [const LunConfig(removable: true)],
      );
      reg = await kernelTestGadget('msd_test', fn).register();
      await reg!.bind(testUDC);
    });

    tearDown(() async {
      try {
        await reg?.remove();
      } catch (_) {}
      reg = null;
    });

    test('gadget name is "msd_test"', () {
      expect(reg!.name, 'msd_test');
    });

    test('"mass_storage" driver is present in registered functions', () {
      expect(reg!.functions().map((f) => f.driver), contains('mass_storage'));
    });

    test('down succeeds (single LUN teardown)', () async {
      await expectLater(reg!.remove(), completes);
    });
  });
}

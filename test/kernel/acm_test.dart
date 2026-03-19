import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  // =========================================================================
  // AcmFunction — unit tests (no hardware)
  // =========================================================================

  group('AcmFunction unit', () {
    test('configfsName is "acm.{name}"', () {
      expect(AcmFunction(name: 'port0').configfsName, 'acm.port0');
    });

    test('type is FunctionType.kernel', () {
      expect(AcmFunction(name: 'port0').type, FunctionType.kernel);
    });

    test('console defaults to null', () {
      expect(AcmFunction(name: 'port0').console, isNull);
    });

    test('console: false is stored', () {
      expect(AcmFunction(name: 'port0', console: false).console, isFalse);
    });

    test('console: true is stored', () {
      expect(AcmFunction(name: 'port0', console: true).console, isTrue);
    });

    test(
      'console attribute is not in getConfigAttributes (written in prepare())',
      () {
        final attrs = AcmFunction(
          name: 'port0',
          console: false,
        ).getConfigAttributes();
        // console is written directly in prepare() with best-effort error handling
        // to match kernels where the attribute is read-only. It is not in the
        // attributes map.
        expect(attrs.containsKey('console'), isFalse);
      },
    );
  });

  // =========================================================================
  // AcmFunction — integration (requires hardware)
  // =========================================================================

  group('AcmFunction — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      // console attribute is read-only on some kernels (open() returns EPERM
      // before any write). Omit it so prepare() doesn't attempt to write it.
      final fn = AcmFunction(name: 'port0');
      reg = await kernelTestGadget('acm_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() => reg.remove());

    test('gadget name is "acm_test"', () {
      expect(reg.name, 'acm_test');
    });

    test('"acm" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('acm'));
    });
  });
}

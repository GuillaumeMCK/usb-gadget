import 'dart:io';

import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  group('LoopbackFunction unit', () {
    test('configfsName is "Loopback.{name}"', () {
      expect(LoopbackFunction(name: 'loop0').configfsName, 'Loopback.loop0');
    });

    test('qlen defaults to 32', () {
      expect(LoopbackFunction(name: 'loop0').qlen, 32);
    });

    test('getConfigAttributes maps to kernel attribute names', () {
      final attrs = LoopbackFunction(
        name: 'loop0',
        qlen: 16,
        buflen: 2048,
      ).getConfigAttributes();
      expect(attrs['qlen'], '16');
      expect(attrs['bulk_buflen'], '2048');
    });

    test('qlen > 1000 fails validate()', () {
      expect(LoopbackFunction(name: 'loop0', qlen: 1001).validate(), isFalse);
    });
  });

  group('LoopbackFunction — integration', skip: !hasUDC, () {
    RegGadget? reg;

    setUp(() async {
      final fn = LoopbackFunction(name: 'loop0');
      try {
        reg = await kernelTestGadget('loopback_test', fn).register();
      } on PathNotFoundException {
        // functions/loopback.loop0 mkdir returned ENOENT: the loopback
        // function driver is not available on this kernel.
        markTestSkipped('loopback kernel module not available');
        return;
      }
      await reg!.bind(testUDC);
    });

    tearDown(() async {
      try {
        await reg?.remove();
      } catch (_) {}
      reg = null;
    });

    test('gadget name is "loopback_test"', () {
      expect(reg!.name, 'loopback_test');
    });

    test('"Loopback" driver is present in registered functions', () {
      expect(reg!.functions().map((f) => f.driver), contains('Loopback'));
    });
  });

  group('SourceSinkFunction unit', () {
    test('configfsName is "SourceSink.{name}"', () {
      expect(SourceSinkFunction(name: 'ss0').configfsName, 'SourceSink.ss0');
    });

    test('pattern defaults to 0', () {
      expect(SourceSinkFunction(name: 'ss0').pattern, 0);
    });

    test('invalid pattern fails validate()', () {
      expect(SourceSinkFunction(name: 'ss0', pattern: 3).validate(), isFalse);
    });

    test('getConfigAttributes contains pattern', () {
      final attrs = SourceSinkFunction(
        name: 'ss0',
        pattern: 1,
      ).getConfigAttributes();
      expect(attrs['pattern'], '1');
    });
  });

  group('SourceSinkFunction — integration', skip: !hasUDC, () {
    RegGadget? reg;

    setUp(() async {
      final fn = SourceSinkFunction(name: 'ss0');
      try {
        reg = await kernelTestGadget('sourcesink_test', fn).register();
      } on PathNotFoundException {
        // functions/sourcesink.ss0 mkdir returned ENOENT: the sourcesink
        // function driver is not available on this kernel.
        markTestSkipped('sourcesink kernel module not available');
        return;
      }
      await reg!.bind(testUDC);
    });

    tearDown(() async {
      try {
        await reg?.remove();
      } catch (_) {}
      reg = null;
    });

    test('gadget name is "sourcesink_test"', () {
      expect(reg!.name, 'sourcesink_test');
    });

    test('"SourceSink" driver is present in registered functions', () {
      expect(reg!.functions().map((f) => f.driver), contains('SourceSink'));
    });
  });
}

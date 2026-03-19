import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  group('KernelFunctionType.toString()', () {
    const cases = {
      KernelFunctionType.massStorage: 'mass_storage',
      KernelFunctionType.acm: 'acm',
      KernelFunctionType.serial: 'gser',
      KernelFunctionType.ecm: 'ecm',
      KernelFunctionType.ecmSubset: 'geth',
      KernelFunctionType.eem: 'eem',
      KernelFunctionType.ncm: 'ncm',
      KernelFunctionType.rndis: 'rndis',
      KernelFunctionType.hid: 'hid',
      KernelFunctionType.midi: 'midi',
      KernelFunctionType.uac1: 'uac1',
      KernelFunctionType.uac2: 'uac2',
      KernelFunctionType.uvc: 'uvc',
      KernelFunctionType.printer: 'printer',
      KernelFunctionType.loopback: 'Loopback',
      KernelFunctionType.sourceSink: 'SourceSink',
    };

    for (final entry in cases.entries) {
      test('${entry.key.name} → "${entry.value}"', () {
        expect(entry.key.toString(), entry.value);
      });
    }
  });

  group('KernelFunction base', () {
    test('type is FunctionType.kernel', () {
      expect(
        MinimalKernelFn(name: 'x', kernelType: .loopback).type,
        FunctionType.kernel,
      );
    });

    test('configfsName is "{kernelType}.{name}"', () {
      expect(
        MinimalKernelFn(name: 'usb0', kernelType: .ecm).configfsName,
        'ecm.usb0',
      );
    });

    test('prepared is false before prepare()', () {
      expect(MinimalKernelFn(name: 'x', kernelType: .acm).prepared, isFalse);
    });

    test('prepare() throws StateError when called a second time', () async {
      final fn = MinimalKernelFn(name: 'x', kernelType: .acm);
      fn.prepare('/any/path');
      expect(() => fn.prepare('/any/path'), throwsA(isA<StateError>()));
    });

    test('awaitState() returns immediately for kernel functions', () async {
      await expectLater(
        MinimalKernelFn(
          name: 'x',
          kernelType: .loopback,
        ).awaitState(FunctionFsState.ready),
        completes,
      );
    });

    test('release() completes when not prepared', () async {
      await expectLater(
        MinimalKernelFn(name: 'x', kernelType: .loopback).release(),
        completes,
      );
    });

    test('release() is idempotent', () async {
      final fn = MinimalKernelFn(name: 'x', kernelType: .loopback);
      await fn.release();
      await expectLater(fn.release(), completes);
    });
  });
}

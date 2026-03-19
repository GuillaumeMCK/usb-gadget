import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  group('HIDFunction (kernel) unit', () {
    final desc = [0x05, 0x01, 0x09, 0x06];

    test('configfsName is "hid.{name}"', () {
      expect(
        HIDFunction(name: 'usb0', descriptor: desc).configfsName,
        'hid.usb0',
      );
    });

    test('type is FunctionType.kernel', () {
      expect(
        HIDFunction(name: 'usb0', descriptor: desc).type,
        FunctionType.kernel,
      );
    });

    test('protocol defaults to 0x00', () {
      expect(HIDFunction(name: 'usb0', descriptor: desc).protocol, 0x00);
    });

    test('subClass defaults to 0x00', () {
      expect(HIDFunction(name: 'usb0', descriptor: desc).subClass, 0x00);
    });

    test('empty descriptor fails validate()', () {
      expect(
        HIDFunction(name: 'usb0', descriptor: const []).validate(),
        isFalse,
      );
    });

    test('reportLength > 1024 fails validate()', () {
      expect(
        HIDFunction(
          name: 'usb0',
          descriptor: desc,
          reportLength: 1025,
        ).validate(),
        isFalse,
      );
    });

    test('getConfigAttributes includes protocol, subclass, report_length', () {
      final attrs = HIDFunction(
        name: 'usb0',
        descriptor: desc,
        protocol: 2,
        subClass: 1,
        reportLength: 8,
      ).getConfigAttributes();
      expect(attrs['protocol'], '2');
      expect(attrs['subclass'], '1');
      expect(attrs['report_length'], '8');
    });

    test('noOutEndpoint: true writes "1" attribute', () {
      final attrs = HIDFunction(
        name: 'usb0',
        descriptor: desc,
        noOutEndpoint: true,
      ).getConfigAttributes();
      expect(attrs['no_out_endpoint'], '1');
    });
  });
}

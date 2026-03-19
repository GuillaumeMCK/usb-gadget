import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  group('MidiFunction unit', () {
    test('configfsName is "midi.{name}"', () {
      expect(MidiFunction(name: 'midi0').configfsName, 'midi.midi0');
    });

    test('id defaults to "usb-midi"', () {
      expect(MidiFunction(name: 'midi0').id, 'usb-midi');
    });

    test('inPorts and outPorts are stored', () {
      final fn = MidiFunction(name: 'midi0', inPorts: 2, outPorts: 3);
      expect(fn.inPorts, 2);
      expect(fn.outPorts, 3);
    });

    test('getConfigAttributes includes in_ports and out_ports', () {
      final attrs = MidiFunction(
        name: 'midi0',
        inPorts: 2,
        outPorts: 3,
      ).getConfigAttributes();
      expect(attrs['in_ports'], '2');
      expect(attrs['out_ports'], '3');
    });

    test('invalid inPorts > 16 fails validate()', () {
      expect(MidiFunction(name: 'm', inPorts: 17).validate(), isFalse);
    });

    test('invalid outPorts < 0 fails validate()', () {
      expect(MidiFunction(name: 'm', outPorts: -1).validate(), isFalse);
    });
  });

  group('MidiFunction — integration', skip: !hasUDC, () {
    late RegGadget reg;

    setUp(() async {
      final fn = MidiFunction(
        name: 'midi0',
        id: 'midi',
        inPorts: 2,
        outPorts: 3,
      );
      reg = await kernelTestGadget('midi_test', fn).register();
      await reg.bind(testUDC);
    });

    tearDown(() => reg.remove());

    test('gadget name is "midi_test"', () {
      expect(reg.name, 'midi_test');
    });

    test('"midi" driver is present in registered functions', () {
      expect(reg.functions().map((f) => f.driver), contains('midi'));
    });
  });
}

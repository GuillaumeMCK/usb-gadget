import 'package:test/test.dart';

import 'common.dart';

const _epOut = 0x02;
const _epIn = 0x81;

void main() {
  withEchoGadget('Endpoint halt', (pair) {
    test('SET/CLEAR_FEATURE(HALT) on EP_OUT', () async {
      final host = pair().host;
      final payload = Uint8List.fromList('hello'.codeUnits);

      expect(await host.getHalted(_epOut), isFalse);
      expect(await host.echo(payload), equals(payload));

      await host.setHalt(_epOut);
      expect(await host.getHalted(_epOut), isTrue);
      await expectLater(
        host.write(_epOut, payload),
        throwsA(isA<UsbHostError>()),
      );

      await host.clearHalt(_epOut);
      expect(await host.getHalted(_epOut), isFalse);
      expect(await host.echo(payload), equals(payload));
    });

    test('SET/CLEAR_FEATURE(HALT) on EP_IN', () async {
      final host = pair().host;
      final payload = Uint8List.fromList('recover'.codeUnits);

      expect(await host.getHalted(_epIn), isFalse);

      await host.setHalt(_epIn);
      expect(await host.getHalted(_epIn), isTrue);
      await expectLater(
        host.read(_epIn, size: host.maxPacketSize),
        throwsA(isA<UsbHostError>()),
      );

      await host.clearHalt(_epIn);
      expect(await host.getHalted(_epIn), isFalse);
      expect(await host.echo(payload), equals(payload));
    });
  });
}

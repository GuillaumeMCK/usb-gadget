import 'package:test/test.dart';

import 'common.dart';

const _epOut = 0x02;
const _epIn = 0x81;

void main() {
  withEchoGadget('ZLP handling', (pair) {
    test('MPS-aligned packet then ZLP: two distinct IN transfers', () async {
      final host = pair().host;
      final payload = mpsAlignedPayload(1, host.maxPacketSize);

      expect(await host.echo(payload), equals(payload));
      expect(await host.echo(Uint8List(0)), equals(Uint8List(0)));
    });

    test('data + ZLP queued: two ordered IN completions', () async {
      final host = pair().host;
      final mps = host.maxPacketSize;
      final payload = Uint8List.fromList(
        List.generate(mps ~/ 2, (i) => i % 256),
      );

      await host.write(_epOut, payload);
      await host.write(_epOut, Uint8List(0));

      expect(await host.read(_epIn, size: mps), equals(payload));
      expect(await host.read(_epIn, size: mps), equals(Uint8List(0)));
    });
  });
}

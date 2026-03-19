import 'package:test/test.dart';

import 'common.dart';

void main() {
  withEchoGadget('Bulk transfers', (pair) {
    test('basic loopback', () async {
      final host = pair().host;
      final payload = Uint8List.fromList('Hello USB!'.codeUnits);

      expect(await host.echo(payload), equals(payload));
    });

    test('MPS-aligned HS: 16 × 512 B', () async {
      final payload = mpsAlignedPayload(16, 512);
      expect(await pair().host.echo(payload, pktSize: 512), equals(payload));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('MPS-aligned FS: 64 × 64 B', () async {
      final payload = mpsAlignedPayload(64, 64);
      expect(await pair().host.echo(payload, pktSize: 64), equals(payload));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('short tail: 3 × MPS + 37 B', () async {
      final host = pair().host;
      final mps = host.maxPacketSize;
      final payload = Uint8List(3 * mps + 37)
        ..setAll(0, mpsAlignedPayload(3, mps))
        ..fillRange(3 * mps, 3 * mps + 37, 0xAB);
      expect(await host.echo(payload), equals(payload));
    });
  });
}

import 'package:test/test.dart';

import 'common.dart';

const _epOut = 0x02;
const _epIn = 0x81;

void main() {
  withEchoGadget('I/O patterns', (pair) {
    const kBurst = 8;
    test(
      '$kBurst sequential echoes return correct data',
      () async {
        final host = pair().host;
        final mps = host.maxPacketSize;

        final payloads = List.generate(
          kBurst,
          (i) => Uint8List.fromList(
            List.generate(mps ~/ 2, (j) => (i * 3 + j) % 256),
          ),
        );

        final responses = await Future.wait(payloads.map((p) => host.echo(p)));

        for (var i = 0; i < kBurst; i++) {
          expect(responses[i], equals(payloads[i]), reason: 'echo $i mismatch');
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    const kBurstCount = 16;
    test(
      '$kBurstCount-buffer write-then-read burst',
      () async {
        final host = pair().host;
        final mps = host.maxPacketSize;

        final sent = List.generate(
          kBurstCount,
          (i) =>
              Uint8List.fromList(List.generate(mps ~/ 4, (j) => (i + j) % 256)),
        );

        for (final buf in sent) {
          await host.write(_epOut, buf);
        }

        for (var i = 0; i < kBurstCount; i++) {
          expect(
            await host.read(_epIn, size: mps),
            equals(sent[i]),
            reason: 'buffer $i must arrive in order',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}

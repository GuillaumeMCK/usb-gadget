import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:usb_gadget/usb_gadget.dart';

import '../common.dart' show ensureHardwareReady;
import 'helpers/host.dart';
import 'helpers/echo.dart';

export 'dart:typed_data' show Uint8List;
export 'helpers/host.dart';
export 'helpers/echo.dart';

class GadgetHostPair {
  GadgetHostPair._(this.reg, this.host);

  final RegGadget reg;
  final HostDevice host;

  static Future<GadgetHostPair> open(
    Future<RegGadget> Function() buildGadget,
  ) async {
    final reg = await buildGadget();
    try {
      final host = await HostDevice.open(vid: kVid, pid: kPid);
      try {
        await host.claim();
      } catch (_) {
        await host.release();
        rethrow;
      }
      return GadgetHostPair._(reg, host);
    } catch (_) {
      await teardownGadget(reg);
      rethrow;
    }
  }

  Future<void> close() async {
    await host.release();
    await teardownGadget(reg);
  }
}

void withEchoGadget(
  String description,
  void Function(GadgetHostPair Function() pair) body,
) {
  group(description, () {
    GadgetHostPair? _pair;

    setUpAll(() async {
      await ensureHardwareReady();
      _pair = await GadgetHostPair.open(buildEchoGadget);
    });

    tearDownAll(() => _pair?.close());

    body(() => _pair!);
  });
}

Uint8List mpsAlignedPayload(int count, int size) {
  final total = count * size;
  final result = Uint8List(total);
  for (var i = 0; i < total; i++) result[i] = i % 256;
  return result;
}

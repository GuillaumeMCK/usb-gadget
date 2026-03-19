import 'dart:io';

import 'package:test/test.dart';

import 'common.dart';

void main() {
  setUpAll(ensureHardwareReady);

  group('UvcFunction unit', () {
    test('configfsName is "uvc.{name}"', () {
      expect(UvcFunction(name: 'video0').configfsName, 'uvc.video0');
    });

    test('invalid streamingMaxpacket fails validate()', () {
      expect(
        UvcFunction(name: 'video0', streamingMaxpacket: 0).validate(),
        isFalse,
      );
    });

    test('invalid streamingInterval fails validate()', () {
      expect(
        UvcFunction(name: 'video0', streamingInterval: 0).validate(),
        isFalse,
      );
    });

    test('getConfigAttributes contains streaming_maxpacket', () {
      final attrs = UvcFunction(
        name: 'video0',
        streamingMaxpacket: 2048,
      ).getConfigAttributes();
      expect(attrs['streaming_maxpacket'], '2048');
    });
  });

  group('UvcFrame unit', () {
    test('UvcFrame.yuyv factory sets format to UvcFormat.yuyv', () {
      final frame = UvcFrame.yuyv(640, 480, [30]);
      expect(frame.format, UvcFormat.yuyv);
      expect(frame.width, 640);
      expect(frame.height, 480);
    });

    test('UvcFrame.mjpeg factory sets format to UvcFormat.mjpeg', () {
      expect(UvcFrame.mjpeg(1280, 720, [30]).format, UvcFormat.mjpeg);
    });

    test('UvcFrame.nv12 factory sets format to UvcFormat.framebased', () {
      final frame = UvcFrame.nv12(640, 480, [30]);
      expect(frame.format, UvcFormat.framebased);
      expect(frame.formatName, 'nv12');
    });

    test('UvcFrame.h264 factory sets format to UvcFormat.framebased', () {
      final frame = UvcFrame.h264(1920, 1080, [30]);
      expect(frame.format, UvcFormat.framebased);
      expect(frame.formatName, 'h264');
    });

    test('intervals convert fps to 100 ns units', () {
      // 30 fps → 10_000_000 / 30 = 333333
      expect(UvcFrame.yuyv(640, 480, [30]).intervals, [333333]);
    });
  });

  group('UvcColorMatching unit', () {
    test('stores primaries and coefficients', () {
      const cm = UvcColorMatching(
        colorPrimaries: 4,
        transferCharacteristics: 1,
        matrixCoefficients: 2,
      );
      expect(cm.colorPrimaries, 4);
      expect(cm.matrixCoefficients, 2);
    });
  });

  group('UvcFunction — integration', skip: !hasUDC || testUDC.isDummyUDC, () {
    RegGadget? reg;

    setUp(() async {
      final fn = UvcFunction(
        name: 'video0',
        frames: [
          UvcFrame.yuyv(640, 360, [15, 30]),
          UvcFrame.mjpeg(1280, 720, [30]),
        ],
      );
      reg = await kernelTestGadget('uvc_test', fn).register();
      await reg!.bind(testUDC);
    });

    tearDown(() async {
      try {
        await reg?.remove();
      } catch (_) {}
      reg = null;
    });

    test('gadget name is "uvc_test"', () {
      expect(reg!.name, 'uvc_test');
    });

    test('"uvc" driver is present in registered functions', () {
      expect(reg!.functions().map((f) => f.driver), contains('uvc'));
    });

    test('user-created frame dirs exist in configfs after register', () {
      final base =
          '/sys/kernel/config/usb_gadget/uvc_test/functions/uvc.video0';
      expect(
        Directory('$base/streaming/uncompressed/yuyv/360p').existsSync(),
        isTrue,
      );
      expect(
        Directory('$base/streaming/mjpeg/mjpeg/720p').existsSync(),
        isTrue,
      );
    });

    test(
      'down succeeds — _removeFrameDescriptors clears user-created dirs',
      () async {
        await expectLater(reg!.remove(), completes);
        expect(
          Directory('/sys/kernel/config/usb_gadget/uvc_test').existsSync(),
          isFalse,
        );
      },
    );
  });
}

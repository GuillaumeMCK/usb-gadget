import 'dart:io';

import 'base.dart';

/// USB Video Class (UVC) frame format.
///
/// Determines how frame data is structured in the configfs directory tree
/// and which streaming format class the kernel expects.
enum UvcFormat {
  /// YUYV (packed YUV) uncompressed format.
  yuyv,

  /// MJPEG compressed format.
  mjpeg,

  /// Framebased format with a custom GUID (e.g., NV12, H.264).
  framebased;

  String get _groupDir {
    return switch (this) {
      UvcFormat.yuyv => 'uncompressed',
      UvcFormat.mjpeg => 'mjpeg',
      UvcFormat.framebased => 'framebased',
    };
  }

  String get _name {
    return switch (this) {
      UvcFormat.yuyv => 'yuyv',
      UvcFormat.mjpeg => 'mjpeg',
      UvcFormat.framebased => 'framebased',
    };
  }
}

/// Frame color matching information for a UVC format.
///
/// Optional per-format color space metadata. If not provided, the UVC
/// specification default values are used.
class UvcColorMatching {
  const UvcColorMatching({
    this.colorPrimaries = 0,
    this.transferCharacteristics = 0,
    this.matrixCoefficients = 0,
  });

  /// Color primaries (ITU-R BT.601, BT.709, etc.)
  final int colorPrimaries;

  /// Transfer characteristics (gamma curve)
  final int transferCharacteristics;

  /// Matrix coefficients (Y'CbCr matrix)
  final int matrixCoefficients;
}

/// A UVC video frame configuration.
///
/// Describes a single width × height resolution with one or more frame rates.
///
/// Use [UvcFrameDescriptor] for advanced control over frame intervals and
/// color matching.
class UvcFrame {
  const UvcFrame({
    required this.width,
    required this.height,
    required this.fps,
    required this.format,
    this.bpp = 0,
    this.guid,
    this.formatName,
    this.colorMatching,
  });

  /// Creates a YUYV frame at the given resolution and frame rates.
  factory UvcFrame.yuyv(int width, int height, List<int> fps) =>
      UvcFrame(width: width, height: height, fps: fps, format: UvcFormat.yuyv);

  /// Creates an MJPEG frame at the given resolution and frame rates.
  factory UvcFrame.mjpeg(int width, int height, List<int> fps) =>
      UvcFrame(width: width, height: height, fps: fps, format: UvcFormat.mjpeg);

  /// Creates an NV12 framebased frame at the given resolution and frame rates.
  factory UvcFrame.nv12(int width, int height, List<int> fps) => UvcFrame(
    width: width,
    height: height,
    fps: fps,
    format: UvcFormat.framebased,
    guid: [
      0x4E, 0x56, 0x31, 0x32, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, //
      0xaa, 0x00, 0x38, 0x9b, 0x71, //
    ],
    formatName: 'nv12',
    bpp: 12,
  );

  /// Creates an H.264 framebased frame at the given resolution and frame rates.
  factory UvcFrame.h264(int width, int height, List<int> fps) => UvcFrame(
    width: width,
    height: height,
    fps: fps,
    format: UvcFormat.framebased,
    guid: [
      0x48, 0x32, 0x36, 0x34, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, //
      0xaa, 0x00, 0x38, 0x9b, 0x71, //
    ],
    formatName: 'h264',
    bpp: 0,
  );

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Frame rates in frames per second.
  final List<int> fps;

  /// Frame format.
  final UvcFormat format;

  /// Bits per pixel (for framebased formats). 0 for compressed.
  final int bpp;

  /// 16-byte GUID identifying the pixel format (for framebased formats).
  final List<int>? guid;

  /// Short name used for the configfs directory (for framebased formats).
  final String? formatName;

  /// Optional color matching information.
  final UvcColorMatching? colorMatching;

  String get _effectiveName {
    if (format == UvcFormat.framebased && formatName != null)
      return formatName!;
    return format._name;
  }

  String get groupPath => 'streaming/${format._groupDir}/$_effectiveName';

  String get _frameDirName => '${height}p';

  String get framePath => '$groupPath/$_frameDirName';

  String get headerLinkPath => 'streaming/header/h/$_effectiveName';

  String get _colorMatchingPath => 'streaming/color_matching/$_effectiveName';

  String get _colorMatchingLinkPath => '$groupPath/color_matching';

  /// Convert fps values to 100 ns interval units.
  List<int> get intervals => [
    ...fps.where((f) => f > 0).map((f) => 10000000 ~/ f),
  ];
}

/// UVC (USB Video Class) function for webcam emulation.
///
/// Requires a userspace program (such as `uvc-gadget`) to respond to UVC
/// control requests and fill V4L2 buffers.
///
/// ## Example
///
/// ```dart
/// final uvc = UvcFunction(
///   name: 'uvc',
///   frames: [
///     UvcFrame.yuyv(640, 480, [15, 30]),
///     UvcFrame.mjpeg(1280, 720, [30]),
///   ],
/// );
/// ```
class UvcFunction extends KernelFunction {
  UvcFunction({
    required super.name,
    this.frames = const [],
    this.streamingMaxpacket = 3072,
    this.streamingMaxburst = 0,
    this.streamingInterval = 1,
    this.processingControls,
    this.cameraControls,
    this.functionName,
  }) : super(kernelType: .uvc);

  /// Video frames to expose. Must contain at least one frame when binding.
  final List<UvcFrame> frames;

  /// Maximum packet size for streaming endpoint (valid: 1024, 2048, 3072)
  final int streamingMaxpacket;

  /// Maximum burst size (USB 3.0 only)
  final int streamingMaxburst;

  /// Streaming interval (1-16, frame rate related)
  final int streamingInterval;

  /// Processing Unit's bmControls field
  final int? processingControls;

  /// Camera Terminal's bmControls field
  final int? cameraControls;

  /// Video device interface name
  final String? functionName;

  @override
  bool validate() {
    if (streamingMaxpacket <= 0 || streamingMaxpacket > 3072) {
      log?.error('Invalid streaming_maxpacket: $streamingMaxpacket');
      return false;
    }
    if (streamingInterval < 1 || streamingInterval > 16) {
      log?.error('Invalid streaming_interval: $streamingInterval');
      return false;
    }
    return true;
  }

  // When frames are provided we must build the configfs directory structure
  // manually instead of just writing attributes.
  @override
  Future<void> prepare(String path) async {
    if (frames.isNotEmpty) {
      await super.prepare(path);
      _writeFrameDescriptors(path);
    } else {
      // legacy: no frames, just write basic attributes
      await super.prepare(path);
    }
  }

  @override
  Map<String, String> getConfigAttributes() {
    final attrs = <String, String>{
      'streaming_maxpacket': streamingMaxpacket.toString(),
      'streaming_maxburst': streamingMaxburst.toString(),
      'streaming_interval': streamingInterval.toString(),
    };
    if (functionName != null) attrs['function_name'] = functionName!;
    return attrs;
  }

  void _writeFrameDescriptors(String basePath) {
    for (final frame in frames) {
      // Create the frame resolution sub-directory.
      final frameDir = Directory('$basePath/${frame.framePath}');
      frameDir.createSync(recursive: true);

      // For framebased formats write the GUID.
      if (frame.format == UvcFormat.framebased && frame.guid != null) {
        File(
          '$basePath/${frame.groupPath}/guidFormat',
        ).writeAsBytesSync(frame.guid!);
      }

      File(
        '$basePath/${frame.framePath}/wWidth',
      ).writeAsStringSync(frame.width.toString());
      File(
        '$basePath/${frame.framePath}/wHeight',
      ).writeAsStringSync(frame.height.toString());

      if (frame.format == UvcFormat.framebased) {
        final bpl = frame.width * frame.bpp ~/ 8;
        File(
          '$basePath/${frame.framePath}/dwBytesPerLine',
        ).writeAsStringSync(bpl.toString());
      } else {
        final bufSize = frame.width * frame.height * 2;
        File(
          '$basePath/${frame.framePath}/dwMaxVideoFrameBufferSize',
        ).writeAsStringSync(bufSize.toString());
      }

      File(
        '$basePath/${frame.framePath}/dwFrameInterval',
      ).writeAsStringSync(frame.intervals.join('\n'));

      // Color matching (at most one per format).
      final cm = frame.colorMatching;
      if (cm != null) {
        final cmDir = Directory('$basePath/${frame._colorMatchingPath}');
        if (!cmDir.existsSync()) {
          cmDir.createSync(recursive: true);
          File(
            '$basePath/${frame._colorMatchingPath}/bColorPrimaries',
          ).writeAsStringSync(cm.colorPrimaries.toString());
          File(
            '$basePath/${frame._colorMatchingPath}/bTransferCharacteristics',
          ).writeAsStringSync(cm.transferCharacteristics.toString());
          File(
            '$basePath/${frame._colorMatchingPath}/bMatrixCoefficients',
          ).writeAsStringSync(cm.matrixCoefficients.toString());
          // Link color_matching into the format group dir.
          Link(
            '$basePath/${frame._colorMatchingLinkPath}',
          ).createSync('$basePath/${frame._colorMatchingPath}');
        }
      }
    }

    // Create streaming/control headers.
    Directory('$basePath/streaming/header/h').createSync(recursive: true);
    Directory('$basePath/control/header/h').createSync(recursive: true);

    // Link each format group into streaming/header/h.
    for (final frame in frames) {
      final linkPath = '$basePath/${frame.headerLinkPath}';
      if (!Link(linkPath).existsSync()) {
        Link(linkPath).createSync('$basePath/${frame.groupPath}');
      }
    }

    // Link headers into all speed classes.
    for (final cls in ['fs', 'hs', 'ss']) {
      final d = Directory('$basePath/streaming/class/$cls');
      d.createSync(recursive: true);
      final lk = Link('$basePath/streaming/class/$cls/h');
      if (!lk.existsSync()) lk.createSync('$basePath/streaming/header/h');
    }
    for (final cls in ['fs', 'ss']) {
      final d = Directory('$basePath/control/class/$cls');
      d.createSync(recursive: true);
      final lk = Link('$basePath/control/class/$cls/h');
      if (!lk.existsSync()) lk.createSync('$basePath/control/header/h');
    }

    // Processing Unit controls.
    if (processingControls != null) {
      File(
        '$basePath/control/processing/default/bmControls',
      ).writeAsStringSync(processingControls.toString());
    }

    // Camera Terminal controls.
    if (cameraControls != null) {
      File(
        '$basePath/control/terminal/camera/default/bmControls',
      ).writeAsStringSync(cameraControls.toString());
    }
  }

  /// Gets the V4L2 video device path (e.g., `/dev/video0`).
  ///
  /// Parses the `dev` attribute to get the minor number and constructs
  /// the device path. Returns `null` if not available.
  String? getVideoDevice() {
    if (!prepared) return null;

    try {
      final dev = readAttribute('dev');
      if (dev != null) {
        final parts = dev.trim().split(':');
        if (parts.length == 2) {
          final minor = int.tryParse(parts[1]);
          if (minor != null) {
            return '/dev/video$minor';
          }
        }
      }
    } catch (_) {
      // Ignore errors
    }

    return null;
  }
}
